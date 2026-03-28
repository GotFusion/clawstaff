#!/usr/bin/env python3
"""
ChatGPT adapter for TODO 3.2.

Features:
- retry with exponential backoff
- request timeout
- sliding-window rate limit
- request/response summary logging without raw prompt persistence
- offline text provider for no-API environments
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
import time
import uuid
from collections import deque
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Any
from urllib import error, request

from render_knowledge_prompts import (
    DEFAULT_OUTPUT_SCHEMA,
    DEFAULT_SYSTEM_TEMPLATE,
    DEFAULT_TASK_TEMPLATE,
    infer_semantic_target,
    load_json,
    load_text,
    render_task_prompt,
    sanitize_instruction_text,
)
from validate_knowledge_parse_output import (
    extract_json_from_text,
    validate_output,
    validate_with_knowledge_item,
)


TRANSIENT_HTTP_STATUS = {408, 409, 425, 429, 500, 502, 503, 504}
COMPONENT = "llm-adapter"


@dataclass
class AdapterError(Exception):
    message: str
    error_code: str
    retryable: bool = False

    def __str__(self) -> str:
        return self.message


class SlidingWindowRateLimiter:
    def __init__(self, max_requests: int, window_seconds: float = 60.0) -> None:
        if max_requests < 1:
            raise ValueError("max_requests must be >= 1")
        self.max_requests = max_requests
        self.window_seconds = window_seconds
        self._timestamps: deque[float] = deque()

    def wait_for_slot(self) -> float:
        now = time.monotonic()
        self._evict(now)
        if len(self._timestamps) < self.max_requests:
            self._timestamps.append(now)
            return 0.0

        sleep_for = self.window_seconds - (now - self._timestamps[0])
        if sleep_for > 0:
            time.sleep(sleep_for)
        now = time.monotonic()
        self._evict(now)
        self._timestamps.append(now)
        return max(0.0, sleep_for)

    def _evict(self, now: float) -> None:
        while self._timestamps and now - self._timestamps[0] >= self.window_seconds:
            self._timestamps.popleft()


class OpenAIProvider:
    def __init__(self, api_url: str, api_key: str, model: str) -> None:
        self.api_url = api_url
        self.api_key = api_key
        self.model = model

    def generate(self, system_prompt: str, user_prompt: str, timeout_seconds: float) -> str:
        payload = {
            "model": self.model,
            "temperature": 0,
            "response_format": {"type": "json_object"},
            "messages": [
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_prompt},
            ],
        }

        body = json.dumps(payload).encode("utf-8")
        req = request.Request(
            self.api_url,
            data=body,
            method="POST",
            headers={
                "Authorization": f"Bearer {self.api_key}",
                "Content-Type": "application/json",
            },
        )

        try:
            with request.urlopen(req, timeout=timeout_seconds) as response:
                response_body = response.read().decode("utf-8", errors="replace")
        except error.HTTPError as exc:
            raw = exc.read().decode("utf-8", errors="replace")
            raise AdapterError(
                message=f"OpenAI HTTP error {exc.code}: {shorten_text(raw, 300)}",
                error_code=f"LLM-HTTP-{exc.code}",
                retryable=exc.code in TRANSIENT_HTTP_STATUS,
            ) from exc
        except error.URLError as exc:
            raise AdapterError(
                message=f"OpenAI URL error: {exc.reason}",
                error_code="LLM-NETWORK-UNREACHABLE",
                retryable=True,
            ) from exc
        except TimeoutError as exc:
            raise AdapterError(
                message="OpenAI request timed out.",
                error_code="LLM-TIMEOUT",
                retryable=True,
            ) from exc

        try:
            parsed = json.loads(response_body)
            content = parsed["choices"][0]["message"]["content"]
        except (json.JSONDecodeError, KeyError, IndexError, TypeError) as exc:
            raise AdapterError(
                message=f"OpenAI response format invalid: {shorten_text(response_body, 300)}",
                error_code="LLM-RESPONSE-FORMAT-INVALID",
                retryable=True,
            ) from exc

        if not isinstance(content, str) or not content.strip():
            raise AdapterError(
                message="OpenAI response content is empty.",
                error_code="LLM-RESPONSE-EMPTY",
                retryable=True,
            )

        return content


class TextProvider:
    def __init__(self, knowledge_item: dict[str, Any], simulate_transient_failures: int) -> None:
        self.knowledge_item = knowledge_item
        self.remaining_failures = max(0, simulate_transient_failures)

    def generate(self, system_prompt: str, user_prompt: str, timeout_seconds: float) -> str:
        del system_prompt, user_prompt, timeout_seconds

        if self.remaining_failures > 0:
            self.remaining_failures -= 1
            raise AdapterError(
                message="Simulated transient failure in text provider.",
                error_code="LLM-SIMULATED-TRANSIENT-FAILURE",
                retryable=True,
            )

        output = build_text_provider_output(self.knowledge_item)
        return json.dumps(output, ensure_ascii=False, indent=2)


def build_text_provider_output(knowledge_item: dict[str, Any]) -> dict[str, Any]:
    context = knowledge_item.get("context", {})
    constraints = knowledge_item.get("constraints", [])
    source_steps = knowledge_item.get("steps", [])

    requires_confirmation = any(
        isinstance(constraint, dict)
        and constraint.get("type") == "manualConfirmationRequired"
        for constraint in constraints
    )

    output_steps: list[dict[str, Any]] = []
    recognized_actions = 0
    for step in source_steps:
        if not isinstance(step, dict):
            continue
        instruction = str(step.get("instruction", "")).strip()
        action_type = map_action_type(instruction)
        target = infer_target(step, action_type, context)
        if action_type != "unknown":
            recognized_actions += 1
        output_steps.append(
            {
                "stepId": step.get("stepId", "step-000"),
                "actionType": action_type,
                "instruction": sanitize_instruction_text(instruction) or "unknown",
                "target": target,
                "sourceEventIds": list(step.get("sourceEventIds", [])) or ["unknown"],
            }
        )

    if not output_steps:
        output_steps = [
            {
                "stepId": "step-000",
                "actionType": "unknown",
                "instruction": "unknown",
                "target": "unknown",
                "sourceEventIds": ["unknown"],
            }
        ]

    app_name = str(context.get("appName", "unknown")) or "unknown"
    app_bundle_id = str(context.get("appBundleId", "unknown")) or "unknown"
    window_title = context.get("windowTitle")
    safety_notes = [
        str(constraint.get("description", "unknown"))
        for constraint in constraints
        if isinstance(constraint, dict)
    ]
    if not safety_notes:
        safety_notes = ["unknown"]

    total_steps = len(output_steps)
    recognized_ratio = recognized_actions / total_steps if total_steps > 0 else 0.0
    context_bonus = 1.0 if app_name != "unknown" and app_bundle_id != "unknown" else 0.0
    confidence = round(min(0.95, 0.55 + 0.35 * recognized_ratio + 0.10 * context_bonus), 2)

    return {
        "schemaVersion": "llm.knowledge-parse.v0",
        "knowledgeItemId": str(knowledge_item.get("knowledgeItemId", "unknown")) or "unknown",
        "taskId": str(knowledge_item.get("taskId", "unknown")) or "unknown",
        "sessionId": str(knowledge_item.get("sessionId", "unknown")) or "unknown",
        "objective": str(knowledge_item.get("goal", "unknown")) or "unknown",
        "context": {
            "appName": app_name,
            "appBundleId": app_bundle_id,
            "windowTitle": window_title if window_title is None else str(window_title),
        },
        "executionPlan": {
            "requiresTeacherConfirmation": requires_confirmation,
            "steps": output_steps,
            "completionCriteria": {
                "expectedStepCount": len(output_steps),
                "requiredFrontmostAppBundleId": app_bundle_id,
            },
            "failurePolicy": {
                "onContextMismatch": "stopAndAskTeacher",
                "onStepError": "stopAndAskTeacher",
                "onUnknownAction": "stopAndAskTeacher",
            },
        },
        "safetyNotes": safety_notes,
        "confidence": confidence,
    }


def map_action_type(instruction: str) -> str:
    lower = instruction.lower()
    if "快捷键" in instruction or "shortcut" in lower:
        return "shortcut"
    if "输入" in instruction or "type" in lower:
        return "input"
    if "打开" in instruction or "open" in lower:
        return "openApp"
    if "等待" in instruction or "wait" in lower:
        return "wait"
    if "点击" in instruction or "click" in lower:
        return "click"
    return "unknown"


def infer_target(step: dict[str, Any], action_type: str, context: dict[str, Any]) -> str:
    semantic_target = infer_semantic_target(step, context)
    if semantic_target != "unknown":
        return semantic_target

    if action_type == "openApp":
        app_name = str(context.get("appName", "unknown"))
        return f"app:{app_name or 'unknown'}"

    return "unknown"


def iso_now() -> str:
    return datetime.now().astimezone().isoformat(timespec="seconds")


def hash_text(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def shorten_text(text: str, max_len: int) -> str:
    if len(text) <= max_len:
        return text
    return text[: max_len - 3] + "..."


def write_json_file(path: Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False, indent=2)
        f.write("\n")


def append_json_log(path: Path, record: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as f:
        f.write(json.dumps(record, ensure_ascii=False))
        f.write("\n")


def build_log_path(log_root: Path, session_id: str) -> Path:
    date_dir = datetime.now().astimezone().date().isoformat()
    return log_root / date_dir / f"{session_id}-llm-adapter.log"


def backoff_seconds(base: float, attempt: int) -> float:
    return base * (2 ** max(0, attempt - 1))


def validate_output_payload(
    payload: Any, knowledge_item: dict[str, Any], strict_knowledge_match: bool
) -> list[str]:
    errors = validate_output(payload)
    if strict_knowledge_match and isinstance(payload, dict):
        errors.extend(validate_with_knowledge_item(payload, knowledge_item))
    elif strict_knowledge_match:
        errors.append("Output JSON must be an object.")
    return errors


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="ChatGPT adapter with retry/timeout/rate-limit.")
    parser.add_argument(
        "--knowledge-item",
        required=True,
        type=Path,
        help="Path to input KnowledgeItem JSON.",
    )
    parser.add_argument(
        "--provider",
        choices=["text", "openai"],
        default="text",
        help="Provider mode. Use text mode for offline deterministic conversion.",
    )
    parser.add_argument(
        "--model",
        default="gpt-4.1-mini",
        help="Model name when provider=openai.",
    )
    parser.add_argument(
        "--api-url",
        default="https://api.openai.com/v1/chat/completions",
        help="OpenAI Chat Completions endpoint.",
    )
    parser.add_argument(
        "--api-key-env",
        default="OPENAI_API_KEY",
        help="Environment variable name for OpenAI API key.",
    )
    parser.add_argument(
        "--timeout-seconds",
        type=float,
        default=30.0,
        help="Per-request timeout seconds.",
    )
    parser.add_argument(
        "--max-retries",
        type=int,
        default=3,
        help="Maximum retry count after first attempt.",
    )
    parser.add_argument(
        "--retry-backoff-seconds",
        type=float,
        default=1.0,
        help="Retry exponential backoff base seconds.",
    )
    parser.add_argument(
        "--max-requests-per-minute",
        type=int,
        default=30,
        help="Rate limit in requests per minute.",
    )
    parser.add_argument(
        "--simulate-transient-failures",
        type=int,
        default=0,
        help="Only for provider=text. Number of transient failures before success.",
    )
    parser.add_argument(
        "--strict-knowledge-match",
        action="store_true",
        default=True,
        help="Require output to match source KnowledgeItem deterministic fields.",
    )
    parser.add_argument(
        "--no-strict-knowledge-match",
        action="store_false",
        dest="strict_knowledge_match",
        help="Disable deterministic cross-check against KnowledgeItem.",
    )
    parser.add_argument(
        "--system-template",
        default=DEFAULT_SYSTEM_TEMPLATE,
        type=Path,
        help=f"System prompt template path (default: {DEFAULT_SYSTEM_TEMPLATE}).",
    )
    parser.add_argument(
        "--task-template",
        default=DEFAULT_TASK_TEMPLATE,
        type=Path,
        help=f"Task prompt template path (default: {DEFAULT_TASK_TEMPLATE}).",
    )
    parser.add_argument(
        "--output-schema",
        default=DEFAULT_OUTPUT_SCHEMA,
        type=Path,
        help=f"Output schema path (default: {DEFAULT_OUTPUT_SCHEMA}).",
    )
    parser.add_argument(
        "--output",
        type=Path,
        help="Write normalized JSON output to file. If omitted, print to stdout.",
    )
    parser.add_argument(
        "--error-report",
        type=Path,
        help="Optional error report JSON output path.",
    )
    parser.add_argument(
        "--log-root",
        type=Path,
        default=Path("data/logs"),
        help="Structured log root directory.",
    )
    parser.add_argument(
        "--trace-id",
        help="Optional traceId. If omitted, auto-generate one.",
    )
    return parser.parse_args()


def create_provider(args: argparse.Namespace, knowledge_item: dict[str, Any]) -> Any:
    if args.provider == "text":
        return TextProvider(knowledge_item, args.simulate_transient_failures)

    api_key = os.environ.get(args.api_key_env, "").strip()
    if not api_key:
        raise AdapterError(
            message=f"Missing API key in environment variable: {args.api_key_env}",
            error_code="LLM-CONFIG-MISSING-API-KEY",
            retryable=False,
        )
    return OpenAIProvider(args.api_url, api_key, args.model)


def main() -> int:
    args = parse_args()

    if args.max_retries < 0:
        print("FAILED: LLM-CONFIG-INVALID max-retries must be >= 0", file=sys.stderr)
        return 1
    if args.timeout_seconds <= 0:
        print("FAILED: LLM-CONFIG-INVALID timeout-seconds must be > 0", file=sys.stderr)
        return 1
    if args.max_requests_per_minute < 1:
        print("FAILED: LLM-CONFIG-INVALID max-requests-per-minute must be >= 1", file=sys.stderr)
        return 1
    if args.retry_backoff_seconds < 0:
        print("FAILED: LLM-CONFIG-INVALID retry-backoff-seconds must be >= 0", file=sys.stderr)
        return 1

    knowledge_item_obj = load_json(args.knowledge_item)
    if not isinstance(knowledge_item_obj, dict):
        print("INVALID: KnowledgeItem must be a JSON object.", file=sys.stderr)
        return 1
    knowledge_item: dict[str, Any] = knowledge_item_obj

    system_prompt = load_text(args.system_template).strip() + "\n"
    task_template = load_text(args.task_template)
    output_schema = load_json(args.output_schema)
    user_prompt = render_task_prompt(task_template, knowledge_item, output_schema)

    trace_id = args.trace_id or f"trace-{uuid.uuid4().hex[:16]}"
    session_id = str(knowledge_item.get("sessionId", "unknown")) or "unknown"
    task_id = str(knowledge_item.get("taskId", "unknown")) or "unknown"
    log_path = build_log_path(args.log_root, session_id)

    request_summary = {
        "provider": args.provider,
        "model": args.model if args.provider == "openai" else "text-simulator-v0",
        "timeoutSeconds": args.timeout_seconds,
        "maxRetries": args.max_retries,
        "maxRequestsPerMinute": args.max_requests_per_minute,
        "promptFingerprint": {
            "systemSha256": hash_text(system_prompt),
            "systemChars": len(system_prompt),
            "userSha256": hash_text(user_prompt),
            "userChars": len(user_prompt),
        },
        "knowledgeSummary": {
            "knowledgeItemId": knowledge_item.get("knowledgeItemId"),
            "stepCount": len(knowledge_item.get("steps", []))
            if isinstance(knowledge_item.get("steps"), list)
            else 0,
            "constraintCount": len(knowledge_item.get("constraints", []))
            if isinstance(knowledge_item.get("constraints"), list)
            else 0,
            "appBundleId": knowledge_item.get("context", {}).get("appBundleId")
            if isinstance(knowledge_item.get("context"), dict)
            else None,
        },
    }

    limiter = SlidingWindowRateLimiter(args.max_requests_per_minute)
    try:
        provider = create_provider(args, knowledge_item)
    except AdapterError as exc:
        report = {
            "timestamp": iso_now(),
            "traceId": trace_id,
            "sessionId": session_id,
            "taskId": task_id,
            "component": COMPONENT,
            "status": "failed",
            "errorCode": exc.error_code,
            "message": str(exc),
        }
        if args.error_report:
            write_json_file(args.error_report, report)
        print(f"FAILED: {exc.error_code} {exc}", file=sys.stderr)
        return 1

    max_attempts = args.max_retries + 1
    failures: list[dict[str, Any]] = []

    for attempt in range(1, max_attempts + 1):
        throttled_seconds = limiter.wait_for_slot()
        started = time.monotonic()
        append_json_log(
            log_path,
            {
                "timestamp": iso_now(),
                "traceId": trace_id,
                "sessionId": session_id,
                "taskId": task_id,
                "component": COMPONENT,
                "status": "requestAttempt",
                "attempt": attempt,
                "requestSummary": request_summary,
                "rateLimitDelaySeconds": round(throttled_seconds, 3),
            },
        )

        try:
            response_text = provider.generate(system_prompt, user_prompt, args.timeout_seconds)
            parsed = extract_json_from_text(response_text)
            validation_errors = validate_output_payload(
                parsed, knowledge_item, strict_knowledge_match=args.strict_knowledge_match
            )
            if validation_errors:
                raise AdapterError(
                    message="; ".join(validation_errors),
                    error_code="KNO-VALIDATION-FAILED",
                    retryable=(args.provider == "openai"),
                )

            elapsed_ms = int((time.monotonic() - started) * 1000)
            output_payload = parsed
            if args.output:
                write_json_file(args.output, output_payload)
            else:
                print(json.dumps(output_payload, ensure_ascii=False, indent=2))

            append_json_log(
                log_path,
                {
                    "timestamp": iso_now(),
                    "traceId": trace_id,
                    "sessionId": session_id,
                    "taskId": task_id,
                    "component": COMPONENT,
                    "status": "success",
                    "attempt": attempt,
                    "requestSummary": request_summary,
                    "responseSummary": {
                        "responseSha256": hash_text(response_text),
                        "responseChars": len(response_text),
                        "durationMs": elapsed_ms,
                        "validationPassed": True,
                    },
                },
            )
            print(
                f"SUCCESS: provider={args.provider} attempts={attempt} log={log_path}",
                file=sys.stderr,
            )
            return 0
        except AdapterError as exc:
            elapsed_ms = int((time.monotonic() - started) * 1000)
            will_retry = exc.retryable and attempt < max_attempts
            failure = {
                "attempt": attempt,
                "errorCode": exc.error_code,
                "message": str(exc),
                "retryable": exc.retryable,
                "durationMs": elapsed_ms,
                "willRetry": will_retry,
            }
            failures.append(failure)

            append_json_log(
                log_path,
                {
                    "timestamp": iso_now(),
                    "traceId": trace_id,
                    "sessionId": session_id,
                    "taskId": task_id,
                    "component": COMPONENT,
                    "status": "failure",
                    "attempt": attempt,
                    "errorCode": exc.error_code,
                    "message": str(exc),
                    "requestSummary": request_summary,
                    "retryable": exc.retryable,
                    "willRetry": will_retry,
                    "durationMs": elapsed_ms,
                },
            )

            if will_retry:
                sleep_seconds = backoff_seconds(args.retry_backoff_seconds, attempt)
                time.sleep(sleep_seconds)
                continue

            report = {
                "timestamp": iso_now(),
                "traceId": trace_id,
                "sessionId": session_id,
                "taskId": task_id,
                "component": COMPONENT,
                "status": "failed",
                "errorCode": exc.error_code,
                "message": str(exc),
                "provider": args.provider,
                "attempts": attempt,
                "maxAttempts": max_attempts,
                "failures": failures,
                "logPath": str(log_path),
            }
            if args.error_report:
                write_json_file(args.error_report, report)
            print(f"FAILED: {exc.error_code} {exc}", file=sys.stderr)
            return 1
        except (ValueError, json.JSONDecodeError) as exc:
            error_message = f"Failed to parse provider output JSON: {exc}"
            will_retry = args.provider == "openai" and attempt < max_attempts
            failure = {
                "attempt": attempt,
                "errorCode": "KNO-JSON-PARSE-FAILED",
                "message": error_message,
                "retryable": args.provider == "openai",
                "willRetry": will_retry,
            }
            failures.append(failure)
            append_json_log(
                log_path,
                {
                    "timestamp": iso_now(),
                    "traceId": trace_id,
                    "sessionId": session_id,
                    "taskId": task_id,
                    "component": COMPONENT,
                    "status": "failure",
                    "attempt": attempt,
                    "errorCode": "KNO-JSON-PARSE-FAILED",
                    "message": error_message,
                    "requestSummary": request_summary,
                    "retryable": args.provider == "openai",
                    "willRetry": will_retry,
                },
            )
            if will_retry:
                sleep_seconds = backoff_seconds(args.retry_backoff_seconds, attempt)
                time.sleep(sleep_seconds)
                continue
            report = {
                "timestamp": iso_now(),
                "traceId": trace_id,
                "sessionId": session_id,
                "taskId": task_id,
                "component": COMPONENT,
                "status": "failed",
                "errorCode": "KNO-JSON-PARSE-FAILED",
                "message": error_message,
                "provider": args.provider,
                "attempts": attempt,
                "maxAttempts": max_attempts,
                "failures": failures,
                "logPath": str(log_path),
            }
            if args.error_report:
                write_json_file(args.error_report, report)
            print(f"FAILED: KNO-JSON-PARSE-FAILED {error_message}", file=sys.stderr)
            return 1

    print("FAILED: unexpected retry loop termination.", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
