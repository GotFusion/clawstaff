#!/usr/bin/env python3
"""Shared helpers for learning bundle export, verification, and restore."""

from __future__ import annotations

import hashlib
import json
import shutil
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


REPO_ROOT = Path(__file__).resolve().parents[2]
BUNDLE_SCHEMA_VERSION = "openstaff.learning.bundle.v0"
MANIFEST_SCHEMA_VERSION = "openstaff.learning.bundle-manifest.v0"
VERIFICATION_SCHEMA_VERSION = "openstaff.learning.bundle-verification.v0"
PROFILE_POINTER_SCHEMA_VERSION = "openstaff.learning.preference-profile-pointer.v0"
CATEGORY_ORDER = ("turns", "evidence", "signals", "rules", "profiles", "audit")
EXPECTED_RECORD_SCHEMA = {
    "turns": "openstaff.learning.interaction-turn.v0",
    "evidence": "openstaff.learning.next-state-evidence.v0",
    "signals": "openstaff.learning.preference-signal.v0",
    "rules": "openstaff.learning.preference-rule.v0",
    "profiles": "openstaff.learning.preference-profile-snapshot.v0",
    "audit": "openstaff.learning.preference-audit.v0",
}
PAYLOAD_RELATIVE_ROOT = {
    "turns": Path("payload/turns"),
    "evidence": Path("payload/evidence"),
    "signals": Path("payload/signals"),
    "rules": Path("payload/rules"),
    "profiles": Path("payload/profiles"),
    "audit": Path("payload/audit"),
}
RESTORE_RELATIVE_ROOT = {
    "turns": Path("data/learning/turns"),
    "evidence": Path("data/learning/evidence"),
    "signals": Path("data/preferences/signals"),
    "rules": Path("data/preferences/rules"),
    "profiles": Path("data/preferences/profiles"),
    "audit": Path("data/preferences/audit"),
}
FORMAT_BY_CATEGORY = {
    "turns": "json",
    "evidence": "jsonl",
    "signals": "json",
    "rules": "json",
    "profiles": "json",
    "audit": "jsonl",
}
ID_FIELD_BY_CATEGORY = {
    "turns": "turnId",
    "evidence": "evidenceId",
    "signals": "signalId",
    "rules": "ruleId",
    "profiles": "profileVersion",
    "audit": "auditId",
}


def now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def repo_relative_or_abs(path: Path) -> str:
    resolved = path.resolve()
    try:
        return resolved.relative_to(REPO_ROOT).as_posix()
    except ValueError:
        return str(resolved)


def read_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def read_jsonl(path: Path) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    if not path.exists():
        return rows
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line:
            continue
        rows.append(json.loads(line))
    return rows


def write_json(path: Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def write_jsonl(path: Path, rows: list[dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    text = "".join(json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n" for row in rows)
    path.write_text(text, encoding="utf-8")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def ensure_clean_output_directory(output_dir: Path, overwrite: bool = False) -> None:
    if output_dir.exists():
        if not overwrite:
            raise ValueError(f"Output directory already exists: {output_dir}")
        shutil.rmtree(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)


def issue(severity: str, code: str, message: str, **fields: Any) -> dict[str, Any]:
    payload: dict[str, Any] = {
        "severity": severity,
        "code": code,
        "message": message,
    }
    for key, value in fields.items():
        if value is None:
            continue
        payload[key] = value
    return payload


def category_counts_template() -> dict[str, dict[str, int]]:
    return {category: {"files": 0, "records": 0} for category in CATEGORY_ORDER}


def encode_latest_profile_pointer(profile_version: str, updated_at: str) -> dict[str, Any]:
    return {
        "schemaVersion": PROFILE_POINTER_SCHEMA_VERSION,
        "profileVersion": profile_version,
        "updatedAt": updated_at,
    }


@dataclass(frozen=True)
class Artifact:
    category: str
    source_path: Path
    source_relative_path: str
    bundle_relative_path: str
    restore_relative_path: str
    record_format: str
    records: tuple[dict[str, Any], ...]
    record_ids: tuple[str, ...]


@dataclass
class LoadedDataset:
    artifacts_by_category: dict[str, list[Artifact]]
    turns_by_id: dict[str, dict[str, Any]]
    evidence_by_id: dict[str, dict[str, Any]]
    signals_by_id: dict[str, dict[str, Any]]
    rules_by_id: dict[str, dict[str, Any]]
    profiles_by_id: dict[str, dict[str, Any]]
    audit_by_id: dict[str, dict[str, Any]]
    latest_profile_version: str | None
    latest_profile_updated_at: str | None


def _record_entries(records: list[dict[str, Any]], artifact: Artifact, category: str) -> dict[str, dict[str, Any]]:
    id_field = ID_FIELD_BY_CATEGORY[category]
    entries: dict[str, dict[str, Any]] = {}
    for record in records:
        record_id = record.get(id_field)
        if not isinstance(record_id, str) or not record_id.strip():
            continue
        entries[record_id] = {
            "payload": record,
            "artifact": artifact,
        }
    return entries


def _iter_turn_artifacts(root: Path) -> list[Artifact]:
    artifacts: list[Artifact] = []
    if not root.exists():
        return artifacts
    for path in sorted(root.rglob("*.json")):
        record = read_json(path)
        if not isinstance(record, dict):
            continue
        relative = path.relative_to(root).as_posix()
        record_id = record.get("turnId")
        if not isinstance(record_id, str) or not record_id.strip():
            continue
        artifacts.append(
            Artifact(
                category="turns",
                source_path=path,
                source_relative_path=relative,
                bundle_relative_path=(PAYLOAD_RELATIVE_ROOT["turns"] / relative).as_posix(),
                restore_relative_path=(RESTORE_RELATIVE_ROOT["turns"] / relative).as_posix(),
                record_format="json",
                records=(record,),
                record_ids=(record_id,),
            )
        )
    return artifacts


def _iter_jsonl_artifacts(category: str, root: Path) -> list[Artifact]:
    artifacts: list[Artifact] = []
    if not root.exists():
        return artifacts
    for path in sorted(root.rglob("*.jsonl")):
        rows = read_jsonl(path)
        if not rows:
            continue
        id_field = ID_FIELD_BY_CATEGORY[category]
        record_ids = tuple(
            row[id_field]
            for row in rows
            if isinstance(row, dict) and isinstance(row.get(id_field), str) and row[id_field].strip()
        )
        if not record_ids:
            continue
        relative = path.relative_to(root).as_posix()
        artifacts.append(
            Artifact(
                category=category,
                source_path=path,
                source_relative_path=relative,
                bundle_relative_path=(PAYLOAD_RELATIVE_ROOT[category] / relative).as_posix(),
                restore_relative_path=(RESTORE_RELATIVE_ROOT[category] / relative).as_posix(),
                record_format="jsonl",
                records=tuple(row for row in rows if isinstance(row, dict)),
                record_ids=record_ids,
            )
        )
    return artifacts


def _iter_signals_artifacts(root: Path) -> list[Artifact]:
    artifacts: list[Artifact] = []
    if not root.exists():
        return artifacts
    for path in sorted(root.rglob("*.json")):
        if "/index/" in path.as_posix():
            continue
        records = read_json(path)
        if not isinstance(records, list) or not records:
            continue
        record_ids = tuple(
            record["signalId"]
            for record in records
            if isinstance(record, dict) and isinstance(record.get("signalId"), str) and record["signalId"].strip()
        )
        if not record_ids:
            continue
        relative = path.relative_to(root).as_posix()
        artifacts.append(
            Artifact(
                category="signals",
                source_path=path,
                source_relative_path=relative,
                bundle_relative_path=(PAYLOAD_RELATIVE_ROOT["signals"] / relative).as_posix(),
                restore_relative_path=(RESTORE_RELATIVE_ROOT["signals"] / relative).as_posix(),
                record_format="json",
                records=tuple(record for record in records if isinstance(record, dict)),
                record_ids=record_ids,
            )
        )
    return artifacts


def _iter_rules_artifacts(root: Path) -> list[Artifact]:
    artifacts: list[Artifact] = []
    if not root.exists():
        return artifacts
    for path in sorted(root.glob("*.json")):
        if path.name in {"latest.json", "index.json"}:
            continue
        record = read_json(path)
        if not isinstance(record, dict):
            continue
        record_id = record.get("ruleId")
        if not isinstance(record_id, str) or not record_id.strip():
            continue
        relative = path.relative_to(root).as_posix()
        artifacts.append(
            Artifact(
                category="rules",
                source_path=path,
                source_relative_path=relative,
                bundle_relative_path=(PAYLOAD_RELATIVE_ROOT["rules"] / relative).as_posix(),
                restore_relative_path=(RESTORE_RELATIVE_ROOT["rules"] / relative).as_posix(),
                record_format="json",
                records=(record,),
                record_ids=(record_id,),
            )
        )
    return artifacts


def _iter_profiles_artifacts(root: Path) -> tuple[list[Artifact], str | None, str | None]:
    artifacts: list[Artifact] = []
    latest_profile_version: str | None = None
    latest_profile_updated_at: str | None = None
    if not root.exists():
        return artifacts, latest_profile_version, latest_profile_updated_at

    latest_pointer_path = root / "latest.json"
    if latest_pointer_path.exists():
        pointer = read_json(latest_pointer_path)
        if isinstance(pointer, dict):
            profile_version = pointer.get("profileVersion")
            updated_at = pointer.get("updatedAt")
            if isinstance(profile_version, str) and profile_version.strip():
                latest_profile_version = profile_version
            if isinstance(updated_at, str) and updated_at.strip():
                latest_profile_updated_at = updated_at

    for path in sorted(root.glob("*.json")):
        if path.name == "latest.json":
            continue
        record = read_json(path)
        if not isinstance(record, dict):
            continue
        record_id = record.get("profileVersion")
        if not isinstance(record_id, str) or not record_id.strip():
            continue
        relative = path.relative_to(root).as_posix()
        artifacts.append(
            Artifact(
                category="profiles",
                source_path=path,
                source_relative_path=relative,
                bundle_relative_path=(PAYLOAD_RELATIVE_ROOT["profiles"] / relative).as_posix(),
                restore_relative_path=(RESTORE_RELATIVE_ROOT["profiles"] / relative).as_posix(),
                record_format="json",
                records=(record,),
                record_ids=(record_id,),
            )
        )
    return artifacts, latest_profile_version, latest_profile_updated_at


def load_source_dataset(learning_root: Path, preferences_root: Path) -> LoadedDataset:
    turns_root = learning_root / "turns"
    evidence_root = learning_root / "evidence"
    signals_root = preferences_root / "signals"
    rules_root = preferences_root / "rules"
    profiles_root = preferences_root / "profiles"
    audit_root = preferences_root / "audit"

    turns_artifacts = _iter_turn_artifacts(turns_root)
    evidence_artifacts = _iter_jsonl_artifacts("evidence", evidence_root)
    signals_artifacts = _iter_signals_artifacts(signals_root)
    rules_artifacts = _iter_rules_artifacts(rules_root)
    profiles_artifacts, latest_profile_version, latest_profile_updated_at = _iter_profiles_artifacts(profiles_root)
    audit_artifacts = _iter_jsonl_artifacts("audit", audit_root)

    artifacts_by_category = {
        "turns": turns_artifacts,
        "evidence": evidence_artifacts,
        "signals": signals_artifacts,
        "rules": rules_artifacts,
        "profiles": profiles_artifacts,
        "audit": audit_artifacts,
    }

    turns_by_id: dict[str, dict[str, Any]] = {}
    evidence_by_id: dict[str, dict[str, Any]] = {}
    signals_by_id: dict[str, dict[str, Any]] = {}
    rules_by_id: dict[str, dict[str, Any]] = {}
    profiles_by_id: dict[str, dict[str, Any]] = {}
    audit_by_id: dict[str, dict[str, Any]] = {}

    for artifact in turns_artifacts:
        turns_by_id.update(_record_entries(list(artifact.records), artifact, "turns"))
    for artifact in evidence_artifacts:
        evidence_by_id.update(_record_entries(list(artifact.records), artifact, "evidence"))
    for artifact in signals_artifacts:
        signals_by_id.update(_record_entries(list(artifact.records), artifact, "signals"))
    for artifact in rules_artifacts:
        rules_by_id.update(_record_entries(list(artifact.records), artifact, "rules"))
    for artifact in profiles_artifacts:
        profiles_by_id.update(_record_entries(list(artifact.records), artifact, "profiles"))
    for artifact in audit_artifacts:
        audit_by_id.update(_record_entries(list(artifact.records), artifact, "audit"))

    return LoadedDataset(
        artifacts_by_category=artifacts_by_category,
        turns_by_id=turns_by_id,
        evidence_by_id=evidence_by_id,
        signals_by_id=signals_by_id,
        rules_by_id=rules_by_id,
        profiles_by_id=profiles_by_id,
        audit_by_id=audit_by_id,
        latest_profile_version=latest_profile_version,
        latest_profile_updated_at=latest_profile_updated_at,
    )


def _profile_rule_ids(profile: dict[str, Any]) -> set[str]:
    rule_ids = set()
    for key in ("sourceRuleIds",):
        values = profile.get(key)
        if isinstance(values, list):
            rule_ids.update(value for value in values if isinstance(value, str) and value.strip())

    embedded = profile.get("profile")
    if isinstance(embedded, dict):
        active_rule_ids = embedded.get("activeRuleIds")
        if isinstance(active_rule_ids, list):
            rule_ids.update(value for value in active_rule_ids if isinstance(value, str) and value.strip())

        for directive_key in (
            "assistPreferences",
            "skillPreferences",
            "repairPreferences",
            "reviewPreferences",
            "plannerPreferences",
        ):
            directives = embedded.get(directive_key)
            if not isinstance(directives, list):
                continue
            for directive in directives:
                if not isinstance(directive, dict):
                    continue
                rule_id = directive.get("ruleId")
                if isinstance(rule_id, str) and rule_id.strip():
                    rule_ids.add(rule_id)

    return rule_ids


def _matches_basic_filters(
    payload: dict[str, Any],
    *,
    session_ids: set[str],
    task_ids: set[str],
    turn_ids: set[str],
) -> bool:
    if session_ids:
        session_id = payload.get("sessionId")
        if not isinstance(session_id, str) or session_id not in session_ids:
            return False
    if task_ids:
        task_id = payload.get("taskId")
        if not isinstance(task_id, str) or task_id not in task_ids:
            return False
    if turn_ids:
        turn_id = payload.get("turnId")
        if not isinstance(turn_id, str) or turn_id not in turn_ids:
            return False
    return True


def _rule_matches_filters(
    payload: dict[str, Any],
    *,
    session_ids: set[str],
    task_ids: set[str],
    turn_ids: set[str],
) -> bool:
    evidence = payload.get("evidence")
    if not isinstance(evidence, list):
        return False
    for item in evidence:
        if not isinstance(item, dict):
            continue
        if _matches_basic_filters(
            item,
            session_ids=session_ids,
            task_ids=task_ids,
            turn_ids=turn_ids,
        ):
            return True
    return False


def select_records(
    dataset: LoadedDataset,
    *,
    session_ids: list[str] | None = None,
    task_ids: list[str] | None = None,
    turn_ids: list[str] | None = None,
) -> dict[str, set[str]]:
    normalized_session_ids = {value.strip() for value in session_ids or [] if value.strip()}
    normalized_task_ids = {value.strip() for value in task_ids or [] if value.strip()}
    normalized_turn_ids = {value.strip() for value in turn_ids or [] if value.strip()}
    filters_enabled = bool(normalized_session_ids or normalized_task_ids or normalized_turn_ids)

    if not filters_enabled:
        return {
            "turns": set(dataset.turns_by_id.keys()),
            "evidence": set(dataset.evidence_by_id.keys()),
            "signals": set(dataset.signals_by_id.keys()),
            "rules": set(dataset.rules_by_id.keys()),
            "profiles": set(dataset.profiles_by_id.keys()),
            "audit": set(dataset.audit_by_id.keys()),
        }

    selected = {
        "turns": {
            turn_id
            for turn_id, entry in dataset.turns_by_id.items()
            if _matches_basic_filters(
                entry["payload"],
                session_ids=normalized_session_ids,
                task_ids=normalized_task_ids,
                turn_ids=normalized_turn_ids,
            )
        },
        "evidence": {
            evidence_id
            for evidence_id, entry in dataset.evidence_by_id.items()
            if _matches_basic_filters(
                entry["payload"],
                session_ids=normalized_session_ids,
                task_ids=normalized_task_ids,
                turn_ids=normalized_turn_ids,
            )
        },
        "signals": {
            signal_id
            for signal_id, entry in dataset.signals_by_id.items()
            if _matches_basic_filters(
                entry["payload"],
                session_ids=normalized_session_ids,
                task_ids=normalized_task_ids,
                turn_ids=normalized_turn_ids,
            )
        },
        "rules": {
            rule_id
            for rule_id, entry in dataset.rules_by_id.items()
            if _rule_matches_filters(
                entry["payload"],
                session_ids=normalized_session_ids,
                task_ids=normalized_task_ids,
                turn_ids=normalized_turn_ids,
            )
        },
        "profiles": set(),
        "audit": set(),
    }

    changed = True
    while changed:
        changed = False

        for signal_id in list(selected["signals"]):
            signal = dataset.signals_by_id[signal_id]["payload"]
            turn_id = signal.get("turnId")
            if isinstance(turn_id, str) and turn_id and turn_id not in selected["turns"]:
                selected["turns"].add(turn_id)
                changed = True
            evidence_ids = signal.get("evidenceIds") or []
            for evidence_id in evidence_ids:
                if isinstance(evidence_id, str) and evidence_id and evidence_id not in selected["evidence"]:
                    selected["evidence"].add(evidence_id)
                    changed = True

        for evidence_id in list(selected["evidence"]):
            entry = dataset.evidence_by_id.get(evidence_id)
            if not entry:
                continue
            evidence = entry["payload"]
            turn_id = evidence.get("turnId")
            if isinstance(turn_id, str) and turn_id and turn_id not in selected["turns"]:
                selected["turns"].add(turn_id)
                changed = True

        for turn_id in list(selected["turns"]):
            for evidence_id, entry in dataset.evidence_by_id.items():
                if evidence_id in selected["evidence"]:
                    continue
                evidence = entry["payload"]
                if evidence.get("turnId") == turn_id:
                    selected["evidence"].add(evidence_id)
                    changed = True
            for signal_id, entry in dataset.signals_by_id.items():
                if signal_id in selected["signals"]:
                    continue
                signal = entry["payload"]
                if signal.get("turnId") == turn_id:
                    selected["signals"].add(signal_id)
                    changed = True

        for rule_id in list(selected["rules"]):
            rule = dataset.rules_by_id[rule_id]["payload"]
            for signal_id in rule.get("sourceSignalIds") or []:
                if isinstance(signal_id, str) and signal_id and signal_id not in selected["signals"]:
                    selected["signals"].add(signal_id)
                    changed = True
            for evidence_ref in rule.get("evidence") or []:
                if not isinstance(evidence_ref, dict):
                    continue
                turn_id = evidence_ref.get("turnId")
                if isinstance(turn_id, str) and turn_id and turn_id not in selected["turns"]:
                    selected["turns"].add(turn_id)
                    changed = True
                signal_id = evidence_ref.get("signalId")
                if isinstance(signal_id, str) and signal_id and signal_id not in selected["signals"]:
                    selected["signals"].add(signal_id)
                    changed = True
                for evidence_id in evidence_ref.get("evidenceIds") or []:
                    if isinstance(evidence_id, str) and evidence_id and evidence_id not in selected["evidence"]:
                        selected["evidence"].add(evidence_id)
                        changed = True

        for rule_id, entry in dataset.rules_by_id.items():
            if rule_id in selected["rules"]:
                continue
            rule = entry["payload"]
            source_signal_ids = {
                value
                for value in rule.get("sourceSignalIds") or []
                if isinstance(value, str) and value.strip()
            }
            if source_signal_ids & selected["signals"]:
                selected["rules"].add(rule_id)
                changed = True

        for profile_id, entry in dataset.profiles_by_id.items():
            if profile_id in selected["profiles"]:
                continue
            if _profile_rule_ids(entry["payload"]) & selected["rules"]:
                selected["profiles"].add(profile_id)
                changed = True

        for profile_id in list(selected["profiles"]):
            profile = dataset.profiles_by_id[profile_id]["payload"]
            for rule_id in _profile_rule_ids(profile):
                if rule_id not in selected["rules"] and rule_id in dataset.rules_by_id:
                    selected["rules"].add(rule_id)
                    changed = True

        for audit_id, entry in dataset.audit_by_id.items():
            if audit_id in selected["audit"]:
                continue
            audit = entry["payload"]
            rule_ids = set()
            for field_name in ("ruleId", "relatedRuleId"):
                value = audit.get(field_name)
                if isinstance(value, str) and value.strip():
                    rule_ids.add(value)
            affected_rule_ids = audit.get("affectedRuleIds")
            if isinstance(affected_rule_ids, list):
                rule_ids.update(
                    value for value in affected_rule_ids if isinstance(value, str) and value.strip()
                )

            profile_versions = set()
            for field_name in ("profileVersion", "relatedProfileVersion"):
                value = audit.get(field_name)
                if isinstance(value, str) and value.strip():
                    profile_versions.add(value)

            signal_ids = {
                value
                for value in audit.get("signalIds") or []
                if isinstance(value, str) and value.strip()
            }

            if (
                rule_ids & selected["rules"]
                or profile_versions & selected["profiles"]
                or signal_ids & selected["signals"]
            ):
                selected["audit"].add(audit_id)
                changed = True

        for audit_id in list(selected["audit"]):
            audit = dataset.audit_by_id[audit_id]["payload"]
            for signal_id in audit.get("signalIds") or []:
                if isinstance(signal_id, str) and signal_id in dataset.signals_by_id and signal_id not in selected["signals"]:
                    selected["signals"].add(signal_id)
                    changed = True
            for field_name in ("ruleId", "relatedRuleId"):
                value = audit.get(field_name)
                if isinstance(value, str) and value in dataset.rules_by_id and value not in selected["rules"]:
                    selected["rules"].add(value)
                    changed = True
            for rule_id in audit.get("affectedRuleIds") or []:
                if isinstance(rule_id, str) and rule_id in dataset.rules_by_id and rule_id not in selected["rules"]:
                    selected["rules"].add(rule_id)
                    changed = True
            for field_name in ("profileVersion", "relatedProfileVersion"):
                value = audit.get(field_name)
                if isinstance(value, str) and value in dataset.profiles_by_id and value not in selected["profiles"]:
                    selected["profiles"].add(value)
                    changed = True

    return selected


def _selected_records_for_artifact(artifact: Artifact, selected_ids: set[str]) -> list[dict[str, Any]]:
    return [
        record
        for record in artifact.records
        if isinstance(record, dict)
        and isinstance(record.get(ID_FIELD_BY_CATEGORY[artifact.category]), str)
        and record[ID_FIELD_BY_CATEGORY[artifact.category]] in selected_ids
    ]


def export_bundle(
    dataset: LoadedDataset,
    output_dir: Path,
    *,
    learning_root: Path,
    preferences_root: Path,
    session_ids: list[str] | None = None,
    task_ids: list[str] | None = None,
    turn_ids: list[str] | None = None,
    bundle_id: str | None = None,
    overwrite: bool = False,
    created_at: str | None = None,
) -> dict[str, Any]:
    created_at = created_at or now_iso()
    bundle_id = bundle_id or f"learning-bundle-{created_at.replace(':', '').replace('-', '').replace('T', '-').replace('Z', 'z')}"
    selected = select_records(
        dataset,
        session_ids=session_ids,
        task_ids=task_ids,
        turn_ids=turn_ids,
    )

    ensure_clean_output_directory(output_dir, overwrite=overwrite)

    manifest_counts = category_counts_template()
    manifest_artifacts: list[dict[str, Any]] = []

    for category in CATEGORY_ORDER:
        for artifact in dataset.artifacts_by_category[category]:
            selected_records = _selected_records_for_artifact(artifact, selected[category])
            if not selected_records:
                continue

            bundle_path = output_dir / artifact.bundle_relative_path
            bundle_path.parent.mkdir(parents=True, exist_ok=True)
            if artifact.record_format == "jsonl":
                write_jsonl(bundle_path, selected_records)
            elif artifact.category in {"signals"}:
                write_json(bundle_path, selected_records)
            else:
                write_json(bundle_path, selected_records[0])

            object_ids = [
                record[ID_FIELD_BY_CATEGORY[category]]
                for record in selected_records
                if isinstance(record.get(ID_FIELD_BY_CATEGORY[category]), str)
            ]
            manifest_counts[category]["files"] += 1
            manifest_counts[category]["records"] += len(object_ids)
            manifest_artifacts.append(
                {
                    "category": category,
                    "format": artifact.record_format,
                    "sourcePath": repo_relative_or_abs(artifact.source_path),
                    "sourceRelativePath": artifact.source_relative_path,
                    "payloadPath": artifact.bundle_relative_path,
                    "restorePath": artifact.restore_relative_path,
                    "recordCount": len(object_ids),
                    "recordIds": object_ids,
                    "sha256": sha256_file(bundle_path),
                    "sizeBytes": bundle_path.stat().st_size,
                }
            )

    included_profiles = selected["profiles"]
    latest_profile_version: str | None = None
    latest_profile_updated_at: str | None = None
    if dataset.latest_profile_version and dataset.latest_profile_version in included_profiles:
        latest_profile_version = dataset.latest_profile_version
        latest_profile_updated_at = dataset.latest_profile_updated_at or created_at

    manifest = {
        "schemaVersion": MANIFEST_SCHEMA_VERSION,
        "bundleSchemaVersion": BUNDLE_SCHEMA_VERSION,
        "bundleId": bundle_id,
        "createdAt": created_at,
        "source": {
            "learningRoot": repo_relative_or_abs(learning_root),
            "preferencesRoot": repo_relative_or_abs(preferences_root),
            "filters": {
                "sessionIds": sorted({value.strip() for value in session_ids or [] if value.strip()}),
                "taskIds": sorted({value.strip() for value in task_ids or [] if value.strip()}),
                "turnIds": sorted({value.strip() for value in turn_ids or [] if value.strip()}),
            },
        },
        "counts": manifest_counts,
        "indexes": {
            "turnIds": sorted(selected["turns"]),
            "evidenceIds": sorted(selected["evidence"]),
            "signalIds": sorted(selected["signals"]),
            "ruleIds": sorted(selected["rules"]),
            "profileVersions": sorted(selected["profiles"]),
            "auditIds": sorted(selected["audit"]),
            "latestProfileVersion": latest_profile_version,
            "latestProfileUpdatedAt": latest_profile_updated_at,
        },
        "artifacts": manifest_artifacts,
    }

    write_json(output_dir / "manifest.json", manifest)
    verification = verify_bundle(output_dir)
    write_json(output_dir / "verification.json", verification)

    manifest["payloadVerification"] = {
        "path": "verification.json",
        "passed": verification["passed"],
        "checkedAt": verification["checkedAt"],
        "issueCount": len(verification["issues"]),
        "warningCount": verification["summary"]["warningCount"],
        "errorCount": verification["summary"]["errorCount"],
    }
    write_json(output_dir / "manifest.json", manifest)

    return {
        "schemaVersion": BUNDLE_SCHEMA_VERSION,
        "bundleId": bundle_id,
        "bundlePath": str(output_dir.resolve()),
        "manifestPath": str((output_dir / "manifest.json").resolve()),
        "verificationPath": str((output_dir / "verification.json").resolve()),
        "counts": manifest_counts,
        "indexes": manifest["indexes"],
        "passed": verification["passed"],
        "issues": verification["issues"],
    }


def _category_from_restore_path(restore_path: str) -> str | None:
    for category, prefix in RESTORE_RELATIVE_ROOT.items():
        prefix_text = prefix.as_posix()
        if restore_path == prefix_text or restore_path.startswith(prefix_text + "/"):
            return category
    return None


def _load_bundle_manifest(bundle_dir: Path) -> dict[str, Any]:
    manifest_path = bundle_dir / "manifest.json"
    if not manifest_path.exists():
        raise ValueError(f"Bundle manifest not found: {manifest_path}")
    manifest = read_json(manifest_path)
    if not isinstance(manifest, dict):
        raise ValueError(f"Bundle manifest is not an object: {manifest_path}")
    return manifest


def _validate_record_structure(category: str, record: dict[str, Any]) -> list[dict[str, Any]]:
    id_field = ID_FIELD_BY_CATEGORY[category]
    issues: list[dict[str, Any]] = []
    record_id = record.get(id_field)
    if not isinstance(record_id, str) or not record_id.strip():
        issues.append(issue("error", "LB-MISSING-ID", f"{category} record is missing {id_field}.", category=category))
        return issues

    schema_version = record.get("schemaVersion")
    expected_schema = EXPECTED_RECORD_SCHEMA[category]
    if schema_version != expected_schema:
        issues.append(
            issue(
                "error",
                "LB-SCHEMA-MISMATCH",
                f"{category} record {record_id} expected schema {expected_schema}, got {schema_version!r}.",
                category=category,
                recordId=record_id,
            )
        )

    required_fields = {
        "turns": ["turnId", "traceId", "sessionId", "taskId", "stepId"],
        "evidence": ["evidenceId", "turnId", "sessionId", "taskId", "stepId", "timestamp"],
        "signals": ["signalId", "turnId", "sessionId", "taskId", "stepId", "timestamp"],
        "rules": ["ruleId", "sourceSignalIds", "evidence", "createdAt", "updatedAt"],
        "profiles": ["profileVersion", "profile", "sourceRuleIds", "createdAt"],
        "audit": ["auditId", "action", "timestamp", "actor", "source"],
    }[category]
    for field_name in required_fields:
        value = record.get(field_name)
        if value is None or (isinstance(value, str) and not value.strip()):
            issues.append(
                issue(
                    "error",
                    "LB-MISSING-FIELD",
                    f"{category} record {record_id} is missing {field_name}.",
                    category=category,
                    recordId=record_id,
                    field=field_name,
                )
            )

    if category == "signals":
        evidence_ids = record.get("evidenceIds")
        if not isinstance(evidence_ids, list) or not evidence_ids:
            issues.append(
                issue(
                    "error",
                    "LB-MISSING-EVIDENCE-LINK",
                    f"signals record {record_id} must reference at least one evidenceId.",
                    category=category,
                    recordId=record_id,
                )
            )

    if category == "rules":
        source_signal_ids = record.get("sourceSignalIds")
        evidence = record.get("evidence")
        if not isinstance(source_signal_ids, list) or not source_signal_ids:
            issues.append(
                issue(
                    "error",
                    "LB-MISSING-SIGNAL-LINK",
                    f"rules record {record_id} must reference sourceSignalIds.",
                    category=category,
                    recordId=record_id,
                )
            )
        if not isinstance(evidence, list) or not evidence:
            issues.append(
                issue(
                    "error",
                    "LB-MISSING-RULE-EVIDENCE",
                    f"rules record {record_id} must include evidence rows.",
                    category=category,
                    recordId=record_id,
                )
            )

    if category == "profiles":
        embedded = record.get("profile")
        if isinstance(embedded, dict):
            embedded_version = embedded.get("profileVersion")
            if embedded_version != record_id:
                issues.append(
                    issue(
                        "error",
                        "LB-PROFILE-VERSION-MISMATCH",
                        f"profile snapshot {record_id} does not match embedded profileVersion {embedded_version!r}.",
                        category=category,
                        recordId=record_id,
                    )
                )
        else:
            issues.append(
                issue(
                    "error",
                    "LB-MISSING-EMBEDDED-PROFILE",
                    f"profile snapshot {record_id} is missing embedded profile payload.",
                    category=category,
                    recordId=record_id,
                )
            )

    return issues


def verify_bundle(bundle_dir: Path) -> dict[str, Any]:
    checked_at = now_iso()
    manifest_path = bundle_dir / "manifest.json"
    issues: list[dict[str, Any]] = []
    counts = category_counts_template()
    turns_by_id: dict[str, dict[str, Any]] = {}
    evidence_by_id: dict[str, dict[str, Any]] = {}
    signals_by_id: dict[str, dict[str, Any]] = {}
    rules_by_id: dict[str, dict[str, Any]] = {}
    profiles_by_id: dict[str, dict[str, Any]] = {}
    audit_by_id: dict[str, dict[str, Any]] = {}

    if not manifest_path.exists():
        issues.append(issue("error", "LB-MISSING-MANIFEST", "manifest.json is missing.", path="manifest.json"))
        return {
            "schemaVersion": VERIFICATION_SCHEMA_VERSION,
            "bundlePath": str(bundle_dir.resolve()),
            "checkedAt": checked_at,
            "passed": False,
            "summary": {"errorCount": 1, "warningCount": 0},
            "counts": counts,
            "issues": issues,
        }

    manifest = read_json(manifest_path)
    if not isinstance(manifest, dict):
        issues.append(issue("error", "LB-INVALID-MANIFEST", "manifest.json must be an object.", path="manifest.json"))
        return {
            "schemaVersion": VERIFICATION_SCHEMA_VERSION,
            "bundlePath": str(bundle_dir.resolve()),
            "checkedAt": checked_at,
            "passed": False,
            "summary": {"errorCount": 1, "warningCount": 0},
            "counts": counts,
            "issues": issues,
        }

    if manifest.get("schemaVersion") != MANIFEST_SCHEMA_VERSION:
        issues.append(
            issue(
                "error",
                "LB-MANIFEST-SCHEMA-MISMATCH",
                f"manifest schemaVersion must be {MANIFEST_SCHEMA_VERSION}.",
                path="manifest.json",
            )
        )

    if manifest.get("bundleSchemaVersion") != BUNDLE_SCHEMA_VERSION:
        issues.append(
            issue(
                "error",
                "LB-BUNDLE-SCHEMA-MISMATCH",
                f"bundleSchemaVersion must be {BUNDLE_SCHEMA_VERSION}.",
                path="manifest.json",
            )
        )

    artifacts = manifest.get("artifacts")
    if not isinstance(artifacts, list):
        issues.append(issue("error", "LB-MISSING-ARTIFACTS", "manifest.artifacts must be an array.", path="manifest.json"))
        artifacts = []

    for artifact in artifacts:
        if not isinstance(artifact, dict):
            issues.append(issue("error", "LB-INVALID-ARTIFACT", "manifest artifact must be an object.", path="manifest.json"))
            continue

        category = artifact.get("category")
        payload_path = artifact.get("payloadPath")
        restore_path = artifact.get("restorePath")
        declared_record_ids = artifact.get("recordIds")
        record_format = artifact.get("format")
        if category not in CATEGORY_ORDER:
            issues.append(issue("error", "LB-UNKNOWN-CATEGORY", f"Unknown artifact category: {category!r}.", path="manifest.json"))
            continue
        if record_format != FORMAT_BY_CATEGORY[category]:
            issues.append(
                issue(
                    "error",
                    "LB-FORMAT-MISMATCH",
                    f"Artifact {payload_path!r} expected format {FORMAT_BY_CATEGORY[category]}, got {record_format!r}.",
                    category=category,
                    path="manifest.json",
                )
            )
            continue
        if not isinstance(payload_path, str) or not payload_path:
            issues.append(issue("error", "LB-MISSING-PAYLOAD-PATH", "Artifact is missing payloadPath.", category=category, path="manifest.json"))
            continue
        if not isinstance(restore_path, str) or not restore_path:
            issues.append(issue("error", "LB-MISSING-RESTORE-PATH", "Artifact is missing restorePath.", category=category, path="manifest.json"))
            continue
        if Path(payload_path).is_absolute() or ".." in Path(payload_path).parts:
            issues.append(issue("error", "LB-UNSAFE-PAYLOAD-PATH", f"Unsafe payloadPath: {payload_path}.", category=category, path="manifest.json"))
            continue
        if Path(restore_path).is_absolute() or ".." in Path(restore_path).parts:
            issues.append(issue("error", "LB-UNSAFE-RESTORE-PATH", f"Unsafe restorePath: {restore_path}.", category=category, path="manifest.json"))
            continue
        expected_category = _category_from_restore_path(restore_path)
        if expected_category != category:
            issues.append(
                issue(
                    "error",
                    "LB-RESTORE-CATEGORY-MISMATCH",
                    f"Artifact restorePath {restore_path} does not belong to {category}.",
                    category=category,
                    path="manifest.json",
                )
            )
            continue

        artifact_path = bundle_dir / payload_path
        if not artifact_path.exists():
            issues.append(
                issue(
                    "error",
                    "LB-MISSING-PAYLOAD",
                    f"Artifact payload is missing: {payload_path}.",
                    category=category,
                    path=payload_path,
                )
            )
            continue

        if category in {"evidence", "audit"}:
            records = read_jsonl(artifact_path)
        elif category == "signals":
            loaded = read_json(artifact_path)
            records = loaded if isinstance(loaded, list) else []
        else:
            loaded = read_json(artifact_path)
            records = [loaded] if isinstance(loaded, dict) else []

        actual_record_ids: list[str] = []
        id_field = ID_FIELD_BY_CATEGORY[category]
        for record in records:
            if not isinstance(record, dict):
                issues.append(
                    issue(
                        "error",
                        "LB-INVALID-RECORD",
                        f"{payload_path} contains a non-object record.",
                        category=category,
                        path=payload_path,
                    )
                )
                continue
            actual_record_ids.append(record.get(id_field))
            issues.extend(
                _validate_record_structure(category, record)
            )
            if category == "turns":
                turns_by_id[record[id_field]] = record
            elif category == "evidence":
                evidence_by_id[record[id_field]] = record
            elif category == "signals":
                signals_by_id[record[id_field]] = record
            elif category == "rules":
                rules_by_id[record[id_field]] = record
            elif category == "profiles":
                profiles_by_id[record[id_field]] = record
            elif category == "audit":
                audit_by_id[record[id_field]] = record

        counts[category]["files"] += 1
        counts[category]["records"] += len(records)

        if not isinstance(declared_record_ids, list):
            issues.append(
                issue(
                    "error",
                    "LB-MISSING-RECORD-IDS",
                    f"Artifact {payload_path} is missing recordIds.",
                    category=category,
                    path="manifest.json",
                )
            )
        else:
            normalized_declared = [
                value for value in declared_record_ids if isinstance(value, str) and value.strip()
            ]
            normalized_actual = [
                value for value in actual_record_ids if isinstance(value, str) and value.strip()
            ]
            if normalized_declared != normalized_actual:
                issues.append(
                    issue(
                        "error",
                        "LB-RECORD-ID-MISMATCH",
                        f"Artifact {payload_path} recordIds do not match payload contents.",
                        category=category,
                        path=payload_path,
                    )
                )

        declared_sha256 = artifact.get("sha256")
        if declared_sha256 != sha256_file(artifact_path):
            issues.append(
                issue(
                    "error",
                    "LB-SHA256-MISMATCH",
                    f"Artifact {payload_path} sha256 does not match payload.",
                    category=category,
                    path=payload_path,
                )
            )

    manifest_counts = manifest.get("counts")
    if isinstance(manifest_counts, dict):
        for category in CATEGORY_ORDER:
            expected = manifest_counts.get(category)
            if not isinstance(expected, dict):
                issues.append(
                    issue(
                        "error",
                        "LB-MISSING-CATEGORY-COUNT",
                        f"manifest.counts is missing {category}.",
                        category=category,
                        path="manifest.json",
                    )
                )
                continue
            if expected.get("files") != counts[category]["files"] or expected.get("records") != counts[category]["records"]:
                issues.append(
                    issue(
                        "error",
                        "LB-COUNT-MISMATCH",
                        f"manifest count mismatch for {category}.",
                        category=category,
                        path="manifest.json",
                    )
                )

    for evidence_id, evidence in evidence_by_id.items():
        turn_id = evidence.get("turnId")
        if turn_id not in turns_by_id:
            issues.append(
                issue(
                    "error",
                    "LB-MISSING-TURN",
                    f"evidence {evidence_id} references missing turn {turn_id!r}.",
                    category="evidence",
                    recordId=evidence_id,
                )
            )

    for signal_id, signal in signals_by_id.items():
        turn_id = signal.get("turnId")
        if turn_id not in turns_by_id:
            issues.append(
                issue(
                    "error",
                    "LB-MISSING-TURN",
                    f"signal {signal_id} references missing turn {turn_id!r}.",
                    category="signals",
                    recordId=signal_id,
                )
            )
        for evidence_id in signal.get("evidenceIds") or []:
            if evidence_id not in evidence_by_id:
                issues.append(
                    issue(
                        "error",
                        "LB-MISSING-EVIDENCE",
                        f"signal {signal_id} references missing evidence {evidence_id!r}.",
                        category="signals",
                        recordId=signal_id,
                    )
                )

    for rule_id, rule in rules_by_id.items():
        for signal_id in rule.get("sourceSignalIds") or []:
            if signal_id not in signals_by_id:
                issues.append(
                    issue(
                        "error",
                        "LB-MISSING-SIGNAL",
                        f"rule {rule_id} references missing signal {signal_id!r}.",
                        category="rules",
                        recordId=rule_id,
                    )
                )
        for evidence_ref in rule.get("evidence") or []:
            if not isinstance(evidence_ref, dict):
                continue
            signal_id = evidence_ref.get("signalId")
            if signal_id not in signals_by_id:
                issues.append(
                    issue(
                        "error",
                        "LB-MISSING-SIGNAL",
                        f"rule {rule_id} evidence references missing signal {signal_id!r}.",
                        category="rules",
                        recordId=rule_id,
                    )
                )
            turn_id = evidence_ref.get("turnId")
            if turn_id not in turns_by_id:
                issues.append(
                    issue(
                        "error",
                        "LB-MISSING-TURN",
                        f"rule {rule_id} evidence references missing turn {turn_id!r}.",
                        category="rules",
                        recordId=rule_id,
                    )
                )
            for evidence_id in evidence_ref.get("evidenceIds") or []:
                if evidence_id not in evidence_by_id:
                    issues.append(
                        issue(
                            "error",
                            "LB-MISSING-EVIDENCE",
                            f"rule {rule_id} references missing evidence {evidence_id!r}.",
                            category="rules",
                            recordId=rule_id,
                        )
                    )

    for profile_id, profile in profiles_by_id.items():
        for rule_id in _profile_rule_ids(profile):
            if rule_id not in rules_by_id:
                issues.append(
                    issue(
                        "error",
                        "LB-MISSING-RULE",
                        f"profile {profile_id} references missing rule {rule_id!r}.",
                        category="profiles",
                        recordId=profile_id,
                    )
                )

    for audit_id, audit in audit_by_id.items():
        for signal_id in audit.get("signalIds") or []:
            if signal_id and signal_id not in signals_by_id:
                issues.append(
                    issue(
                        "warning",
                        "LB-AUDIT-MISSING-SIGNAL",
                        f"audit {audit_id} references signal {signal_id!r} that is not present in this bundle.",
                        category="audit",
                        recordId=audit_id,
                    )
                )
        for field_name in ("ruleId", "relatedRuleId"):
            value = audit.get(field_name)
            if isinstance(value, str) and value and value not in rules_by_id:
                issues.append(
                    issue(
                        "warning",
                        "LB-AUDIT-MISSING-RULE",
                        f"audit {audit_id} references rule {value!r} that is not present in this bundle.",
                        category="audit",
                        recordId=audit_id,
                    )
                )
        for rule_id in audit.get("affectedRuleIds") or []:
            if isinstance(rule_id, str) and rule_id and rule_id not in rules_by_id:
                issues.append(
                    issue(
                        "warning",
                        "LB-AUDIT-MISSING-RULE",
                        f"audit {audit_id} references affected rule {rule_id!r} that is not present in this bundle.",
                        category="audit",
                        recordId=audit_id,
                    )
                )
        for field_name in ("profileVersion", "relatedProfileVersion"):
            value = audit.get(field_name)
            if isinstance(value, str) and value and value not in profiles_by_id:
                issues.append(
                    issue(
                        "warning",
                        "LB-AUDIT-MISSING-PROFILE",
                        f"audit {audit_id} references profile {value!r} that is not present in this bundle.",
                        category="audit",
                        recordId=audit_id,
                    )
                )

    indexes = manifest.get("indexes")
    if isinstance(indexes, dict):
        latest_profile_version = indexes.get("latestProfileVersion")
        if latest_profile_version is not None and latest_profile_version not in profiles_by_id:
            issues.append(
                issue(
                    "error",
                    "LB-MISSING-LATEST-PROFILE",
                    f"indexes.latestProfileVersion {latest_profile_version!r} is not present in the bundle.",
                    path="manifest.json",
                )
            )

    error_count = sum(1 for item in issues if item["severity"] == "error")
    warning_count = sum(1 for item in issues if item["severity"] == "warning")

    return {
        "schemaVersion": VERIFICATION_SCHEMA_VERSION,
        "bundlePath": str(bundle_dir.resolve()),
        "checkedAt": checked_at,
        "passed": error_count == 0,
        "summary": {
            "errorCount": error_count,
            "warningCount": warning_count,
        },
        "counts": counts,
        "issues": issues,
    }


def preview_restore(
    bundle_dir: Path,
    workspace_root: Path,
    *,
    overwrite: bool = False,
) -> dict[str, Any]:
    manifest = _load_bundle_manifest(bundle_dir)
    planned_writes: list[dict[str, Any]] = []
    conflict_count = 0

    for artifact in sorted(
        manifest.get("artifacts") or [],
        key=lambda item: (str(item.get("restorePath", "")), str(item.get("payloadPath", ""))),
    ):
        if not isinstance(artifact, dict):
            continue
        restore_path = artifact.get("restorePath")
        payload_path = artifact.get("payloadPath")
        category = artifact.get("category")
        if not isinstance(restore_path, str) or not isinstance(payload_path, str) or not isinstance(category, str):
            continue

        destination = workspace_root / restore_path
        source = bundle_dir / payload_path
        exists = destination.exists()
        if exists and not overwrite:
            status = "conflict"
            conflict_count += 1
        elif exists and overwrite:
            status = "overwrite"
        else:
            status = "create"

        planned_writes.append(
            {
                "category": category,
                "payloadPath": payload_path,
                "restorePath": restore_path,
                "status": status,
                "recordCount": artifact.get("recordCount", 0),
                "recordIds": artifact.get("recordIds", []),
                "sizeBytes": source.stat().st_size if source.exists() else 0,
            }
        )

    return {
        "workspaceRoot": str(workspace_root.resolve()),
        "overwrite": overwrite,
        "restoreReady": conflict_count == 0,
        "conflictCount": conflict_count,
        "plannedWrites": planned_writes,
    }


def apply_restore(
    bundle_dir: Path,
    workspace_root: Path,
    *,
    overwrite: bool = False,
) -> dict[str, Any]:
    preview = preview_restore(bundle_dir, workspace_root, overwrite=overwrite)
    if not preview["restoreReady"]:
        raise ValueError("Restore preview contains conflicts. Re-run with overwrite enabled or choose a clean target.")

    manifest = _load_bundle_manifest(bundle_dir)
    for item in preview["plannedWrites"]:
        source = bundle_dir / item["payloadPath"]
        destination = workspace_root / item["restorePath"]
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, destination)

    indexes = manifest.get("indexes") or {}
    latest_profile_version = indexes.get("latestProfileVersion")
    latest_profile_updated_at = indexes.get("latestProfileUpdatedAt") or manifest.get("createdAt") or now_iso()
    if isinstance(latest_profile_version, str) and latest_profile_version.strip():
        profiles_root = workspace_root / RESTORE_RELATIVE_ROOT["profiles"]
        profiles_root.mkdir(parents=True, exist_ok=True)
        write_json(
            profiles_root / "latest.json",
            encode_latest_profile_pointer(latest_profile_version, latest_profile_updated_at),
        )

    return {
        "workspaceRoot": str(workspace_root.resolve()),
        "applied": True,
        "overwrite": overwrite,
        "writtenFileCount": len(preview["plannedWrites"]),
        "plannedWrites": preview["plannedWrites"],
        "latestProfileVersion": latest_profile_version,
    }
