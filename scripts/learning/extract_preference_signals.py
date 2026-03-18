#!/usr/bin/env python3
"""LLM-assisted structured preference hint extractor for Phase 11 TODO 11.2.3."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import re
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any
from urllib import error, request


REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT_DIR = Path(__file__).resolve().parent
DEFAULT_PROMPT_TEMPLATE = SCRIPT_DIR / "prompts" / "preference-hint-extractor.md"
DEFAULT_OUTPUT_SCHEMA = SCRIPT_DIR / "schemas" / "preference-extraction-output.schema.json"
DEFAULT_OUTPUT_ROOT = REPO_ROOT / "data" / "preferences"
DEFAULT_API_URL = "https://api.openai.com/v1/chat/completions"
DEFAULT_MODEL = "gpt-4.1-mini"
PROMPT_VERSION = "preference-hint-extractor.v1"
TRANSIENT_HTTP_STATUS = {408, 409, 425, 429, 500, 502, 503, 504}
TOP_LEVEL_KEYS = {"decision", "hint", "signalType", "scope", "confidence"}
SUPPORTED_DECISIONS = {"pass", "fail", "neutral"}
SUPPORTED_SIGNAL_TYPES = {"outcome", "procedure", "locator", "style", "risk", "repair"}
SUPPORTED_SCOPES = {"global", "app", "taskFamily", "skillFamily", "windowPattern"}
ACTIONABLE_HINT_MARKERS = {
    "请",
    "先",
    "再",
    "改",
    "更新",
    "避免",
    "保持",
    "确认",
    "检查",
    "使用",
    "重新",
    "补上",
    "限制",
    "修复",
    "replace",
    "update",
    "avoid",
    "keep",
    "confirm",
    "check",
    "use",
    "refresh",
    "retry",
    "replay",
    "require",
}
BANNED_HINT_PHRASES = {
    "not good",
    "be better",
    "better result",
    "improve quality",
    "needs improvement",
    "做得更好",
    "不够好",
    "体验不好",
    "注意一点",
    "优化一下",
}
RISK_TOKENS = {"danger", "dangerous", "risk", "blocked", "不要自动", "需确认", "确认后", "危险", "高风险"}
STYLE_TOKENS = {"style", "tone", "concise", "brief", "简洁", "啰嗦", "语气", "太长", "直接一点"}
PROCEDURE_TOKENS = {"order", "sequence", "first", "then", "before", "after", "顺序", "先", "再", "之后", "流程"}
LOCATOR_TOKENS = {"locator", "title", "text anchor", "button", "label", "定位", "标题", "按钮", "文案", "锚点"}
REPAIR_TOKENS = {"repair", "reteach", "retry", "fix", "refresh", "修复", "重教", "重试", "更新"}
POSITIVE_TOKENS = {"approved", "good", "works", "继续", "保持", "没问题", "通过"}


@dataclass
class ProviderError(Exception):
    message: str
    error_code: str
    retryable: bool = False

    def __str__(self) -> str:
        return self.message


@dataclass
class ExtractionContext:
    turn_path: Path
    evidence_path: Path
    turn: dict[str, Any]
    evidence: dict[str, Any]
    teacher_note: str
    teacher_note_source: str
    action_summary: str
    next_state_summary: str
    next_state_role: str
    prompt_version: str
    schema_path: Path
    task_family: str
    skill_family: str | None


class OpenAIProvider:
    def __init__(self, api_url: str, api_key: str, model: str) -> None:
        self.api_url = api_url
        self.api_key = api_key
        self.model = model
        self.name = "openai"

    def generate(
        self,
        *,
        system_prompt: str,
        user_prompt: str,
        context: ExtractionContext,
        timeout_seconds: float,
    ) -> str:
        del context
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
                raw = response.read().decode("utf-8", errors="replace")
        except error.HTTPError as exc:
            raw = exc.read().decode("utf-8", errors="replace")
            raise ProviderError(
                message=f"OpenAI HTTP error {exc.code}: {shorten_text(raw, 240)}",
                error_code=f"LLM-HTTP-{exc.code}",
                retryable=exc.code in TRANSIENT_HTTP_STATUS,
            ) from exc
        except error.URLError as exc:
            raise ProviderError(
                message=f"OpenAI URL error: {exc.reason}",
                error_code="LLM-NETWORK-UNREACHABLE",
                retryable=True,
            ) from exc
        except TimeoutError as exc:
            raise ProviderError(
                message="OpenAI request timed out.",
                error_code="LLM-TIMEOUT",
                retryable=True,
            ) from exc

        try:
            parsed = json.loads(raw)
            content = parsed["choices"][0]["message"]["content"]
        except (json.JSONDecodeError, KeyError, IndexError, TypeError) as exc:
            raise ProviderError(
                message=f"OpenAI response format invalid: {shorten_text(raw, 240)}",
                error_code="LLM-RESPONSE-FORMAT-INVALID",
                retryable=True,
            ) from exc

        if not isinstance(content, str) or not content.strip():
            raise ProviderError(
                message="OpenAI response content is empty.",
                error_code="LLM-RESPONSE-EMPTY",
                retryable=True,
            )

        return content


class MockResponsesProvider:
    def __init__(self, responses: list[str]) -> None:
        if not responses:
            raise ValueError("mock responses must not be empty")
        self.responses = responses
        self.index = 0
        self.name = "mock"
        self.model = "mock-votes"

    def generate(
        self,
        *,
        system_prompt: str,
        user_prompt: str,
        context: ExtractionContext,
        timeout_seconds: float,
    ) -> str:
        del system_prompt, user_prompt, context, timeout_seconds
        value = self.responses[self.index % len(self.responses)]
        self.index += 1
        return value


class HeuristicPreferenceProvider:
    def __init__(self) -> None:
        self.name = "heuristic"
        self.model = "heuristic-v1"

    def generate(
        self,
        *,
        system_prompt: str,
        user_prompt: str,
        context: ExtractionContext,
        timeout_seconds: float,
    ) -> str:
        del system_prompt, user_prompt, timeout_seconds
        note = normalize_free_text(context.teacher_note)
        summary = normalize_free_text(context.next_state_summary)
        combined = f"{note} {summary}".strip()

        if contains_any(combined, RISK_TOKENS):
            payload = {
                "decision": "fail",
                "hint": choose_hint(
                    context.teacher_note,
                    "Require teacher confirmation before auto-running similar steps in this app.",
                ),
                "signalType": "risk",
                "scope": "app",
                "confidence": 0.88,
            }
        elif contains_any(combined, STYLE_TOKENS):
            payload = {
                "decision": "fail",
                "hint": choose_hint(
                    context.teacher_note,
                    "Keep the reply concise and direct, and remove extra explanation next time.",
                ),
                "signalType": "style",
                "scope": "global",
                "confidence": 0.84,
            }
        elif contains_any(combined, PROCEDURE_TOKENS):
            payload = {
                "decision": "fail",
                "hint": choose_hint(
                    context.teacher_note,
                    "Adjust the step order first, and only continue after the prerequisite check succeeds.",
                ),
                "signalType": "procedure",
                "scope": "taskFamily",
                "confidence": 0.82,
            }
        elif contains_any(combined, LOCATOR_TOKENS):
            payload = {
                "decision": "fail",
                "hint": choose_hint(
                    context.teacher_note,
                    "Update the locator text or title anchor before replaying this step.",
                ),
                "signalType": "locator",
                "scope": "app",
                "confidence": 0.8,
            }
        elif contains_any(combined, REPAIR_TOKENS):
            payload = {
                "decision": "fail",
                "hint": choose_hint(
                    context.teacher_note,
                    "Repair the failing skill step first, then rerun the corrected path only once.",
                ),
                "signalType": "repair",
                "scope": "taskFamily",
                "confidence": 0.79,
            }
        elif contains_any(combined, POSITIVE_TOKENS):
            payload = {
                "decision": "pass",
                "hint": "Keep the current step order and reuse the same interaction pattern next time.",
                "signalType": "outcome",
                "scope": "taskFamily",
                "confidence": 0.77,
            }
        else:
            payload = {
                "decision": "neutral",
                "hint": "Review the teacher note manually and convert it into a concrete next-step correction.",
                "signalType": "procedure",
                "scope": "taskFamily",
                "confidence": 0.52,
            }

        return json.dumps(payload, ensure_ascii=False, indent=2)


def normalize_free_text(value: str | None) -> str:
    if not value:
        return ""
    return re.sub(r"\s+", " ", value.strip().lower())


def contains_any(text: str, tokens: set[str]) -> bool:
    return any(token in text for token in tokens)


def choose_hint(source_text: str, fallback: str) -> str:
    cleaned = re.sub(r"\s+", " ", source_text.strip())
    if cleaned and 1 <= sentence_count(cleaned) <= 3 and is_actionable_hint(cleaned):
        return cleaned
    return fallback


def load_text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def load_json(path: Path) -> Any:
    return json.loads(load_text(path))


def load_jsonl(path: Path) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for raw_line in load_text(path).splitlines():
        line = raw_line.strip()
        if not line:
            continue
        rows.append(json.loads(line))
    return rows


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def repo_relative(path: Path) -> str:
    resolved = path.resolve()
    try:
        return resolved.relative_to(REPO_ROOT).as_posix()
    except ValueError:
        return resolved.as_posix()


def sanitize_token(raw: str) -> str:
    token = "".join(ch if ch.isalnum() or ch in "-_" else "-" for ch in raw)
    return token or "item"


def date_key(timestamp: str) -> str:
    return timestamp[:10] if len(timestamp) >= 10 else "unknown-date"


def sha256_text(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def shorten_text(value: str, limit: int) -> str:
    compact = re.sub(r"\s+", " ", value.strip())
    if len(compact) <= limit:
        return compact
    return compact[: max(0, limit - 3)] + "..."


def sentence_count(text: str) -> int:
    normalized = re.sub(r"\s+", " ", text.strip())
    if not normalized:
        return 0
    pieces = [
        part.strip()
        for part in re.split(r"(?:[。！？!?]+|(?<!\d)\.(?=\s|$))", normalized)
        if part.strip()
    ]
    return len(pieces) if pieces else 1


def is_actionable_hint(text: str) -> bool:
    lowered = normalize_free_text(text)
    if not lowered:
        return False
    if any(phrase in lowered for phrase in BANNED_HINT_PHRASES):
        return False
    return any(marker in lowered for marker in ACTIONABLE_HINT_MARKERS)


def require_exact_keys(obj: Any, keys: set[str], path: str, errors: list[str]) -> None:
    if not isinstance(obj, dict):
        errors.append(f"{path} must be an object.")
        return
    current = set(obj.keys())
    missing = sorted(keys - current)
    extra = sorted(current - keys)
    if missing:
        errors.append(f"{path} missing keys: {', '.join(missing)}")
    if extra:
        errors.append(f"{path} has extra keys: {', '.join(extra)}")


def validate_output(payload: Any) -> list[str]:
    errors: list[str] = []
    require_exact_keys(payload, TOP_LEVEL_KEYS, "$", errors)
    if not isinstance(payload, dict):
        return errors

    if payload.get("decision") not in SUPPORTED_DECISIONS:
        errors.append("$.decision must be one of: pass, fail, neutral.")

    hint = payload.get("hint")
    if not isinstance(hint, str) or not hint.strip():
        errors.append("$.hint must be a non-empty string.")
    else:
        sentence_total = sentence_count(hint)
        if sentence_total < 1 or sentence_total > 3:
            errors.append("$.hint must contain between 1 and 3 sentences.")
        if not is_actionable_hint(hint):
            errors.append("$.hint must describe concrete executable guidance.")

    if payload.get("signalType") not in SUPPORTED_SIGNAL_TYPES:
        errors.append(
            "$.signalType must be one of: "
            + ", ".join(sorted(SUPPORTED_SIGNAL_TYPES))
            + "."
        )

    if payload.get("scope") not in SUPPORTED_SCOPES:
        errors.append(
            "$.scope must be one of: " + ", ".join(sorted(SUPPORTED_SCOPES)) + "."
        )

    confidence = payload.get("confidence")
    if not isinstance(confidence, (int, float)) or isinstance(confidence, bool):
        errors.append("$.confidence must be a number.")
    elif confidence < 0 or confidence > 1:
        errors.append("$.confidence must be between 0 and 1.")

    return errors


def extract_balanced_objects(text: str) -> list[str]:
    objects: list[str] = []
    depth = 0
    start_index: int | None = None
    in_string = False
    escaping = False

    for idx, ch in enumerate(text):
        if in_string:
            if escaping:
                escaping = False
            elif ch == "\\":
                escaping = True
            elif ch == '"':
                in_string = False
            continue

        if ch == '"':
            in_string = True
            continue

        if ch == "{":
            if depth == 0:
                start_index = idx
            depth += 1
            continue

        if ch == "}" and depth > 0:
            depth -= 1
            if depth == 0 and start_index is not None:
                objects.append(text[start_index : idx + 1])
                start_index = None

    return objects


def select_best_candidate(candidates: list[Any]) -> Any:
    dict_candidates = [item for item in candidates if isinstance(item, dict)]
    if not dict_candidates:
        return candidates[0]

    def score(payload: dict[str, Any]) -> int:
        keys = set(payload.keys())
        value = len(keys & TOP_LEVEL_KEYS)
        if payload.get("decision") in SUPPORTED_DECISIONS:
            value += 4
        if payload.get("signalType") in SUPPORTED_SIGNAL_TYPES:
            value += 4
        if payload.get("scope") in SUPPORTED_SCOPES:
            value += 4
        return value

    dict_candidates.sort(key=score, reverse=True)
    return dict_candidates[0]


def extract_json_from_text(text: str) -> Any:
    stripped = text.strip()
    try:
        return json.loads(stripped)
    except json.JSONDecodeError:
        pass

    fenced_blocks = re.findall(
        r"```(?:json)?\s*([\s\S]*?)\s*```", text, flags=re.IGNORECASE
    )
    for block in fenced_blocks:
        candidate = block.strip()
        if not candidate:
            continue
        try:
            return json.loads(candidate)
        except json.JSONDecodeError:
            continue

    parsed_candidates: list[Any] = []
    for candidate in extract_balanced_objects(text):
        try:
            parsed = json.loads(candidate)
        except json.JSONDecodeError:
            continue
        parsed_candidates.append(parsed)
        if isinstance(parsed, dict) and TOP_LEVEL_KEYS.issubset(set(parsed.keys())):
            return parsed

    if parsed_candidates:
        return select_best_candidate(parsed_candidates)

    raise ValueError("Cannot find valid JSON object in input text.")


def evidence_priority(row: dict[str, Any]) -> tuple[int, int]:
    source = row.get("source")
    order = {
        "teacherReview": 0,
        "chatgptSuggestion": 1,
        "driftDetection": 2,
        "replayVerify": 3,
        "executionRuntime": 4,
        "benchmarkResult": 5,
    }
    role_bonus = 0 if row.get("role") in {"directive", "mixed"} else 1
    return order.get(source, 99), role_bonus


def select_evidence(rows: list[dict[str, Any]], evidence_id: str | None) -> dict[str, Any]:
    if not rows:
        raise ValueError("evidence file is empty")
    if evidence_id:
        for row in rows:
            if row.get("evidenceId") == evidence_id:
                return row
        raise ValueError(f"cannot find evidenceId={evidence_id}")
    if len(rows) == 1:
        return rows[0]
    return sorted(rows, key=evidence_priority)[0]


def resolve_teacher_note(
    *,
    turn: dict[str, Any],
    evidence: dict[str, Any],
    explicit_note: str | None,
    note_file: Path | None,
) -> tuple[str, str]:
    if explicit_note and explicit_note.strip():
        return explicit_note.strip(), "cli.teacher-note"
    if note_file:
        return load_text(note_file).strip(), f"file:{repo_relative(note_file)}"

    review_note = (
        ((turn.get("review") or {}).get("note"))
        if isinstance(turn.get("review"), dict)
        else None
    )
    if isinstance(review_note, str) and review_note.strip():
        return review_note.strip(), "turn.review.note"

    for raw_ref in evidence.get("rawRefs", []):
        note = raw_ref.get("note")
        if isinstance(note, str) and note.strip():
            return note.strip(), "evidence.rawRefs.note"

    rationale = ((evidence.get("evaluativeCandidate") or {}).get("rationale"))
    if isinstance(rationale, str) and rationale.strip():
        return rationale.strip(), "evidence.evaluativeCandidate.rationale"

    directive_hint = ((evidence.get("directiveCandidate") or {}).get("hint"))
    if isinstance(directive_hint, str) and directive_hint.strip():
        return directive_hint.strip(), "evidence.directiveCandidate.hint"

    raise ValueError(
        "teacher note is missing; pass --teacher-note/--teacher-note-file or provide turn.review.note"
    )


def fallback_task_family(turn: dict[str, Any]) -> str:
    mode = str(turn.get("mode") or "unknown").strip() or "unknown"
    turn_kind = str(turn.get("turnKind") or "unknown").strip() or "unknown"
    return f"{mode}.{turn_kind}"


def derive_skill_family(turn: dict[str, Any]) -> str | None:
    execution = turn.get("execution") or {}
    for candidate in (
        execution.get("skillName"),
        Path(str(execution.get("skillDirectoryPath", ""))).name if execution.get("skillDirectoryPath") else None,
    ):
        if isinstance(candidate, str) and candidate.strip():
            return candidate.strip()
    return None


def build_context(
    *,
    turn_path: Path,
    evidence_path: Path,
    turn: dict[str, Any],
    evidence: dict[str, Any],
    teacher_note: str,
    teacher_note_source: str,
    schema_path: Path,
    task_family: str | None,
    skill_family: str | None,
) -> ExtractionContext:
    action_summary = str(turn.get("actionSummary") or turn.get("intentSummary") or "").strip()
    next_state_summary = str(evidence.get("summary") or "").strip()
    next_state_role = str(evidence.get("role") or "evaluative").strip()

    if not action_summary:
        raise ValueError("turn.actionSummary is required")
    if not next_state_summary:
        raise ValueError("evidence.summary is required")

    return ExtractionContext(
        turn_path=turn_path,
        evidence_path=evidence_path,
        turn=turn,
        evidence=evidence,
        teacher_note=teacher_note,
        teacher_note_source=teacher_note_source,
        action_summary=action_summary,
        next_state_summary=next_state_summary,
        next_state_role=next_state_role,
        prompt_version=PROMPT_VERSION,
        schema_path=schema_path,
        task_family=task_family or fallback_task_family(turn),
        skill_family=skill_family or derive_skill_family(turn),
    )


def render_user_prompt(context: ExtractionContext, output_schema: Any) -> str:
    payload = {
        "actionSummary": context.action_summary,
        "nextStateSummary": context.next_state_summary,
        "nextStateRole": context.next_state_role,
        "teacherNote": context.teacher_note,
    }
    schema_json = json.dumps(output_schema, ensure_ascii=False, indent=2, sort_keys=True)
    input_json = json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True)
    return (
        "请根据固定 schema 输出 JSON，不要输出解释。\n\n"
        "输出 schema：\n"
        f"```json\n{schema_json}\n```\n\n"
        "输入：\n"
        f"```json\n{input_json}\n```"
    )


def call_provider_with_retries(
    provider: Any,
    *,
    system_prompt: str,
    user_prompt: str,
    context: ExtractionContext,
    timeout_seconds: float,
    max_attempts: int = 3,
) -> str:
    attempt = 0
    while True:
        attempt += 1
        try:
            return provider.generate(
                system_prompt=system_prompt,
                user_prompt=user_prompt,
                context=context,
                timeout_seconds=timeout_seconds,
            )
        except ProviderError as exc:
            if (
                attempt >= max_attempts
                or not getattr(provider, "name", "").startswith("openai")
                or not exc.retryable
            ):
                raise
            time.sleep(0.5 * (2 ** (attempt - 1)))


def normalize_hint_for_vote(hint: str) -> str:
    lowered = hint.strip().lower()
    lowered = re.sub(r"[`'\"“”‘’.,;:!?。！？、，（）()\\[\\]{}<>]+", " ", lowered)
    lowered = re.sub(r"\s+", " ", lowered)
    return lowered.strip()


def vote_key(payload: dict[str, Any]) -> str:
    return "|".join(
        [
            str(payload["decision"]),
            str(payload["signalType"]),
            str(payload["scope"]),
            normalize_hint_for_vote(str(payload["hint"])),
        ]
    )


def build_scope_reference(context: ExtractionContext, scope_level: str) -> dict[str, Any]:
    turn = context.turn
    app_context = turn.get("appContext") or {}
    if scope_level == "global":
        return {"level": "global"}
    if scope_level == "app":
        return {
            "level": "app",
            "appBundleId": app_context.get("appBundleId"),
            "appName": app_context.get("appName"),
        }
    if scope_level == "taskFamily":
        return {"level": "taskFamily", "taskFamily": context.task_family}
    if scope_level == "skillFamily":
        return {"level": "skillFamily", "skillFamily": context.skill_family}

    window_title = app_context.get("windowTitle")
    return {
        "level": "windowPattern",
        "appBundleId": app_context.get("appBundleId"),
        "appName": app_context.get("appName"),
        "windowPattern": f"^{re.escape(window_title)}$" if window_title else None,
    }


def proposed_action_for(signal_type: str, decision: str) -> str | None:
    if signal_type == "locator":
        return "repair_locator"
    if signal_type == "style":
        return "adjust_style"
    if signal_type == "procedure":
        return "adjust_procedure"
    if signal_type == "risk":
        return "require_teacher_confirmation"
    if signal_type == "repair":
        return "repair_skill"
    if signal_type == "outcome" and decision == "pass":
        return "reuse_successful_pattern"
    return None


def candidate_signal_payload(
    *,
    context: ExtractionContext,
    result: dict[str, Any],
) -> dict[str, Any]:
    decision = result["decision"]
    polarity = {"pass": "reinforce", "fail": "discourage", "neutral": "neutral"}[decision]
    return {
        "type": result["signalType"],
        "evaluativeDecision": decision,
        "polarity": polarity,
        "scope": build_scope_reference(context, result["scope"]),
        "hint": result["hint"],
        "confidence": result["confidence"],
        "evidenceIds": [context.evidence["evidenceId"]],
        "proposedAction": proposed_action_for(result["signalType"], decision),
        "promotionStatus": "candidate",
    }


def majority_decision(
    *,
    votes: list[dict[str, Any]],
    minimum_confidence: float,
    threshold: int,
) -> tuple[dict[str, Any], dict[str, Any] | None]:
    valid_votes = [vote for vote in votes if vote["status"] == "accepted"]
    if not valid_votes:
        return {
            "status": "needs_review",
            "reason": "no_valid_votes",
            "majorityCount": 0,
            "threshold": threshold,
            "decision": None,
            "hint": None,
            "signalType": None,
            "scope": None,
            "confidence": 0.0,
        }, None

    grouped: dict[str, list[dict[str, Any]]] = {}
    for vote in valid_votes:
        key = vote_key(vote["structuredOutput"])
        grouped.setdefault(key, []).append(vote)

    winner_key, winner_votes = max(grouped.items(), key=lambda item: len(item[1]))
    del winner_key
    candidate = dict(winner_votes[0]["structuredOutput"])
    candidate_confidence = round(
        sum(float(item["structuredOutput"]["confidence"]) for item in winner_votes) / len(winner_votes),
        3,
    )
    candidate["confidence"] = candidate_confidence

    if len(winner_votes) < threshold:
        return {
            "status": "needs_review",
            "reason": "no_majority",
            "majorityCount": len(winner_votes),
            "threshold": threshold,
            "decision": candidate["decision"],
            "hint": candidate["hint"],
            "signalType": candidate["signalType"],
            "scope": candidate["scope"],
            "confidence": candidate_confidence,
        }, candidate

    if candidate_confidence < minimum_confidence:
        return {
            "status": "needs_review",
            "reason": "low_confidence",
            "majorityCount": len(winner_votes),
            "threshold": threshold,
            "decision": candidate["decision"],
            "hint": candidate["hint"],
            "signalType": candidate["signalType"],
            "scope": candidate["scope"],
            "confidence": candidate_confidence,
        }, candidate

    return {
        "status": "accepted",
        "reason": "majority_vote",
        "majorityCount": len(winner_votes),
        "threshold": threshold,
        "decision": candidate["decision"],
        "hint": candidate["hint"],
        "signalType": candidate["signalType"],
        "scope": candidate["scope"],
        "confidence": candidate_confidence,
    }, candidate


def output_path_for(output_root: Path, report: dict[str, Any]) -> Path:
    result = report["result"]
    bucket = "extractions" if result["status"] == "accepted" else "needs-review"
    source = report["source"]
    date_directory = date_key(source["evidenceTimestamp"])
    filename = (
        f"{sanitize_token(report['input']['turnId'])}"
        f"--{sanitize_token(source['evidenceId'])}.json"
    )
    return output_root / bucket / date_directory / report["input"]["sessionId"] / filename


def build_report(
    *,
    context: ExtractionContext,
    provider: Any,
    model_name: str | None,
    prompt_path: Path,
    user_prompt: str,
    votes: list[dict[str, Any]],
    result: dict[str, Any],
    candidate_signal: dict[str, Any] | None,
) -> dict[str, Any]:
    input_payload = {
        "turnId": context.turn["turnId"],
        "traceId": context.turn.get("traceId"),
        "sessionId": context.turn["sessionId"],
        "taskId": context.turn["taskId"],
        "stepId": context.turn["stepId"],
        "actionSummary": context.action_summary,
        "nextStateSummary": context.next_state_summary,
        "nextStateRole": context.next_state_role,
        "teacherNote": context.teacher_note,
        "taskFamily": context.task_family,
    }
    if context.skill_family:
        input_payload["skillFamily"] = context.skill_family

    report = {
        "schemaVersion": "openstaff.learning.preference-extraction-report.v1",
        "promptVersion": context.prompt_version,
        "createdAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "source": {
            "turnPath": repo_relative(context.turn_path),
            "evidencePath": repo_relative(context.evidence_path),
            "evidenceId": context.evidence["evidenceId"],
            "evidenceSource": context.evidence["source"],
            "evidenceTimestamp": context.evidence["timestamp"],
            "teacherNoteSource": context.teacher_note_source,
            "provider": getattr(provider, "name", "unknown"),
            "model": model_name,
            "promptPath": repo_relative(prompt_path),
            "schemaPath": repo_relative(context.schema_path),
            "inputHash": sha256_text(json.dumps(input_payload, ensure_ascii=False, sort_keys=True)),
            "userPromptHash": sha256_text(user_prompt),
        },
        "input": input_payload,
        "votes": votes,
        "result": result,
        "candidateSignal": candidate_signal,
    }
    return report


def parse_mock_responses(path: Path) -> list[str]:
    raw = load_text(path).strip()
    if not raw:
        raise ValueError("mock responses file is empty")
    try:
        parsed = json.loads(raw)
    except json.JSONDecodeError:
        parsed = None

    if isinstance(parsed, list):
        values = []
        for item in parsed:
            if isinstance(item, str):
                values.append(item)
            else:
                values.append(json.dumps(item, ensure_ascii=False))
        return values

    responses = [line.strip() for line in raw.splitlines() if line.strip()]
    return responses


def build_provider(args: argparse.Namespace) -> Any:
    if args.provider == "mock":
        if not args.mock_responses:
            raise ValueError("--mock-responses is required when --provider=mock")
        return MockResponsesProvider(parse_mock_responses(args.mock_responses))

    if args.provider == "heuristic":
        return HeuristicPreferenceProvider()

    api_key = args.api_key or os.environ.get("OPENAI_API_KEY")
    if args.provider == "auto" and not api_key:
        return HeuristicPreferenceProvider()

    if not api_key:
        raise ValueError("OPENAI_API_KEY is required when using the OpenAI provider")

    return OpenAIProvider(
        api_url=args.api_url,
        api_key=api_key,
        model=args.model,
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Extract structured preference hints from turn/evidence/teacher-note context."
    )
    parser.add_argument("--turn", required=True, type=Path, help="Path to InteractionTurn JSON.")
    parser.add_argument("--evidence", required=True, type=Path, help="Path to NextStateEvidence JSONL.")
    parser.add_argument("--evidence-id", help="Optional evidenceId to pick from the JSONL file.")
    parser.add_argument("--teacher-note", help="Explicit teacher note override.")
    parser.add_argument("--teacher-note-file", type=Path, help="Optional file containing the teacher note.")
    parser.add_argument("--task-family", help="Optional taskFamily override for hydrated candidate scope.")
    parser.add_argument("--skill-family", help="Optional skillFamily override for hydrated candidate scope.")
    parser.add_argument(
        "--provider",
        choices=["auto", "openai", "heuristic", "mock"],
        default="auto",
        help="LLM provider. auto falls back to heuristic when OPENAI_API_KEY is absent.",
    )
    parser.add_argument("--mock-responses", type=Path, help="JSON/JSONL file with mock vote outputs.")
    parser.add_argument("--api-url", default=DEFAULT_API_URL, help="OpenAI compatible chat completions URL.")
    parser.add_argument("--api-key", help="OpenAI API key. Defaults to OPENAI_API_KEY.")
    parser.add_argument("--model", default=os.environ.get("OPENAI_MODEL", DEFAULT_MODEL), help="Model name.")
    parser.add_argument("--votes", type=int, default=3, help="Number of extraction votes (default: 3).")
    parser.add_argument(
        "--minimum-confidence",
        type=float,
        default=0.75,
        help="Majority confidence floor before accepting output (default: 0.75).",
    )
    parser.add_argument(
        "--prompt-template",
        type=Path,
        default=DEFAULT_PROMPT_TEMPLATE,
        help=f"Prompt template path (default: {DEFAULT_PROMPT_TEMPLATE}).",
    )
    parser.add_argument(
        "--output-schema",
        type=Path,
        default=DEFAULT_OUTPUT_SCHEMA,
        help=f"Output schema path (default: {DEFAULT_OUTPUT_SCHEMA}).",
    )
    parser.add_argument("--output-root", type=Path, help="Optional root for accepted/needs-review reports.")
    parser.add_argument(
        "--timeout-seconds",
        type=float,
        default=45.0,
        help="Request timeout for each provider call (default: 45).",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.votes < 1:
        raise SystemExit("--votes must be >= 1")
    if args.minimum_confidence < 0 or args.minimum_confidence > 1:
        raise SystemExit("--minimum-confidence must be between 0 and 1")

    turn = load_json(args.turn)
    evidence_rows = load_jsonl(args.evidence)
    evidence = select_evidence(evidence_rows, args.evidence_id)
    teacher_note, teacher_note_source = resolve_teacher_note(
        turn=turn,
        evidence=evidence,
        explicit_note=args.teacher_note,
        note_file=args.teacher_note_file,
    )

    context = build_context(
        turn_path=args.turn,
        evidence_path=args.evidence,
        turn=turn,
        evidence=evidence,
        teacher_note=teacher_note,
        teacher_note_source=teacher_note_source,
        schema_path=args.output_schema,
        task_family=args.task_family,
        skill_family=args.skill_family,
    )

    prompt_template = load_text(args.prompt_template).strip() + "\n"
    output_schema = load_json(args.output_schema)
    user_prompt = render_user_prompt(context, output_schema)
    provider = build_provider(args)
    threshold = math.floor(args.votes / 2) + 1

    votes: list[dict[str, Any]] = []
    for vote_index in range(1, args.votes + 1):
        raw_response_hash = None
        try:
            raw_response = call_provider_with_retries(
                provider,
                system_prompt=prompt_template,
                user_prompt=user_prompt,
                context=context,
                timeout_seconds=args.timeout_seconds,
            )
            raw_response_hash = sha256_text(raw_response)
            structured_output = extract_json_from_text(raw_response)
            errors = validate_output(structured_output)
            if errors:
                votes.append(
                    {
                        "voteIndex": vote_index,
                        "status": "invalid",
                        "rawResponseHash": raw_response_hash,
                        "errors": errors,
                    }
                )
                continue

            votes.append(
                {
                    "voteIndex": vote_index,
                    "status": "accepted",
                    "rawResponseHash": raw_response_hash,
                    "errors": [],
                    "structuredOutput": structured_output,
                }
            )
        except ProviderError as exc:
            votes.append(
                {
                    "voteIndex": vote_index,
                    "status": "provider_error",
                    "rawResponseHash": raw_response_hash,
                    "errors": [f"{exc.error_code}: {exc.message}"],
                }
            )
        except Exception as exc:
            votes.append(
                {
                    "voteIndex": vote_index,
                    "status": "invalid",
                    "rawResponseHash": raw_response_hash,
                    "errors": [str(exc)],
                }
            )

    result, accepted_candidate = majority_decision(
        votes=votes,
        minimum_confidence=args.minimum_confidence,
        threshold=threshold,
    )
    candidate_signal = (
        candidate_signal_payload(context=context, result=result)
        if result["status"] == "accepted" and accepted_candidate
        else None
    )

    report = build_report(
        context=context,
        provider=provider,
        model_name=getattr(provider, "model", args.model if provider.name == "openai" else None),
        prompt_path=args.prompt_template,
        user_prompt=user_prompt,
        votes=votes,
        result=result,
        candidate_signal=candidate_signal,
    )

    if args.output_root:
        output_path = output_path_for(args.output_root, report)
        write_json(output_path, report)
        report["outputPath"] = repo_relative(output_path)

    print(json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
