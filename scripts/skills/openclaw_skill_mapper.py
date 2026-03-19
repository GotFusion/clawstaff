#!/usr/bin/env python3
"""
Map KnowledgeItem + LLM output to OpenClaw skill folder format.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from datetime import datetime
from pathlib import Path
from typing import Any


SCRIPT_DIR = Path(__file__).resolve().parent
TEMPLATES_DIR = SCRIPT_DIR / "templates"
LLM_DIR = SCRIPT_DIR.parent / "llm"
if str(LLM_DIR) not in sys.path:
    sys.path.insert(0, str(LLM_DIR))

from validate_knowledge_parse_output import extract_json_from_text, validate_output


SCHEMA_VERSION = "openstaff.openclaw-skill.v1"
GENERATOR_VERSION = "openstaff-skill-mapper-v1.1"
REPAIR_VERSION = 0
ACTION_TYPES = {"openApp", "click", "input", "shortcut", "wait", "unknown"}
GUI_ACTION_TYPES = {"click", "input"}
NATIVE_ACTION_TYPES = {"openApp", "shortcut", "wait"}
DEFAULT_NATIVE_STRATEGY_ORDER = ["shortcuts", "applescript", "cli", "app_adapter"]
GUI_LOCATOR_STRATEGY_ORDER = [
    "ax",
    "textAnchor",
    "imageAnchor",
    "relativeCoordinate",
    "absoluteCoordinate",
]


def iso_now() -> str:
    return datetime.now().astimezone().isoformat(timespec="seconds")


def read_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def read_text(path: Path) -> str:
    with path.open("r", encoding="utf-8") as f:
        return f.read()


def write_json(path: Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False, indent=2)
        f.write("\n")


def write_text(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as f:
        f.write(content.rstrip() + "\n")


def slugify(value: str, fallback: str) -> str:
    normalized = value.strip().lower()
    normalized = re.sub(r"[^a-z0-9_-]+", "-", normalized)
    normalized = re.sub(r"-{2,}", "-", normalized).strip("-")
    if not normalized:
        normalized = fallback
    return normalized[:64]


def sanitize_skill_name(task_id: str, override: str | None = None) -> str:
    base = override if override is not None else f"openstaff-{task_id}"
    return slugify(base, "openstaff-skill")


def infer_action_type(instruction: str) -> str:
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


def infer_target(instruction: str, action_type: str, app_name: str) -> str:
    pattern_xy = re.search(r"x\s*=\s*(\d+)\s*[,，]\s*y\s*=\s*(\d+)", instruction, flags=re.IGNORECASE)
    if pattern_xy:
        return f"coordinate:{pattern_xy.group(1)},{pattern_xy.group(2)}"

    pattern_tuple = re.search(r"\((\d+)\s*,\s*(\d+)\)", instruction)
    if pattern_tuple:
        return f"coordinate:{pattern_tuple.group(1)},{pattern_tuple.group(2)}"

    if action_type == "openApp":
        return f"app:{app_name or 'unknown'}"

    return "unknown"


def infer_coordinate(instruction: str) -> dict[str, Any] | None:
    pattern_xy = re.search(r"x\s*=\s*(\d+)\s*[,，]\s*y\s*=\s*(\d+)", instruction, flags=re.IGNORECASE)
    if pattern_xy:
        return {
            "x": int(pattern_xy.group(1)),
            "y": int(pattern_xy.group(2)),
            "coordinateSpace": "screen",
        }

    pattern_tuple = re.search(r"\((\d+)\s*,\s*(\d+)\)", instruction)
    if pattern_tuple:
        return {
            "x": int(pattern_tuple.group(1)),
            "y": int(pattern_tuple.group(2)),
            "coordinateSpace": "screen",
        }

    return None


def manual_confirmation_required(constraints: list[dict[str, Any]]) -> bool:
    return any(c.get("type") == "manualConfirmationRequired" for c in constraints)


def normalize_string(value: Any, fallback: str = "unknown") -> str:
    if isinstance(value, str) and value.strip():
        return value.strip()
    if value is None:
        return fallback
    text = str(value).strip()
    return text or fallback


def normalize_string_list(value: Any, fallback: list[str] | None = None) -> list[str]:
    if isinstance(value, list):
        normalized = [str(item).strip() for item in value if str(item).strip()]
        if normalized:
            return normalized
    if fallback is None:
        return ["unknown"]
    return list(fallback)


def normalize_non_negative_int(value: Any, fallback: int = 0) -> int:
    try:
        return max(0, int(value))
    except (TypeError, ValueError):
        return fallback


def normalize_bool(value: Any, fallback: bool = False) -> bool:
    if isinstance(value, bool):
        return value
    if isinstance(value, str):
        lowered = value.strip().lower()
        if lowered in {"true", "1", "yes"}:
            return True
        if lowered in {"false", "0", "no"}:
            return False
    return fallback


def normalize_float(value: Any, fallback: float = 0.0) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        return fallback


def normalize_optional_string(value: Any) -> str | None:
    if isinstance(value, str) and value.strip():
        return value.strip()
    return None


def normalize_token(value: str | None) -> str:
    return re.sub(r"[^a-z0-9]+", "", (value or "").strip().lower())


def unique_strings(values: list[str]) -> list[str]:
    ordered: list[str] = []
    seen: set[str] = set()
    for value in values:
        normalized = value.strip()
        if not normalized or normalized in seen:
            continue
        seen.add(normalized)
        ordered.append(normalized)
    return ordered


def contains_any_token(value: str | None, tokens: list[str]) -> bool:
    lowered = (value or "").lower()
    return any(token in lowered for token in tokens)


def repository_relative(path: Path) -> str:
    try:
        return path.relative_to(SCRIPT_DIR.parent.parent).as_posix()
    except ValueError:
        return path.as_posix()


def render_template(path: Path, values: dict[str, str]) -> str:
    template = read_text(path)

    def replace(match: re.Match[str]) -> str:
        key = match.group(1)
        return values.get(key, "")

    return re.sub(r"{{\s*([a-zA-Z0-9_]+)\s*}}", replace, template)


def validate_knowledge_item(knowledge_item: Any) -> list[str]:
    errors: list[str] = []
    if not isinstance(knowledge_item, dict):
        return ["KnowledgeItem must be a JSON object."]

    required = [
        "knowledgeItemId",
        "taskId",
        "sessionId",
        "goal",
        "summary",
        "steps",
        "context",
        "constraints",
    ]
    for key in required:
        if key not in knowledge_item:
            errors.append(f"KnowledgeItem missing required key: {key}")

    steps = knowledge_item.get("steps")
    if not isinstance(steps, list) or len(steps) == 0:
        errors.append("KnowledgeItem.steps must be a non-empty array.")
    else:
        for i, step in enumerate(steps):
            if not isinstance(step, dict):
                errors.append(f"KnowledgeItem.steps[{i}] must be an object.")
                continue
            if not isinstance(step.get("stepId"), str) or not step["stepId"].strip():
                errors.append(f"KnowledgeItem.steps[{i}].stepId must be a non-empty string.")
            if not isinstance(step.get("instruction"), str) or not step["instruction"].strip():
                errors.append(f"KnowledgeItem.steps[{i}].instruction must be a non-empty string.")
            source_event_ids = step.get("sourceEventIds")
            if not isinstance(source_event_ids, list) or len(source_event_ids) == 0:
                errors.append(f"KnowledgeItem.steps[{i}].sourceEventIds must be a non-empty array.")

    context = knowledge_item.get("context")
    if not isinstance(context, dict):
        errors.append("KnowledgeItem.context must be an object.")
    else:
        if not isinstance(context.get("appName"), str) or not context["appName"].strip():
            errors.append("KnowledgeItem.context.appName must be a non-empty string.")
        if not isinstance(context.get("appBundleId"), str) or not context["appBundleId"].strip():
            errors.append("KnowledgeItem.context.appBundleId must be a non-empty string.")

    constraints = knowledge_item.get("constraints")
    if not isinstance(constraints, list) or len(constraints) == 0:
        errors.append("KnowledgeItem.constraints must be a non-empty array.")

    return errors


def looks_like_knowledge_item(payload: Any) -> bool:
    if not isinstance(payload, dict):
        return False
    keys = set(payload.keys())
    required = {"goal", "summary", "constraints", "steps", "context"}
    return required.issubset(keys)


def looks_like_json_schema(payload: Any) -> bool:
    if not isinstance(payload, dict):
        return False
    return "$schema" in payload and "properties" in payload


def parse_llm_output(llm_path: Path) -> tuple[Any | None, list[str]]:
    text = read_text(llm_path)
    diagnostics: list[str] = []
    prompt_package_markers = (
        "【OpenStaff 手动 ChatGPT 转换包】" in text
        and "=== SYSTEM PROMPT ===" in text
        and "=== USER PROMPT ===" in text
    )

    try:
        parsed = extract_json_from_text(text)
    except Exception as exc:
        if prompt_package_markers:
            diagnostics.append(
                "检测到输入包含 OpenStaff 转换包提示词。请粘贴 ChatGPT 最终返回的 JSON，不要粘贴提示词包。"
            )
        diagnostics.append(f"Failed to extract JSON from LLM output: {exc}")
        return None, diagnostics

    if looks_like_knowledge_item(parsed):
        diagnostics.append(
            "检测到输入是 KnowledgeItem/提示词数据，而不是 ChatGPT 返回的结构化 JSON。"
        )
        return parsed, diagnostics

    if looks_like_json_schema(parsed):
        diagnostics.append(
            "检测到输入是 JSON Schema，而不是 ChatGPT 返回的结构化 JSON。"
        )
        return parsed, diagnostics

    errors = validate_output(parsed)
    if errors:
        if prompt_package_markers:
            diagnostics.append(
                "检测到输入包含 OpenStaff 转换包提示词。请确认结果框中仅保留 ChatGPT 输出 JSON。"
            )
        diagnostics.extend([f"LLM output schema validation failed: {error}" for error in errors])
        return parsed, diagnostics

    return parsed, diagnostics


def normalize_execution_plan(
    knowledge_item: dict[str, Any],
    llm_output: dict[str, Any] | None,
    llm_valid: bool,
) -> tuple[dict[str, Any], list[str]]:
    diagnostics: list[str] = []
    context = knowledge_item.get("context", {})
    knowledge_steps = knowledge_item.get("steps", [])
    constraints = knowledge_item.get("constraints", [])

    llm_context = llm_output.get("context", {}) if llm_valid and llm_output else {}
    llm_plan = llm_output.get("executionPlan", {}) if llm_valid and llm_output else {}
    llm_steps = llm_plan.get("steps", []) if isinstance(llm_plan, dict) else []
    llm_steps = llm_steps if isinstance(llm_steps, list) else []

    merged_steps: list[dict[str, Any]] = []
    step_count = max(len(knowledge_steps), len(llm_steps))
    if step_count == 0:
        diagnostics.append("No steps found in either KnowledgeItem or LLM output; created one fallback step.")
        step_count = 1

    llm_fallback_count = 0
    for index in range(step_count):
        knowledge_step = knowledge_steps[index] if index < len(knowledge_steps) and isinstance(knowledge_steps[index], dict) else {}
        llm_step = llm_steps[index] if index < len(llm_steps) and isinstance(llm_steps[index], dict) else {}

        step_id = llm_step.get("stepId")
        if not isinstance(step_id, str) or not re.fullmatch(r"step-[0-9]{3}", step_id):
            step_id = knowledge_step.get("stepId")
            if not isinstance(step_id, str) or not step_id.strip():
                step_id = f"step-{index + 1:03d}"
            llm_fallback_count += 1

        instruction = llm_step.get("instruction")
        if not isinstance(instruction, str) or not instruction.strip():
            instruction = knowledge_step.get("instruction")
            if not isinstance(instruction, str) or not instruction.strip():
                instruction = "unknown"
            llm_fallback_count += 1
        instruction = instruction.strip()

        action_type = llm_step.get("actionType")
        if action_type not in ACTION_TYPES:
            action_type = infer_action_type(instruction)
            llm_fallback_count += 1

        target = llm_step.get("target")
        if not isinstance(target, str) or not target.strip():
            target = infer_target(instruction, action_type, str(context.get("appName", "unknown")))
            llm_fallback_count += 1

        source_event_ids = llm_step.get("sourceEventIds")
        if not isinstance(source_event_ids, list) or len(source_event_ids) == 0:
            source_event_ids = knowledge_step.get("sourceEventIds")
            if not isinstance(source_event_ids, list) or len(source_event_ids) == 0:
                source_event_ids = ["unknown"]
            llm_fallback_count += 1

        merged_steps.append(
            {
                "stepId": step_id,
                "actionType": action_type,
                "instruction": instruction,
                "target": target.strip(),
                "sourceEventIds": [str(v) for v in source_event_ids if str(v).strip()] or ["unknown"],
            }
        )

    if llm_fallback_count > 0:
        diagnostics.append(f"Applied fallback on {llm_fallback_count} step fields while normalizing executionPlan.")

    objective = knowledge_item.get("goal", "unknown")
    if llm_valid and isinstance(llm_output.get("objective"), str) and llm_output["objective"].strip():
        objective = llm_output["objective"].strip()
    else:
        diagnostics.append("Fallback objective from KnowledgeItem.goal.")

    app_name = context.get("appName", "unknown")
    app_bundle_id = context.get("appBundleId", "unknown")
    window_title = context.get("windowTitle")
    if llm_valid:
        if isinstance(llm_context.get("appName"), str) and llm_context["appName"].strip():
            app_name = llm_context["appName"].strip()
        if isinstance(llm_context.get("appBundleId"), str) and llm_context["appBundleId"].strip():
            app_bundle_id = llm_context["appBundleId"].strip()
        if llm_context.get("windowTitle") is None or isinstance(llm_context.get("windowTitle"), str):
            window_title = llm_context.get("windowTitle")

    safety_notes = [
        str(c.get("description", "unknown"))
        for c in constraints
        if isinstance(c, dict) and isinstance(c.get("description"), str) and c.get("description", "").strip()
    ]
    if llm_valid and isinstance(llm_output.get("safetyNotes"), list) and len(llm_output["safetyNotes"]) > 0:
        llm_notes = [str(v).strip() for v in llm_output["safetyNotes"] if str(v).strip()]
        if llm_notes:
            safety_notes = llm_notes
    if not safety_notes:
        safety_notes = ["unknown"]
        diagnostics.append("Fallback safetyNotes to ['unknown'].")

    requires_confirmation = manual_confirmation_required(constraints)
    if llm_valid and isinstance(llm_plan.get("requiresTeacherConfirmation"), bool):
        requires_confirmation = llm_plan["requiresTeacherConfirmation"]

    failure_policy = {
        "onContextMismatch": "stopAndAskTeacher",
        "onStepError": "stopAndAskTeacher",
        "onUnknownAction": "stopAndAskTeacher",
    }
    if llm_valid and isinstance(llm_plan.get("failurePolicy"), dict):
        llm_failure_policy = llm_plan["failurePolicy"]
        if (
            llm_failure_policy.get("onContextMismatch") == "stopAndAskTeacher"
            and llm_failure_policy.get("onStepError") == "stopAndAskTeacher"
            and llm_failure_policy.get("onUnknownAction") == "stopAndAskTeacher"
        ):
            failure_policy = llm_failure_policy

    confidence = 0.72
    if llm_valid and isinstance(llm_output.get("confidence"), (int, float)):
        confidence = float(llm_output["confidence"])
    confidence = max(0.0, min(1.0, round(confidence, 2)))

    normalized = {
        "objective": str(objective) if str(objective).strip() else "unknown",
        "context": {
            "appName": str(app_name) if str(app_name).strip() else "unknown",
            "appBundleId": str(app_bundle_id) if str(app_bundle_id).strip() else "unknown",
            "windowTitle": window_title if window_title is None else str(window_title),
        },
        "executionPlan": {
            "requiresTeacherConfirmation": requires_confirmation,
            "steps": merged_steps,
            "completionCriteria": {
                "expectedStepCount": len(merged_steps),
                "requiredFrontmostAppBundleId": str(app_bundle_id) if str(app_bundle_id).strip() else "unknown",
            },
            "failurePolicy": failure_policy,
        },
        "safetyNotes": safety_notes,
        "confidence": confidence,
    }
    return normalized, diagnostics


def load_preference_profile(
    preference_profile: Path | None = None,
    preferences_root: Path | None = None,
) -> tuple[dict[str, Any] | None, str | None, list[str]]:
    diagnostics: list[str] = []
    candidate_path: Path | None = None

    if preference_profile:
        candidate_path = preference_profile
    elif preferences_root:
        latest_path = preferences_root / "profiles" / "latest.json"
        if latest_path.exists():
            try:
                latest_pointer = read_json(latest_path)
            except Exception as exc:
                diagnostics.append(f"Failed to read preference profile pointer: {exc}")
                latest_pointer = None
            if isinstance(latest_pointer, dict):
                profile_version = normalize_optional_string(latest_pointer.get("profileVersion"))
                if profile_version:
                    candidate_path = preferences_root / "profiles" / f"{profile_version}.json"
                else:
                    diagnostics.append("Preference profile pointer missing profileVersion; ignored.")
        elif preferences_root.exists():
            diagnostics.append("Preference profile pointer not found; generated skill without preference profile.")

    if candidate_path is None:
        return None, None, diagnostics

    if not candidate_path.exists():
        diagnostics.append(f"Preference profile path not found: {candidate_path}")
        return None, str(candidate_path), diagnostics

    try:
        payload = read_json(candidate_path)
    except Exception as exc:
        diagnostics.append(f"Failed to read preference profile: {exc}")
        return None, str(candidate_path), diagnostics

    if not isinstance(payload, dict):
        diagnostics.append("Preference profile payload must be a JSON object; ignored.")
        return None, str(candidate_path), diagnostics

    schema_version = normalize_optional_string(payload.get("schemaVersion"))
    if schema_version == "openstaff.learning.preference-profile-snapshot.v0":
        profile = payload.get("profile")
        if not isinstance(profile, dict):
            diagnostics.append("Preference profile snapshot missing embedded profile; ignored.")
            return None, str(candidate_path), diagnostics
        return profile, str(candidate_path), diagnostics

    if schema_version == "openstaff.learning.preference-profile.v0":
        return payload, str(candidate_path), diagnostics

    diagnostics.append(f"Unsupported preference profile schema: {schema_version or 'unknown'}")
    return None, str(candidate_path), diagnostics


def scope_match_score(
    scope: dict[str, Any],
    knowledge_item: dict[str, Any],
    task_family: str | None = None,
    skill_family: str | None = None,
) -> tuple[float, str]:
    level = normalize_optional_string(scope.get("level")) or "global"
    context = knowledge_item.get("context", {})
    app_bundle_id = normalize_token(context.get("appBundleId"))
    app_name = normalize_token(context.get("appName"))
    window_title = normalize_optional_string(context.get("windowTitle")) or ""

    if level == "global":
        return 0.72, "global scope"

    if level == "app":
        scope_bundle = normalize_token(scope.get("appBundleId"))
        scope_name = normalize_token(scope.get("appName"))
        if scope_bundle and scope_bundle == app_bundle_id:
            return 1.0, f"app bundle matched {context.get('appBundleId')}"
        if scope_name and scope_name == app_name:
            return 0.82, f"app name matched {context.get('appName')}"
        return 0.0, "app scope did not match current knowledge context"

    if level == "windowPattern":
        score, reason = scope_match_score(
            {
                "level": "app",
                "appBundleId": scope.get("appBundleId"),
                "appName": scope.get("appName"),
            },
            knowledge_item=knowledge_item,
            task_family=task_family,
            skill_family=skill_family,
        )
        if score <= 0:
            return 0.0, reason
        pattern = normalize_optional_string(scope.get("windowPattern"))
        if not pattern or not window_title:
            return 0.0, "windowPattern scope missing pattern or current window title"
        try:
            matched = re.search(pattern, window_title, flags=re.IGNORECASE) is not None
        except re.error:
            matched = normalize_token(pattern) == normalize_token(window_title)
        if matched:
            return 1.0, f"window pattern matched {window_title}"
        return 0.0, f"window pattern did not match {window_title}"

    if level == "taskFamily":
        scope_family = normalize_token(scope.get("taskFamily"))
        current_family = normalize_token(task_family)
        if scope_family and current_family and scope_family == current_family:
            return 1.0, f"taskFamily matched {task_family}"
        return 0.0, "taskFamily scope did not match"

    if level == "skillFamily":
        scope_family = normalize_token(scope.get("skillFamily"))
        current_family = normalize_token(skill_family)
        if scope_family and current_family and scope_family == current_family:
            return 1.0, f"skillFamily matched {skill_family}"
        return 0.0, "skillFamily scope did not match"

    return 0.0, f"unsupported scope level {level}"


def preferred_native_strategy_from_directive(directive: dict[str, Any]) -> str | None:
    candidates = [
        normalize_optional_string(directive.get("proposedAction")),
        normalize_optional_string(directive.get("hint")),
        normalize_optional_string(directive.get("statement")),
    ]
    for candidate in candidates:
        if contains_any_token(candidate, ["shortcut", "keyboard", "hotkey", "key combo"]):
            return "shortcuts"
        if contains_any_token(candidate, ["applescript", "osascript"]):
            return "applescript"
        if contains_any_token(candidate, ["cli", "shell", "terminal", "command line", "command-line"]):
            return "cli"
        if contains_any_token(candidate, ["adapter", "app intent", "app-intent", "app adapter", "native api"]):
            return "app_adapter"
    return None


def directive_requires_confirmation(directive: dict[str, Any]) -> bool:
    if directive.get("type") == "risk":
        return True

    candidates = [
        normalize_optional_string(directive.get("proposedAction")),
        normalize_optional_string(directive.get("hint")),
        normalize_optional_string(directive.get("statement")),
    ]
    return any(
        contains_any_token(
            candidate,
            ["confirm", "confirmation", "teacher", "approve", "guard", "blocked", "risky", "risk"],
        )
        for candidate in candidates
    )


def assemble_skill_preferences(
    knowledge_item: dict[str, Any],
    profile: dict[str, Any] | None,
    profile_path: str | None = None,
    task_family: str | None = None,
    skill_family: str | None = None,
) -> tuple[dict[str, Any], list[str]]:
    diagnostics: list[str] = []
    empty = {
        "profileVersion": None,
        "profilePath": profile_path,
        "taskFamily": normalize_optional_string(task_family),
        "skillFamily": normalize_optional_string(skill_family),
        "appliedRuleIds": [],
        "procedureNotes": [],
        "locatorNotes": [],
        "styleNotes": [],
        "riskNotes": [],
        "matchedDirectives": [],
        "summary": "No skill preference rules applied.",
        "requiresTeacherConfirmation": False,
    }
    if profile is None:
        return empty, diagnostics

    profile_version = normalize_optional_string(profile.get("profileVersion"))
    directives = profile.get("skillPreferences")
    if not isinstance(directives, list) or not directives:
        diagnostics.append("Preference profile has no skillPreferences; generated skill without preference rules.")
        empty["profileVersion"] = profile_version
        return empty, diagnostics

    matched_directives: list[dict[str, Any]] = []
    for raw_directive in directives:
        if not isinstance(raw_directive, dict):
            continue

        scope = raw_directive.get("scope")
        if not isinstance(scope, dict):
            scope = {"level": "global"}
        match_score, match_reason = scope_match_score(
            scope=scope,
            knowledge_item=knowledge_item,
            task_family=task_family,
            skill_family=skill_family,
        )
        if match_score <= 0:
            continue

        matched_directives.append(
            {
                "ruleId": normalize_string(raw_directive.get("ruleId")),
                "type": normalize_string(raw_directive.get("type")),
                "scopeLevel": normalize_string(scope.get("level")),
                "statement": normalize_string(raw_directive.get("statement")),
                "hint": normalize_optional_string(raw_directive.get("hint")),
                "proposedAction": normalize_optional_string(raw_directive.get("proposedAction")),
                "teacherConfirmed": normalize_bool(raw_directive.get("teacherConfirmed")),
                "updatedAt": normalize_string(raw_directive.get("updatedAt")),
                "matchScore": round(match_score, 2),
                "matchReason": match_reason,
            }
        )

    if not matched_directives:
        diagnostics.append("Preference profile loaded, but no skillPreferences matched current knowledge context.")
        empty["profileVersion"] = profile_version
        empty["summary"] = (
            f"Preference profile {profile_version} loaded, but no skill preference rules matched."
            if profile_version
            else "Preference profile loaded, but no skill preference rules matched."
        )
        return empty, diagnostics

    applied_rule_ids = unique_strings([directive["ruleId"] for directive in matched_directives])
    procedure_notes = unique_strings(
        [directive["hint"] or directive["statement"] for directive in matched_directives if directive["type"] == "procedure"]
    )
    locator_notes = unique_strings(
        [directive["hint"] or directive["statement"] for directive in matched_directives if directive["type"] == "locator"]
    )
    style_notes = unique_strings(
        [directive["hint"] or directive["statement"] for directive in matched_directives if directive["type"] == "style"]
    )
    risk_notes = unique_strings(
        [directive["hint"] or directive["statement"] for directive in matched_directives if directive["type"] == "risk"]
    )
    requires_confirmation = any(directive_requires_confirmation(directive) for directive in matched_directives)

    categories = unique_strings([directive["type"] for directive in matched_directives if directive["type"] != "unknown"])
    category_text = ", ".join(categories) if categories else "generic"
    summary = (
        f"Applied {len(applied_rule_ids)} skill preference rule(s)"
        + (f" from {profile_version}" if profile_version else "")
        + f": {', '.join(applied_rule_ids)}. Categories: {category_text}."
    )
    if requires_confirmation:
        summary += " Teacher confirmation was kept enabled by risk preference."

    return (
        {
            "profileVersion": profile_version,
            "profilePath": profile_path,
            "taskFamily": normalize_optional_string(task_family),
            "skillFamily": normalize_optional_string(skill_family),
            "appliedRuleIds": applied_rule_ids,
            "procedureNotes": procedure_notes,
            "locatorNotes": locator_notes,
            "styleNotes": style_notes,
            "riskNotes": risk_notes,
            "matchedDirectives": matched_directives,
            "summary": summary,
            "requiresTeacherConfirmation": requires_confirmation,
        },
        diagnostics,
    )


def determine_action_kind(step: dict[str, Any], knowledge_step: dict[str, Any]) -> str:
    action_type = normalize_string(step.get("actionType"))
    if action_type in NATIVE_ACTION_TYPES:
        return "nativeAction"
    if action_type in GUI_ACTION_TYPES:
        return "guiAction"

    target = knowledge_step.get("target")
    if isinstance(target, dict):
        semantic_targets = target.get("semanticTargets")
        coordinate = target.get("coordinate")
        if isinstance(semantic_targets, list) and semantic_targets:
            return "guiAction"
        if isinstance(coordinate, dict):
            return "guiAction"

    instruction = normalize_optional_string(step.get("instruction")) or ""
    if contains_any_token(instruction, ["click", "点击", "input", "输入", "type"]):
        return "guiAction"
    return "nativeAction"


def locator_group_for_target(target: dict[str, Any]) -> str | None:
    locator_type = normalize_optional_string(target.get("locatorType"))
    if locator_type in {"axPath", "roleAndTitle"}:
        return "ax"
    if locator_type == "textAnchor":
        return "textAnchor"
    if locator_type == "imageAnchor":
        return "imageAnchor"
    if locator_type == "coordinateFallback":
        rect = target.get("boundingRect")
        if isinstance(rect, dict):
            width = normalize_float(rect.get("width"), 0.0)
            height = normalize_float(rect.get("height"), 0.0)
            if width > 1 or height > 1:
                return "relativeCoordinate"
        return "absoluteCoordinate"
    return None


def target_signature(target: dict[str, Any]) -> str:
    rect = target.get("boundingRect")
    if not isinstance(rect, dict):
        rect = {}
    image_anchor = target.get("imageAnchor")
    if not isinstance(image_anchor, dict):
        image_anchor = {}
    signature = {
        "locatorType": normalize_optional_string(target.get("locatorType")),
        "appBundleId": normalize_optional_string(target.get("appBundleId")),
        "windowTitlePattern": normalize_optional_string(target.get("windowTitlePattern")),
        "elementRole": normalize_optional_string(target.get("elementRole")),
        "elementTitle": normalize_optional_string(target.get("elementTitle")),
        "elementIdentifier": normalize_optional_string(target.get("elementIdentifier")),
        "axPath": normalize_optional_string(target.get("axPath")),
        "textAnchor": normalize_optional_string(target.get("textAnchor")),
        "imageAnchorPixelHash": normalize_optional_string(image_anchor.get("pixelHash")),
        "boundingRect": {
            "x": normalize_float(rect.get("x")),
            "y": normalize_float(rect.get("y")),
            "width": normalize_float(rect.get("width")),
            "height": normalize_float(rect.get("height")),
            "coordinateSpace": normalize_optional_string(rect.get("coordinateSpace")),
        },
    }
    return json.dumps(signature, ensure_ascii=False, sort_keys=True)


def make_window_pattern(context: dict[str, Any], semantic_targets: list[dict[str, Any]]) -> str | None:
    for target in semantic_targets:
        pattern = normalize_optional_string(target.get("windowTitlePattern"))
        if pattern:
            return pattern
    window_title = normalize_optional_string(context.get("windowTitle"))
    if window_title:
        return f"^{re.escape(window_title)}$"
    return None


def best_relative_anchor_target(semantic_targets: list[dict[str, Any]]) -> dict[str, Any] | None:
    for target in semantic_targets:
        group = locator_group_for_target(target)
        if group in {"ax", "textAnchor", "imageAnchor"} and isinstance(target.get("boundingRect"), dict):
            return target
    return None


def build_relative_coordinate_target(
    anchor_target: dict[str, Any] | None,
    context: dict[str, Any],
) -> dict[str, Any] | None:
    if not anchor_target:
        return None
    rect = anchor_target.get("boundingRect")
    if not isinstance(rect, dict):
        return None

    width = max(1.0, normalize_float(rect.get("width"), 1.0))
    height = max(1.0, normalize_float(rect.get("height"), 1.0))
    return {
        "locatorType": "coordinateFallback",
        "appBundleId": normalize_string(anchor_target.get("appBundleId"), normalize_string(context.get("appBundleId"))),
        "windowTitlePattern": normalize_optional_string(anchor_target.get("windowTitlePattern"))
        or make_window_pattern(context, [anchor_target]),
        "boundingRect": {
            "x": normalize_float(rect.get("x")),
            "y": normalize_float(rect.get("y")),
            "width": width,
            "height": height,
            "coordinateSpace": normalize_string(rect.get("coordinateSpace"), "screen"),
        },
        "confidence": round(min(0.32, max(0.12, normalize_float(anchor_target.get("confidence"), 0.18) * 0.5)), 2),
        "source": "skill-mapper-relative-coordinate",
    }


def build_absolute_coordinate_target(
    coordinate: dict[str, Any] | None,
    context: dict[str, Any],
    semantic_targets: list[dict[str, Any]],
) -> dict[str, Any] | None:
    if not isinstance(coordinate, dict):
        return None
    return {
        "locatorType": "coordinateFallback",
        "appBundleId": normalize_string(context.get("appBundleId")),
        "windowTitlePattern": make_window_pattern(context, semantic_targets),
        "boundingRect": {
            "x": normalize_float(coordinate.get("x")),
            "y": normalize_float(coordinate.get("y")),
            "width": 1,
            "height": 1,
            "coordinateSpace": normalize_string(coordinate.get("coordinateSpace"), "screen"),
        },
        "confidence": 0.24,
        "source": "skill-mapper-absolute-coordinate",
    }


def order_gui_semantic_targets(
    knowledge_step: dict[str, Any],
    context: dict[str, Any],
) -> tuple[list[dict[str, Any]], str | None]:
    target = knowledge_step.get("target")
    if not isinstance(target, dict):
        target = {}

    semantic_targets = [item for item in target.get("semanticTargets", []) if isinstance(item, dict)]
    coordinate = target.get("coordinate")
    if not isinstance(coordinate, dict):
        instruction = normalize_optional_string(knowledge_step.get("instruction"))
        coordinate = infer_coordinate(instruction or "")

    grouped: dict[str, list[dict[str, Any]]] = {group: [] for group in GUI_LOCATOR_STRATEGY_ORDER}
    seen_signatures: set[str] = set()

    for semantic_target in semantic_targets:
        group = locator_group_for_target(semantic_target)
        if group is None:
            continue
        signature = target_signature(semantic_target)
        if signature in seen_signatures:
            continue
        seen_signatures.add(signature)
        grouped[group].append(semantic_target)

    relative_candidate = build_relative_coordinate_target(best_relative_anchor_target(semantic_targets), context)
    if relative_candidate is not None:
        signature = target_signature(relative_candidate)
        if signature not in seen_signatures:
            seen_signatures.add(signature)
            grouped["relativeCoordinate"].append(relative_candidate)

    absolute_candidate = build_absolute_coordinate_target(coordinate, context, semantic_targets)
    if absolute_candidate is not None:
        signature = target_signature(absolute_candidate)
        if signature not in seen_signatures:
            seen_signatures.add(signature)
            grouped["absoluteCoordinate"].append(absolute_candidate)

    ordered: list[dict[str, Any]] = []
    for group in GUI_LOCATOR_STRATEGY_ORDER:
        ordered.extend(grouped[group])

    preferred_locator_type = normalize_optional_string(target.get("preferredLocatorType"))
    if not preferred_locator_type and ordered:
        preferred_locator_type = normalize_optional_string(ordered[0].get("locatorType"))

    return ordered, preferred_locator_type


def native_strategy_order_for_step(
    step: dict[str, Any],
    applicable_directives: list[dict[str, Any]],
) -> list[str]:
    preferred: list[str] = []
    for directive in applicable_directives:
        strategy = preferred_native_strategy_from_directive(directive)
        if strategy:
            preferred.append(strategy)

    action_type = normalize_string(step.get("actionType"))
    instruction = normalize_optional_string(step.get("instruction")) or ""
    target = normalize_optional_string(step.get("target")) or ""
    if action_type == "shortcut" or contains_any_token(instruction, ["shortcut", "快捷键", "keyboard"]):
        preferred.insert(0, "shortcuts")
    if contains_any_token(instruction, ["applescript", "osascript"]):
        preferred.insert(0, "applescript")
    if action_type == "openApp" or contains_any_token(target, ["app:", "bundle:", "open "]):
        preferred.append("cli")

    ordered = unique_strings(preferred + DEFAULT_NATIVE_STRATEGY_ORDER)
    return ordered or list(DEFAULT_NATIVE_STRATEGY_ORDER)


def step_notes_for_directives(
    action_kind: str,
    applicable_directives: list[dict[str, Any]],
) -> list[str]:
    notes: list[str] = []
    for directive in applicable_directives:
        directive_type = directive.get("type")
        if directive_type == "locator" and action_kind != "guiAction":
            continue
        note = directive.get("hint") or directive.get("statement")
        if isinstance(note, str) and note.strip():
            notes.append(note.strip())
    return unique_strings(notes)


def applicable_directives_for_step(
    action_kind: str,
    matched_directives: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    applicable: list[dict[str, Any]] = []
    for directive in matched_directives:
        directive_type = directive.get("type")
        if directive_type == "locator" and action_kind != "guiAction":
            continue
        applicable.append(directive)
    return applicable


def apply_preference_assembly(
    mapped: dict[str, Any],
    knowledge_item: dict[str, Any],
    preference_assembly: dict[str, Any],
) -> list[dict[str, Any]]:
    plan = mapped.get("executionPlan", {})
    mapped_steps = plan.get("steps", [])
    knowledge_steps = knowledge_item.get("steps", [])
    context = knowledge_item.get("context", {})
    matched_directives = preference_assembly.get("matchedDirectives", [])
    step_assemblies: list[dict[str, Any]] = []

    for index, mapped_step in enumerate(mapped_steps):
        if not isinstance(mapped_step, dict):
            continue
        knowledge_step = knowledge_steps[index] if index < len(knowledge_steps) and isinstance(knowledge_steps[index], dict) else {}
        action_kind = determine_action_kind(mapped_step, knowledge_step)
        applicable_directives = applicable_directives_for_step(action_kind, matched_directives)
        applied_rule_ids = unique_strings([directive["ruleId"] for directive in applicable_directives])
        notes = step_notes_for_directives(action_kind, applicable_directives)
        requires_confirmation = preference_assembly.get("requiresTeacherConfirmation", False)

        ordered_semantic_targets: list[dict[str, Any]] = []
        preferred_locator_type: str | None = None
        locator_strategy_order: list[str] = []
        native_strategy_order: list[str] = []
        preferred_native_strategy: str | None = None

        if action_kind == "guiAction":
            ordered_semantic_targets, preferred_locator_type = order_gui_semantic_targets(
                knowledge_step=knowledge_step,
                context=context,
            )
            locator_strategy_order = list(GUI_LOCATOR_STRATEGY_ORDER)
        else:
            native_strategy_order = native_strategy_order_for_step(mapped_step, applicable_directives)
            preferred_native_strategy = native_strategy_order[0] if native_strategy_order else None

        step_assemblies.append(
            {
                "stepId": normalize_string(mapped_step.get("stepId"), f"step-{index + 1:03d}"),
                "actionKind": action_kind,
                "appliedRuleIds": applied_rule_ids,
                "preferredLocatorType": preferred_locator_type,
                "locatorStrategyOrder": locator_strategy_order,
                "orderedSemanticTargets": ordered_semantic_targets,
                "nativeStrategyOrder": native_strategy_order,
                "preferredNativeStrategy": preferred_native_strategy,
                "requiresTeacherConfirmation": requires_confirmation,
                "notes": notes,
            }
        )

    if preference_assembly.get("requiresTeacherConfirmation"):
        plan["requiresTeacherConfirmation"] = True

    safety_notes = normalize_string_list(mapped.get("safetyNotes"), fallback=["unknown"])
    extra_risk_notes = preference_assembly.get("riskNotes", [])
    if isinstance(extra_risk_notes, list) and extra_risk_notes:
        mapped["safetyNotes"] = unique_strings(safety_notes + extra_risk_notes)
    else:
        mapped["safetyNotes"] = safety_notes

    return step_assemblies


def build_provenance(
    skill_name: str,
    knowledge_item: dict[str, Any],
    mapped: dict[str, Any],
    created_at: str,
    llm_output_accepted: bool,
    preference_assembly: dict[str, Any] | None = None,
    step_assemblies: list[dict[str, Any]] | None = None,
) -> dict[str, Any]:
    knowledge_source = knowledge_item.get("source", {})
    if not isinstance(knowledge_source, dict):
        knowledge_source = {}

    knowledge_steps = knowledge_item.get("steps", [])
    if not isinstance(knowledge_steps, list):
        knowledge_steps = []

    mapped_steps = mapped.get("executionPlan", {}).get("steps", [])
    if not isinstance(mapped_steps, list):
        mapped_steps = []

    step_mappings: list[dict[str, Any]] = []
    context = knowledge_item.get("context", {})
    if not isinstance(context, dict):
        context = {}

    step_assemblies = step_assemblies or []
    context_app_bundle_id = normalize_string(context.get("appBundleId"))

    applied_rule_ids = []
    profile_version = None
    preference_summary = None
    task_family = None
    skill_family = None
    if isinstance(preference_assembly, dict):
        applied_rule_ids = normalize_string_list(preference_assembly.get("appliedRuleIds"), fallback=[])
        if applied_rule_ids == ["unknown"]:
            applied_rule_ids = []
        profile_version = normalize_optional_string(preference_assembly.get("profileVersion"))
        preference_summary = normalize_optional_string(preference_assembly.get("summary"))
        task_family = normalize_optional_string(preference_assembly.get("taskFamily"))
        skill_family = normalize_optional_string(preference_assembly.get("skillFamily"))

    for index, mapped_step in enumerate(mapped_steps):
        if not isinstance(mapped_step, dict):
            continue

        knowledge_step = (
            knowledge_steps[index]
            if index < len(knowledge_steps) and isinstance(knowledge_steps[index], dict)
            else {}
        )
        target = knowledge_step.get("target", {})
        if not isinstance(target, dict):
            target = {}

        coordinate = target.get("coordinate")
        if not isinstance(coordinate, dict):
            instruction = normalize_string(
                knowledge_step.get("instruction"),
                normalize_string(mapped_step.get("instruction")),
            )
            coordinate = infer_coordinate(instruction)

        assembly = (
            step_assemblies[index]
            if index < len(step_assemblies) and isinstance(step_assemblies[index], dict)
            else {}
        )

        semantic_targets = assembly.get("orderedSemanticTargets")
        if not isinstance(semantic_targets, list):
            semantic_targets = target.get("semanticTargets")
        if not isinstance(semantic_targets, list):
            semantic_targets = []

        if coordinate and not semantic_targets:
            coordinate_fallback: dict[str, Any] = {
                "locatorType": "coordinateFallback",
                "appBundleId": context_app_bundle_id,
                "boundingRect": {
                    "x": coordinate["x"],
                    "y": coordinate["y"],
                    "width": 1,
                    "height": 1,
                    "coordinateSpace": normalize_string(coordinate.get("coordinateSpace"), "screen"),
                },
                "confidence": 0.24,
                "source": "skill-mapper-fallback",
            }
            window_pattern = make_window_pattern(context, [])
            if window_pattern:
                coordinate_fallback["windowTitlePattern"] = window_pattern
            semantic_targets = [coordinate_fallback]

        preferred_locator_type = assembly.get("preferredLocatorType")
        if preferred_locator_type is not None:
            preferred_locator_type = normalize_string(preferred_locator_type)
        else:
            preferred_locator_type = target.get("preferredLocatorType")
            if preferred_locator_type is not None:
                preferred_locator_type = normalize_string(preferred_locator_type)
            elif coordinate and semantic_targets:
                preferred_locator_type = "coordinateFallback"

        skill_step_id = normalize_string(mapped_step.get("stepId"), f"step-{index + 1:03d}")
        step_mappings.append(
            {
                "skillStepId": skill_step_id,
                "knowledgeStepId": normalize_string(knowledge_step.get("stepId"), skill_step_id),
                "instruction": normalize_string(
                    knowledge_step.get("instruction"),
                    normalize_string(mapped_step.get("instruction")),
                ),
                "sourceEventIds": normalize_string_list(mapped_step.get("sourceEventIds")),
                "preferredLocatorType": preferred_locator_type,
                "coordinate": coordinate,
                "semanticTargets": [item for item in semantic_targets if isinstance(item, dict)],
                "actionKind": normalize_string(assembly.get("actionKind"), "guiAction"),
                "preferredNativeStrategy": normalize_optional_string(assembly.get("preferredNativeStrategy")),
                "nativeStrategyOrder": normalize_string_list(assembly.get("nativeStrategyOrder"), fallback=[]),
                "locatorStrategyOrder": normalize_string_list(assembly.get("locatorStrategyOrder"), fallback=[]),
                "appliedRuleIds": normalize_string_list(assembly.get("appliedRuleIds"), fallback=[]),
                "requiresTeacherConfirmation": normalize_bool(assembly.get("requiresTeacherConfirmation")),
                "notes": normalize_string_list(assembly.get("notes"), fallback=[]),
            }
        )

    return {
        "knowledge": {
            "knowledgeItemId": normalize_string(knowledge_item.get("knowledgeItemId")),
            "knowledgeSchemaVersion": normalize_string(knowledge_item.get("schemaVersion"), "knowledge.item.v0"),
            "taskId": normalize_string(knowledge_item.get("taskId")),
            "sessionId": normalize_string(knowledge_item.get("sessionId")),
            "knowledgeCreatedAt": normalize_string(knowledge_item.get("createdAt")),
            "knowledgeGeneratorVersion": normalize_string(
                knowledge_item.get("generatorVersion"),
                "rule-v0",
            ),
        },
        "sourceTrace": {
            "taskChunkSchemaVersion": normalize_string(
                knowledge_source.get("taskChunkSchemaVersion"),
                "knowledge.task-chunk.v0",
            ),
            "startTimestamp": normalize_string(knowledge_source.get("startTimestamp")),
            "endTimestamp": normalize_string(knowledge_source.get("endTimestamp")),
            "eventCount": normalize_non_negative_int(knowledge_source.get("eventCount", 0)),
            "boundaryReason": normalize_string(knowledge_source.get("boundaryReason")),
        },
        "skillBuild": {
            "skillName": skill_name,
            "skillSchemaVersion": SCHEMA_VERSION,
            "skillGeneratorVersion": GENERATOR_VERSION,
            "generatedAt": created_at,
            "repairVersion": REPAIR_VERSION,
            "llmOutputAccepted": llm_output_accepted,
            "preferenceProfileVersion": profile_version,
            "appliedPreferenceRuleIds": applied_rule_ids,
            "preferenceSummary": preference_summary,
            "taskFamily": task_family,
            "skillFamily": skill_family,
        },
        "stepMappings": step_mappings,
    }


def render_skill_markdown(
    skill_name: str,
    mapped: dict[str, Any],
    knowledge_item: dict[str, Any],
    provenance: dict[str, Any],
    preference_assembly: dict[str, Any] | None = None,
) -> str:
    plan = mapped["executionPlan"]
    context = mapped["context"]
    step_mappings = provenance.get("stepMappings", [])
    step_lines: list[str] = []
    for idx, step in enumerate(plan["steps"], start=1):
        source_ids = ", ".join(step["sourceEventIds"])
        provenance_step = (
            step_mappings[idx - 1]
            if idx - 1 < len(step_mappings) and isinstance(step_mappings[idx - 1], dict)
            else {}
        )
        knowledge_step_id = normalize_string(provenance_step.get("knowledgeStepId"), step["stepId"])
        preferred_locator_type = provenance_step.get("preferredLocatorType")
        preferred_locator_text = (
            normalize_string(preferred_locator_type)
            if preferred_locator_type is not None
            else "unknown"
        )
        action_kind = normalize_string(provenance_step.get("actionKind"), "guiAction")
        applied_rule_ids = normalize_string_list(provenance_step.get("appliedRuleIds"), fallback=[])
        notes = normalize_string_list(provenance_step.get("notes"), fallback=[])
        native_order = normalize_string_list(provenance_step.get("nativeStrategyOrder"), fallback=[])
        locator_order = normalize_string_list(provenance_step.get("locatorStrategyOrder"), fallback=[])

        step_lines.extend(
            [
                f"{idx}. [{step['actionType']}] {step['instruction']}",
                f"   - knowledgeStepId: `{knowledge_step_id}`",
                f"   - actionKind: `{action_kind}`",
                f"   - target: `{step['target']}`",
                f"   - preferredLocatorType: `{preferred_locator_text}`",
                f"   - sourceEventIds: `{source_ids}`",
            ]
        )
        if native_order:
            step_lines.append(f"   - nativeStrategyOrder: `{', '.join(native_order)}`")
        if locator_order:
            step_lines.append(f"   - locatorStrategyOrder: `{', '.join(locator_order)}`")
        if applied_rule_ids:
            step_lines.append(f"   - appliedPreferenceRules: `{', '.join(applied_rule_ids)}`")
        if notes:
            step_lines.append(f"   - notes: `{'; '.join(notes)}`")

    safety_lines = "\n".join([f"- {note}" for note in mapped["safetyNotes"]])
    summary = str(knowledge_item.get("summary", "")).strip() or "No summary."
    requires_confirmation = "true" if plan["requiresTeacherConfirmation"] else "false"

    preference_assembly = preference_assembly or {}
    preference_rule_ids = normalize_string_list(preference_assembly.get("appliedRuleIds"), fallback=[])
    if preference_rule_ids == ["unknown"]:
        preference_rule_ids = []
    action_kinds = unique_strings([
        normalize_string(step_mapping.get("actionKind"), "guiAction")
        for step_mapping in step_mappings
        if isinstance(step_mapping, dict)
    ])
    metadata_json = json.dumps(
        {
            "openclaw": {
                "emoji": "🎓",
                "skillKey": skill_name,
                "requires": {"config": ["openstaff.enabled"]},
            },
            "openstaff": {
                "knowledgeItemId": provenance["knowledge"]["knowledgeItemId"],
                "taskId": provenance["knowledge"]["taskId"],
                "sessionId": provenance["knowledge"]["sessionId"],
                "repairVersion": provenance["skillBuild"]["repairVersion"],
                "preferenceProfileVersion": normalize_optional_string(
                    provenance.get("skillBuild", {}).get("preferenceProfileVersion")
                ),
                "preferenceRuleIds": preference_rule_ids,
                "actionKinds": action_kinds,
            },
        },
        ensure_ascii=False,
        separators=(",", ":"),
    )
    title = mapped["objective"]
    provenance_knowledge = provenance["knowledge"]
    provenance_trace = provenance["sourceTrace"]
    provenance_build = provenance["skillBuild"]

    context_lines = "\n".join(
        [
            f"- appName: `{context['appName']}`",
            f"- appBundleId: `{context['appBundleId']}`",
            f"- windowTitle: `{context['windowTitle']}`",
        ]
    )
    provenance_lines = "\n".join(
        [
            f"- sessionId: `{provenance_knowledge['sessionId']}`",
            f"- taskId: `{provenance_knowledge['taskId']}`",
            f"- knowledgeItemId: `{provenance_knowledge['knowledgeItemId']}`",
            f"- sourceTaskChunkSchemaVersion: `{provenance_trace['taskChunkSchemaVersion']}`",
            f"- sourceEventCount: `{provenance_trace['eventCount']}`",
            f"- knowledgeGeneratorVersion: `{provenance_knowledge['knowledgeGeneratorVersion']}`",
            f"- skillGeneratorVersion: `{provenance_build['skillGeneratorVersion']}`",
            f"- repairVersion: `{provenance_build['repairVersion']}`",
        ]
    )

    preference_lines: list[str] = []
    if provenance_build.get("preferenceProfileVersion"):
        preference_lines.append(
            f"- preferenceProfileVersion: `{provenance_build['preferenceProfileVersion']}`"
        )
    if preference_rule_ids:
        preference_lines.append(f"- appliedPreferenceRules: `{', '.join(preference_rule_ids)}`")
    else:
        preference_lines.append("- appliedPreferenceRules: `none`")
    preference_summary = normalize_optional_string(provenance_build.get("preferenceSummary"))
    if preference_summary:
        preference_lines.append(f"- preferenceSummary: {preference_summary}")
    for label, notes in (
        ("procedureNotes", preference_assembly.get("procedureNotes")),
        ("locatorNotes", preference_assembly.get("locatorNotes")),
        ("styleNotes", preference_assembly.get("styleNotes")),
        ("riskNotes", preference_assembly.get("riskNotes")),
    ):
        normalized_notes = normalize_string_list(notes, fallback=[])
        if normalized_notes:
            preference_lines.append(f"- {label}: `{'; '.join(normalized_notes)}`")
    preference_section = "\n".join(preference_lines)

    failure_policy_lines = "\n".join(
        [
            f"- onContextMismatch: `{plan['failurePolicy']['onContextMismatch']}`",
            f"- onStepError: `{plan['failurePolicy']['onStepError']}`",
            f"- onUnknownAction: `{plan['failurePolicy']['onUnknownAction']}`",
        ]
    )
    runtime_requirement_lines = "\n".join(
        [
            f"- requiresTeacherConfirmation: `{requires_confirmation}`",
            f"- expectedStepCount: `{plan['completionCriteria']['expectedStepCount']}`",
            f"- requiredFrontmostAppBundleId: `{plan['completionCriteria']['requiredFrontmostAppBundleId']}`",
            f"- confidence: `{mapped['confidence']}`",
        ]
    )

    return render_template(
        TEMPLATES_DIR / "skill.md.tmpl",
        {
            "skill_name": skill_name,
            "title": title,
            "metadata_json": metadata_json,
            "context_lines": context_lines,
            "provenance_lines": provenance_lines,
            "preference_lines": preference_section,
            "teacher_summary": summary,
            "step_lines": os.linesep.join(step_lines),
            "safety_lines": safety_lines,
            "failure_policy_lines": failure_policy_lines,
            "runtime_requirement_lines": runtime_requirement_lines,
        },
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate OpenClaw skill from KnowledgeItem + LLM output."
    )
    parser.add_argument("--knowledge-item", required=True, type=Path, help="KnowledgeItem JSON path.")
    parser.add_argument(
        "--llm-output",
        required=True,
        type=Path,
        help="LLM output path (JSON or raw text containing JSON).",
    )
    parser.add_argument(
        "--skills-root",
        type=Path,
        default=Path("data/skills/pending"),
        help="Output root for generated skill folders.",
    )
    parser.add_argument("--skill-name", help="Override generated skill name.")
    parser.add_argument("--overwrite", action="store_true", help="Overwrite existing skill folder.")
    parser.add_argument("--report", type=Path, help="Optional output path for mapping report JSON.")
    parser.add_argument(
        "--preferences-root",
        type=Path,
        help="Preference store root. If set, mapper loads profiles/latest.json automatically.",
    )
    parser.add_argument(
        "--preference-profile",
        type=Path,
        help="Explicit PreferenceProfile or PreferenceProfileSnapshot JSON path.",
    )
    parser.add_argument("--task-family", help="Optional taskFamily for scope matching.")
    parser.add_argument("--skill-family", help="Optional skillFamily for scope matching.")
    return parser.parse_args()


def main() -> int:
    args = parse_args()

    knowledge_item = read_json(args.knowledge_item)
    knowledge_errors = validate_knowledge_item(knowledge_item)
    if knowledge_errors:
        print("INVALID: KnowledgeItem validation failed.", file=sys.stderr)
        for err in knowledge_errors:
            print(f"- {err}", file=sys.stderr)
        return 1

    llm_output_any, llm_diagnostics = parse_llm_output(args.llm_output)
    llm_valid = isinstance(llm_output_any, dict) and len(llm_diagnostics) == 0
    llm_output = llm_output_any if isinstance(llm_output_any, dict) else None

    normalized, normalize_diagnostics = normalize_execution_plan(
        knowledge_item=knowledge_item,
        llm_output=llm_output,
        llm_valid=llm_valid,
    )

    preference_profile, preference_profile_path, preference_diagnostics = load_preference_profile(
        preference_profile=args.preference_profile,
        preferences_root=args.preferences_root,
    )
    preference_assembly, preference_match_diagnostics = assemble_skill_preferences(
        knowledge_item=knowledge_item,
        profile=preference_profile,
        profile_path=preference_profile_path,
        task_family=args.task_family,
        skill_family=args.skill_family,
    )
    step_assemblies = apply_preference_assembly(
        mapped=normalized,
        knowledge_item=knowledge_item,
        preference_assembly=preference_assembly,
    )

    skill_name = sanitize_skill_name(str(knowledge_item.get("taskId", "")), args.skill_name)
    skill_dir = args.skills_root / skill_name
    if skill_dir.exists() and not args.overwrite:
        print(
            f"FAILED: SKL-IO-SKILL-EXISTS skill directory already exists: {skill_dir}",
            file=sys.stderr,
        )
        return 1

    created_at = iso_now()
    provenance = build_provenance(
        skill_name=skill_name,
        knowledge_item=knowledge_item,
        mapped=normalized,
        created_at=created_at,
        llm_output_accepted=llm_valid,
        preference_assembly=preference_assembly,
        step_assemblies=step_assemblies,
    )
    skill_md = render_skill_markdown(
        skill_name=skill_name,
        mapped=normalized,
        knowledge_item=knowledge_item,
        provenance=provenance,
        preference_assembly=preference_assembly,
    )
    mapped_payload = {
        "schemaVersion": SCHEMA_VERSION,
        "skillName": skill_name,
        "knowledgeItemId": knowledge_item.get("knowledgeItemId"),
        "taskId": knowledge_item.get("taskId"),
        "sessionId": knowledge_item.get("sessionId"),
        "source": {
            "knowledgeItemPath": str(args.knowledge_item),
            "llmOutputPath": str(args.llm_output),
            "preferenceProfilePath": preference_profile_path,
            "taskFamily": normalize_optional_string(args.task_family),
            "skillFamily": normalize_optional_string(args.skill_family),
        },
        "provenance": provenance,
        "mappedOutput": normalized,
        "diagnostics": llm_diagnostics + normalize_diagnostics + preference_diagnostics + preference_match_diagnostics,
        "llmOutputAccepted": llm_valid,
        "createdAt": created_at,
        "generatorVersion": GENERATOR_VERSION,
    }

    write_text(skill_dir / "SKILL.md", skill_md)
    write_json(skill_dir / "openstaff-skill.json", mapped_payload)

    report_payload = {
        "status": "success",
        "skillDir": str(skill_dir),
        "skillName": skill_name,
        "llmOutputAccepted": llm_valid,
        "diagnostics": mapped_payload["diagnostics"],
        "preferenceProfileVersion": provenance["skillBuild"].get("preferenceProfileVersion"),
        "preferenceRuleIds": provenance["skillBuild"].get("appliedPreferenceRuleIds", []),
    }
    if args.report:
        write_json(args.report, report_payload)

    print(f"SUCCESS: generated OpenClaw skill at {skill_dir}")
    if mapped_payload["diagnostics"]:
        print("DIAGNOSTICS:")
        for line in mapped_payload["diagnostics"]:
            print(f"- {line}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
