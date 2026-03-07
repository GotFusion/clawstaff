#!/usr/bin/env python3
"""
Validate generated OpenClaw skill folder.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any


REQUIRED_FRONTMATTER_KEYS = {"name", "description"}


def read_text(path: Path) -> str:
    with path.open("r", encoding="utf-8") as f:
        return f.read()


def read_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def parse_frontmatter(markdown: str) -> tuple[dict[str, str], str, list[str]]:
    errors: list[str] = []
    lines = markdown.splitlines()
    if len(lines) < 3 or lines[0].strip() != "---":
        return {}, markdown, ["SKILL.md must start with frontmatter delimiter '---'."]

    end_index = -1
    for i in range(1, len(lines)):
        if lines[i].strip() == "---":
            end_index = i
            break
    if end_index == -1:
        return {}, markdown, ["SKILL.md frontmatter missing closing delimiter '---'."]

    body = "\n".join(lines[end_index + 1 :]).strip()
    fm_lines = lines[1:end_index]
    frontmatter: dict[str, str] = {}
    for i, raw in enumerate(fm_lines, start=2):
        if not raw.strip():
            continue
        if ":" not in raw:
            errors.append(f"Frontmatter line {i} must contain ':' key/value separator.")
            continue
        key, value = raw.split(":", 1)
        key = key.strip()
        value = value.strip()
        if not key:
            errors.append(f"Frontmatter line {i} has empty key.")
            continue
        if "\n" in value:
            errors.append(f"Frontmatter key '{key}' must be single-line.")
            continue
        frontmatter[key] = value

    return frontmatter, body, errors


def validate_skill_markdown(markdown: str) -> tuple[dict[str, str], list[str]]:
    frontmatter, body, errors = parse_frontmatter(markdown)
    missing = REQUIRED_FRONTMATTER_KEYS - set(frontmatter.keys())
    for key in sorted(missing):
        errors.append(f"Frontmatter missing required key: {key}")

    name = frontmatter.get("name", "")
    if name and not re.fullmatch(r"[a-z0-9][a-z0-9_-]{0,63}", name):
        errors.append("Frontmatter name must match pattern [a-z0-9][a-z0-9_-]{0,63}.")

    description = frontmatter.get("description", "")
    if description and not description.strip():
        errors.append("Frontmatter description must be non-empty.")

    metadata = frontmatter.get("metadata")
    if metadata:
        try:
            parsed_metadata = json.loads(metadata)
            if not isinstance(parsed_metadata, dict):
                errors.append("Frontmatter metadata must be a JSON object.")
        except json.JSONDecodeError as exc:
            errors.append(f"Frontmatter metadata is not valid single-line JSON: {exc}")

    if not body:
        errors.append("SKILL.md body is empty.")

    if "## Steps" not in body:
        errors.append("SKILL.md body must include a '## Steps' section.")
    if not re.search(r"(?m)^\d+\.\s", body):
        errors.append("SKILL.md body must contain at least one numbered step.")
    if "## Safety Notes" not in body:
        errors.append("SKILL.md body should include a '## Safety Notes' section.")

    return frontmatter, errors


def validate_mapping_json(mapping: Any, frontmatter: dict[str, str]) -> list[str]:
    errors: list[str] = []
    if not isinstance(mapping, dict):
        return ["openstaff-skill.json must be a JSON object."]

    required = [
        "schemaVersion",
        "skillName",
        "knowledgeItemId",
        "taskId",
        "sessionId",
        "mappedOutput",
        "createdAt",
        "generatorVersion",
    ]
    for key in required:
        if key not in mapping:
            errors.append(f"openstaff-skill.json missing required key: {key}")

    if mapping.get("schemaVersion") != "openstaff.openclaw-skill.v0":
        errors.append("openstaff-skill.json schemaVersion must equal 'openstaff.openclaw-skill.v0'.")

    if "skillName" in mapping and frontmatter.get("name") != mapping.get("skillName"):
        errors.append("Frontmatter name must match openstaff-skill.json skillName.")

    mapped_output = mapping.get("mappedOutput")
    if not isinstance(mapped_output, dict):
        errors.append("mappedOutput must be an object.")
        return errors

    if not isinstance(mapped_output.get("objective"), str) or not mapped_output["objective"].strip():
        errors.append("mappedOutput.objective must be a non-empty string.")

    context = mapped_output.get("context")
    if not isinstance(context, dict):
        errors.append("mappedOutput.context must be an object.")
    else:
        if not isinstance(context.get("appName"), str) or not context["appName"].strip():
            errors.append("mappedOutput.context.appName must be non-empty string.")
        if not isinstance(context.get("appBundleId"), str) or not context["appBundleId"].strip():
            errors.append("mappedOutput.context.appBundleId must be non-empty string.")

    plan = mapped_output.get("executionPlan")
    if not isinstance(plan, dict):
        errors.append("mappedOutput.executionPlan must be an object.")
    else:
        steps = plan.get("steps")
        if not isinstance(steps, list) or len(steps) == 0:
            errors.append("mappedOutput.executionPlan.steps must be a non-empty array.")
        else:
            for idx, step in enumerate(steps):
                if not isinstance(step, dict):
                    errors.append(f"mappedOutput.executionPlan.steps[{idx}] must be an object.")
                    continue
                for key in ["stepId", "actionType", "instruction", "target", "sourceEventIds"]:
                    if key not in step:
                        errors.append(f"mappedOutput.executionPlan.steps[{idx}] missing key: {key}")
                if isinstance(step.get("sourceEventIds"), list) and len(step["sourceEventIds"]) == 0:
                    errors.append(
                        f"mappedOutput.executionPlan.steps[{idx}].sourceEventIds must not be empty."
                    )
        completion = plan.get("completionCriteria")
        if not isinstance(completion, dict):
            errors.append("mappedOutput.executionPlan.completionCriteria must be an object.")
        else:
            if completion.get("expectedStepCount") != len(plan.get("steps", [])):
                errors.append(
                    "mappedOutput.executionPlan.completionCriteria.expectedStepCount must equal steps length."
                )

    safety_notes = mapped_output.get("safetyNotes")
    if not isinstance(safety_notes, list) or len(safety_notes) == 0:
        errors.append("mappedOutput.safetyNotes must be a non-empty array.")

    confidence = mapped_output.get("confidence")
    if not isinstance(confidence, (int, float)) or confidence < 0 or confidence > 1:
        errors.append("mappedOutput.confidence must be in [0, 1].")

    return errors


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Validate OpenClaw skill output folder.")
    parser.add_argument("--skill-dir", required=True, type=Path, help="Skill directory path.")
    parser.add_argument(
        "--mapping-file",
        default="openstaff-skill.json",
        help="Mapping JSON filename inside skill-dir.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    skill_dir = args.skill_dir

    errors: list[str] = []
    if not skill_dir.exists() or not skill_dir.is_dir():
        print(f"INVALID: skill directory not found: {skill_dir}", file=sys.stderr)
        return 1

    skill_md_path = skill_dir / "SKILL.md"
    if not skill_md_path.exists():
        print(f"INVALID: missing SKILL.md in {skill_dir}", file=sys.stderr)
        return 1

    markdown = read_text(skill_md_path)
    frontmatter, md_errors = validate_skill_markdown(markdown)
    errors.extend(md_errors)

    mapping_path = skill_dir / args.mapping_file
    if not mapping_path.exists():
        errors.append(f"Missing mapping file: {mapping_path.name}")
    else:
        try:
            mapping = read_json(mapping_path)
            errors.extend(validate_mapping_json(mapping, frontmatter))
        except json.JSONDecodeError as exc:
            errors.append(f"{mapping_path.name} is not valid JSON: {exc}")

    if errors:
        print("INVALID:")
        for err in errors:
            print(f"- {err}")
        return 1

    print(f"VALID: {skill_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
