#!/usr/bin/env python3
"""
Render stable system/user prompts for KnowledgeItem -> LLM structured parse.
"""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from typing import Any


SCRIPT_DIR = Path(__file__).resolve().parent
DEFAULT_SYSTEM_TEMPLATE = SCRIPT_DIR / "prompts" / "system-knowledge-parser-v0.md"
DEFAULT_TASK_TEMPLATE = SCRIPT_DIR / "prompts" / "task-knowledge-parser-v0.md"
DEFAULT_OUTPUT_SCHEMA = SCRIPT_DIR / "schemas" / "knowledge-parse-output.schema.json"

ROLE_PREFIX_BY_AX_ROLE = {
    "axbutton": "button",
    "axcheckbox": "checkbox",
    "axlink": "link",
    "axmenuitem": "menu",
    "axmenubutton": "menu",
    "axpopbutton": "menu",
    "axradiobutton": "radio",
    "axrow": "row",
    "axstatictext": "text",
    "axtab": "tab",
    "axtable": "table",
    "axtextfield": "field",
    "axtextarea": "field",
    "axwindow": "window",
}


def load_json(path: Path) -> object:
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def load_text(path: Path) -> str:
    with path.open("r", encoding="utf-8") as f:
        return f.read()


def normalize_string(value: Any) -> str:
    if isinstance(value, str):
        return value.strip()
    if value is None:
        return ""
    return str(value).strip()


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


def role_prefix_for_role(role: str) -> str | None:
    normalized_role = normalize_string(role).lower()
    if not normalized_role:
        return None
    return ROLE_PREFIX_BY_AX_ROLE.get(normalized_role)


def semantic_target_label(target: dict[str, Any]) -> str | None:
    locator_type = normalize_string(target.get("locatorType"))
    if locator_type == "coordinateFallback":
        return None

    role = normalize_string(target.get("elementRole"))
    title = normalize_string(target.get("elementTitle"))
    identifier = normalize_string(target.get("elementIdentifier"))
    text_anchor = normalize_string(target.get("textAnchor"))
    ax_path = normalize_string(target.get("axPath"))
    prefix = role_prefix_for_role(role)

    if title and prefix:
        return f"{prefix}:{title}"
    if title:
        return f"element:{title}"
    if identifier and prefix:
        return f"{prefix}:{identifier}"
    if identifier:
        return f"element:{identifier}"
    if text_anchor:
        return f"text:{text_anchor}"
    if ax_path:
        if prefix:
            return f"{prefix}:{ax_path}"
        return f"ax:{ax_path}"
    return None


def infer_semantic_target(step: dict[str, Any], context: dict[str, Any]) -> str:
    target = step.get("target")
    if isinstance(target, dict):
        semantic_targets = [
            item
            for item in target.get("semanticTargets", [])
            if isinstance(item, dict)
        ]
        semantic_targets.sort(
            key=lambda item: float(item.get("confidence", 0.0) or 0.0),
            reverse=True,
        )
        for semantic_target in semantic_targets:
            label = semantic_target_label(semantic_target)
            if label:
                return label

    instruction = normalize_string(step.get("instruction"))
    action_type = infer_action_type(instruction)
    if action_type == "openApp":
        bundle_id = normalize_string(context.get("appBundleId"))
        app_name = normalize_string(context.get("appName"))
        if bundle_id and bundle_id != "unknown":
            return f"bundle:{bundle_id}"
        if app_name and app_name != "unknown":
            return f"app:{app_name}"

    return "unknown"


def sanitize_instruction_text(instruction: str) -> str:
    cleaned = instruction
    cleaned = re.sub(
        r"[（(]\s*x\s*=\s*\d+\s*[,，]\s*y\s*=\s*\d+(?:[^）)]*)[）)]",
        "",
        cleaned,
        flags=re.IGNORECASE,
    )
    cleaned = re.sub(r"x\s*=\s*\d+\s*[,，]\s*y\s*=\s*\d+", "语义目标", cleaned, flags=re.IGNORECASE)
    cleaned = re.sub(r"\(\s*\d+\s*,\s*\d+\s*\)", "语义目标", cleaned)
    cleaned = re.sub(r"\s+", " ", cleaned)
    cleaned = re.sub(r"[，,]\s*[。.]$", "。", cleaned)
    cleaned = cleaned.strip(" ，,")
    if cleaned and cleaned[-1] not in "。.!！?？":
        cleaned += "。"
    return cleaned or "unknown"


def sanitize_semantic_target(target: dict[str, Any]) -> dict[str, Any] | None:
    locator_type = normalize_string(target.get("locatorType"))
    if not locator_type or locator_type == "coordinateFallback":
        return None

    sanitized: dict[str, Any] = {
        "locatorType": locator_type,
        "confidence": round(float(target.get("confidence", 0.0) or 0.0), 2),
        "source": normalize_string(target.get("source")) or "unknown",
    }
    for key in (
        "appBundleId",
        "windowTitlePattern",
        "elementRole",
        "elementTitle",
        "elementIdentifier",
        "axPath",
        "textAnchor",
    ):
        value = normalize_string(target.get(key))
        if value:
            sanitized[key] = value

    label = semantic_target_label(target)
    if label:
        sanitized["semanticLabel"] = label
    return sanitized


def build_prompt_knowledge_item(knowledge_item: object) -> object:
    if not isinstance(knowledge_item, dict):
        return knowledge_item

    prompt_item = json.loads(json.dumps(knowledge_item))
    context = prompt_item.get("context")
    if not isinstance(context, dict):
        context = {}
        prompt_item["context"] = context

    raw_steps = prompt_item.get("steps")
    if not isinstance(raw_steps, list):
        return prompt_item

    semanticized_steps: list[dict[str, Any]] = []
    for index, raw_step in enumerate(raw_steps):
        if not isinstance(raw_step, dict):
            semanticized_steps.append(raw_step)
            continue

        step = dict(raw_step)
        original_instruction = normalize_string(step.get("instruction")) or "unknown"
        semantic_target = infer_semantic_target(step, context)
        semantic_instruction = sanitize_instruction_text(original_instruction)
        action_type = infer_action_type(original_instruction)
        if (
            semantic_target != "unknown"
            and action_type in {"click", "input", "openApp"}
            and semantic_target not in semantic_instruction
        ):
            semantic_instruction = semantic_instruction.rstrip("。")
            semantic_instruction += f" 目标 {semantic_target}。"

        step["instruction"] = semantic_instruction

        raw_target = step.get("target")
        if isinstance(raw_target, dict):
            semantic_targets = [
                sanitize_semantic_target(target)
                for target in raw_target.get("semanticTargets", [])
                if isinstance(target, dict)
            ]
            semantic_targets = [target for target in semantic_targets if isinstance(target, dict)]
            step["target"] = {
                "preferredLocatorType": normalize_string(raw_target.get("preferredLocatorType")) or "unknown",
                "semanticSummary": semantic_target,
                "semanticTargets": semantic_targets,
            }
        elif semantic_target != "unknown":
            step["target"] = semantic_target
        else:
            step["target"] = "unknown"

        step["promptNotes"] = {
            "coordinatesOmitted": True,
            "semanticTargetAvailable": semantic_target != "unknown",
            "semanticTarget": semantic_target,
        }
        semanticized_steps.append(step)

    prompt_item["steps"] = semanticized_steps
    prompt_item["promptRendering"] = {
        "mode": "semantic-first",
        "coordinatesIncluded": False,
    }
    return prompt_item


def render_task_prompt(
    task_template: str,
    knowledge_item: object,
    output_schema: object,
) -> str:
    prompt_knowledge_item = build_prompt_knowledge_item(knowledge_item)
    knowledge_json = json.dumps(prompt_knowledge_item, ensure_ascii=False, indent=2, sort_keys=True)
    schema_json = json.dumps(output_schema, ensure_ascii=False, indent=2, sort_keys=True)
    return (
        task_template.replace("{{KNOWLEDGE_ITEM_JSON}}", knowledge_json).replace(
            "{{OUTPUT_SCHEMA_JSON}}", schema_json
        )
    )


def write_text(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as f:
        f.write(content.rstrip() + "\n")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Render prompt files for LLM knowledge parsing."
    )
    parser.add_argument(
        "--knowledge-item",
        required=True,
        type=Path,
        help="Path to KnowledgeItem JSON input.",
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
        "--out-dir",
        type=Path,
        help="Optional output directory. If provided, writes system/user prompt files.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()

    knowledge_item = load_json(args.knowledge_item)
    output_schema = load_json(args.output_schema)
    system_prompt = load_text(args.system_template).strip() + "\n"
    task_template = load_text(args.task_template)
    user_prompt = render_task_prompt(task_template, knowledge_item, output_schema)

    if args.out_dir:
        system_output = args.out_dir / "system.prompt.md"
        user_output = args.out_dir / "user.prompt.md"
        write_text(system_output, system_prompt)
        write_text(user_output, user_prompt)
        print(f"Rendered system prompt: {system_output}")
        print(f"Rendered user prompt:   {user_output}")
        return 0

    print("=== SYSTEM PROMPT ===")
    print(system_prompt.rstrip())
    print()
    print("=== USER PROMPT ===")
    print(user_prompt.rstrip())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
