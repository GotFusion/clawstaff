#!/usr/bin/env python3
"""Build semantic action records directly from raw event streams."""

from __future__ import annotations

import json
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path
from typing import Any

from semantic_selector_extractor import (
    build_accessibility_selector_chain,
    event_context,
    event_pointer,
    exact_window_title_pattern,
    selector_chain_summary,
    selector_manual_review_required,
    selector_strategy_confidence,
)
from semantic_action_store import (
    SCHEMA_VERSION,
    SemanticActionAssertionRecord,
    SemanticActionExecutionLogRecord,
    SemanticActionRecord,
    SemanticActionTargetRecord,
)


BUILDER_VERSION = "sem-101-102-rule-v1"
PRINTABLE_SHORTCUT_EXCLUSIONS = {"\r", "\n", "\t", "\x03", "\x7f", "\x1b"}
KEY_CODE_NAMES = {
    36: "return",
    48: "tab",
    49: "space",
    51: "delete",
    53: "escape",
}


@dataclass(frozen=True)
class ActionBuilderConfig:
    type_gap_ms: int = 1200
    shortcut_gap_ms: int = 900


@dataclass
class EventCluster:
    kind: str
    events: list[dict[str, Any]] = field(default_factory=list)
    diagnostics: list[str] = field(default_factory=list)


@dataclass(frozen=True)
class ActionBuildBundle:
    action: SemanticActionRecord
    targets: list[SemanticActionTargetRecord]
    assertions: list[SemanticActionAssertionRecord]
    execution_logs: list[SemanticActionExecutionLogRecord]
    diagnostics: list[str]


def read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def read_jsonl(path: Path) -> list[dict[str, Any]]:
    records: list[dict[str, Any]] = []
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line:
            continue
        records.append(json.loads(line))
    return records


def repo_relative_or_abs(path: Path, workspace_root: Path) -> str:
    try:
        return path.resolve().relative_to(workspace_root.resolve()).as_posix()
    except ValueError:
        return path.resolve().as_posix()


def parse_iso_timestamp(value: str | None) -> datetime | None:
    if not isinstance(value, str) or not value.strip():
        return None
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None


def duration_millis(started_at: str | None, ended_at: str | None) -> int | None:
    started = parse_iso_timestamp(started_at)
    ended = parse_iso_timestamp(ended_at)
    if started is None or ended is None:
        return None
    return max(int((ended - started).total_seconds() * 1000), 0)


def time_gap_millis(previous: dict[str, Any], current: dict[str, Any]) -> int | None:
    return duration_millis(previous.get("timestamp"), current.get("timestamp"))


def context_key(event: dict[str, Any]) -> tuple[str | None, str | None, str | None]:
    context = event_context(event)
    signature = context.get("windowSignature")
    signature_value = signature.get("signature") if isinstance(signature, dict) else None
    return (
        context.get("appBundleId"),
        context.get("windowTitle"),
        signature_value,
    )


def event_id(event: dict[str, Any]) -> str | None:
    value = event.get("eventId")
    return value.strip() if isinstance(value, str) and value.strip() else None


def keyboard_payload(event: dict[str, Any]) -> dict[str, Any]:
    payload = event.get("keyboard")
    return payload if isinstance(payload, dict) else {}


def keyboard_char(event: dict[str, Any]) -> str | None:
    payload = keyboard_payload(event)
    for key in ("charactersIgnoringModifiers", "characters"):
        value = payload.get(key)
        if isinstance(value, str) and value != "":
            return value
    return None


def key_name(event: dict[str, Any]) -> str | None:
    payload = keyboard_payload(event)
    key_code = payload.get("keyCode")
    if isinstance(key_code, int) and key_code in KEY_CODE_NAMES:
        return KEY_CODE_NAMES[key_code]

    character = keyboard_char(event)
    if not isinstance(character, str) or character == "":
        return None
    if character in {"\r", "\n"}:
        return "return"
    if character == "\t":
        return "tab"
    if character == "\x7f":
        return "delete"
    if character == "\x1b":
        return "escape"
    if character == "\x03":
        return "control_c"
    return character.lower()


def is_printable_text_key(event: dict[str, Any]) -> bool:
    if event.get("action") != "keyDown":
        return False
    if event.get("modifiers"):
        return False
    character = keyboard_char(event)
    if not isinstance(character, str) or len(character) != 1:
        return False
    if character in PRINTABLE_SHORTCUT_EXCLUSIONS:
        return False
    return character.isprintable()


def event_kind(event: dict[str, Any]) -> str | None:
    action = event.get("action")
    if action in {"leftClick", "rightClick", "doubleClick"}:
        return "click"
    if action == "keyDown":
        return "type" if is_printable_text_key(event) else "shortcut"
    return None


def same_context(left: dict[str, Any], right: dict[str, Any]) -> bool:
    return context_key(left) == context_key(right)


def shortcut_signature(event: dict[str, Any]) -> tuple[str, ...]:
    modifiers = tuple(sorted(str(value).lower() for value in (event.get("modifiers") or []) if isinstance(value, str)))
    key = key_name(event) or "unknown"
    return modifiers + (key,)


def should_merge(cluster: EventCluster, event: dict[str, Any], config: ActionBuilderConfig) -> bool:
    if not cluster.events:
        return True
    previous = cluster.events[-1]
    if not same_context(previous, event):
        return False
    if event_kind(event) != cluster.kind:
        return False

    gap_ms = time_gap_millis(previous, event)
    if gap_ms is None:
        return False

    if cluster.kind == "type":
        return gap_ms <= config.type_gap_ms
    if cluster.kind == "shortcut":
        return gap_ms <= config.shortcut_gap_ms and shortcut_signature(previous) == shortcut_signature(event)
    return False


def app_context_selector(context: dict[str, Any]) -> dict[str, Any]:
    return {
        "locatorType": "appContext",
        "selectorKind": "appContext",
        "selectorStrategy": "app_context",
        "appBundleId": context.get("appBundleId"),
        "appName": context.get("appName"),
        "windowTitlePattern": exact_window_title_pattern(context.get("windowTitle")),
        "windowSignature": context.get("windowSignature"),
        "url": context.get("url"),
        "urlHost": context.get("urlHost"),
        "confidence": selector_strategy_confidence("app_context"),
        "source": "raw-event-context-transition",
    }


def window_context_selector(context: dict[str, Any]) -> dict[str, Any]:
    return {
        "locatorType": "windowContext",
        "selectorKind": "windowContext",
        "selectorStrategy": "window_context",
        "appBundleId": context.get("appBundleId"),
        "appName": context.get("appName"),
        "windowTitlePattern": exact_window_title_pattern(context.get("windowTitle")),
        "windowSignature": context.get("windowSignature"),
        "url": context.get("url"),
        "urlHost": context.get("urlHost"),
        "confidence": selector_strategy_confidence("window_context"),
        "source": "raw-event-context-transition",
    }


def event_summary(event: dict[str, Any]) -> dict[str, Any]:
    context = event_context(event)
    return {
        "eventId": event_id(event),
        "timestamp": event.get("timestamp"),
        "action": event.get("action"),
        "appBundleId": context.get("appBundleId"),
        "windowTitle": context.get("windowTitle"),
        "pointer": event_pointer(event),
        "key": key_name(event),
    }


def normalize_target_role(locator_type: str | None, is_preferred: bool) -> str:
    if is_preferred:
        return "primary"
    if locator_type == "coordinateFallback":
        return "fallback"
    return "candidate"


def build_target_records(
    action_id: str,
    selectors: list[dict[str, Any]],
    created_at: str,
) -> list[SemanticActionTargetRecord]:
    targets: list[SemanticActionTargetRecord] = []
    for index, selector in enumerate(selectors, start=1):
        locator_type = selector.get("locatorType")
        targets.append(
            SemanticActionTargetRecord(
                target_id=f"{action_id}:target:{index:02d}",
                target_role=normalize_target_role(locator_type, index == 1),
                ordinal=index,
                locator_type=locator_type,
                selector=selector,
                context={},
                confidence=float(selector.get("confidence") or 0.0) if selector.get("confidence") is not None else None,
                is_preferred=(index == 1),
                created_at=created_at,
            )
        )
    return targets


def build_assertions(
    action_id: str,
    selector: dict[str, Any],
    context: dict[str, Any],
    created_at: str,
) -> list[SemanticActionAssertionRecord]:
    assertions: list[SemanticActionAssertionRecord] = []
    app_bundle_id = context.get("appBundleId")
    if isinstance(app_bundle_id, str) and app_bundle_id.strip():
        assertions.append(
            SemanticActionAssertionRecord(
                assertion_id=f"{action_id}:assertion:required-frontmost-app",
                assertion_type="requiredFrontmostApp",
                assertion={"appBundleId": app_bundle_id.strip()},
                created_at=created_at,
                source="sem101-builder",
                ordinal=0,
            )
        )

    window_title_pattern = selector.get("windowTitlePattern")
    if isinstance(window_title_pattern, str) and window_title_pattern.strip():
        assertions.append(
            SemanticActionAssertionRecord(
                assertion_id=f"{action_id}:assertion:window-title",
                assertion_type="windowTitlePattern",
                assertion={"pattern": window_title_pattern.strip()},
                created_at=created_at,
                source="sem101-builder",
                ordinal=1,
            )
        )

    locator_type = selector.get("locatorType")
    if isinstance(locator_type, str) and locator_type not in {"unknown"}:
        assertions.append(
            SemanticActionAssertionRecord(
                assertion_id=f"{action_id}:assertion:selector-resolvable",
                assertion_type="selectorResolvable",
                assertion={
                    "locatorType": locator_type,
                    "selectorKind": selector.get("selectorKind"),
                    "selectorStrategy": selector.get("selectorStrategy"),
                    "elementRole": selector.get("elementRole"),
                    "elementIdentifier": selector.get("elementIdentifier"),
                    "axPath": selector.get("axPath"),
                },
                created_at=created_at,
                source="sem101-builder",
                ordinal=2,
            )
        )

    return assertions


def action_context_payload(
    *,
    action_type: str,
    task_chunk: dict[str, Any],
    raw_event_log_path: Path,
    task_chunk_path: Path,
    workspace_root: Path,
    cluster: EventCluster,
    selector: dict[str, Any],
    selector_summary: dict[str, Any] | None,
    builder_diagnostics: list[str],
) -> dict[str, Any]:
    first_event = cluster.events[0]
    last_event = cluster.events[-1]
    context = event_context(last_event)
    return {
        "builderVersion": BUILDER_VERSION,
        "actionType": action_type,
        "taskChunk": {
            "taskId": task_chunk.get("taskId"),
            "sessionId": task_chunk.get("sessionId"),
            "boundaryReason": task_chunk.get("boundaryReason"),
            "taskChunkPath": repo_relative_or_abs(task_chunk_path, workspace_root),
            "rawEventLogPath": repo_relative_or_abs(raw_event_log_path, workspace_root),
        },
        "appContext": {
            "appName": context.get("appName"),
            "appBundleId": context.get("appBundleId"),
            "windowTitle": context.get("windowTitle"),
            "windowSignature": context.get("windowSignature"),
            "url": context.get("url"),
            "urlHost": context.get("urlHost"),
        },
        "eventWindow": {
            "eventCount": len(cluster.events),
            "startedAt": first_event.get("timestamp"),
            "endedAt": last_event.get("timestamp"),
            "durationMs": duration_millis(first_event.get("timestamp"), last_event.get("timestamp")),
        },
        "selectorSummary": {
            **(selector_summary or selector_chain_summary([selector])),
            "locatorType": selector.get("locatorType"),
            "selectorKind": selector.get("selectorKind"),
            "selectorStrategy": selector.get("selectorStrategy"),
            "selectorExtractorVersion": selector.get("selectorExtractorVersion"),
            "fallbackLocatorTypes": selector.get("fallbackLocatorTypes") or [],
            "fallbackSelectorStrategies": selector.get("fallbackSelectorStrategies") or [],
        },
        "builderDiagnostics": builder_diagnostics,
    }


def cluster_text(events: list[dict[str, Any]]) -> str:
    characters: list[str] = []
    for event in events:
        character = keyboard_char(event)
        if isinstance(character, str) and character:
            characters.append(character)
    return "".join(characters)


def shortcut_args(events: list[dict[str, Any]]) -> dict[str, Any]:
    signature = list(shortcut_signature(events[0]))
    keys = signature or ["unknown"]
    return {
        "keys": keys,
        "repeat": len(events),
    }


def click_args(event: dict[str, Any]) -> dict[str, Any]:
    mapping = {
        "leftClick": "left",
        "rightClick": "right",
        "doubleClick": "double",
    }
    return {"button": mapping.get(event.get("action"), "left")}


def choose_cluster_selectors(cluster: EventCluster) -> list[dict[str, Any]]:
    event = cluster.events[-1]
    selectors = build_accessibility_selector_chain(event)
    if selectors:
        if cluster.kind == "click":
            return selectors
        non_absolute = [
            selector for selector in selectors if selector.get("selectorStrategy") != "absolute_coordinate"
        ]
        if non_absolute:
            return non_absolute

    context = event_context(event)
    return [window_context_selector(context)]


def build_cluster_action(
    *,
    action_id: str,
    step_index: int,
    task_chunk: dict[str, Any],
    task_chunk_path: Path,
    raw_event_log_path: Path,
    cluster: EventCluster,
    workspace_root: Path,
) -> ActionBuildBundle:
    selectors = choose_cluster_selectors(cluster)
    if not selectors:
        selectors = [{"locatorType": "unknown", "selectorKind": "unknown", "source": "sem101-builder"}]
    chain_summary = selector_chain_summary(selectors)
    primary_selector = dict(selectors[0])
    if primary_selector.get("confidence") is None:
        primary_selector["confidence"] = selector_strategy_confidence(
            str(primary_selector.get("selectorStrategy") or "")
        )
    selectors[0] = dict(primary_selector)
    for selector in selectors[1:]:
        if selector.get("confidence") is None:
            selector["confidence"] = selector_strategy_confidence(str(selector.get("selectorStrategy") or ""))

    first_event = cluster.events[0]
    last_event = cluster.events[-1]
    context = event_context(last_event)
    created_at = str(first_event.get("timestamp") or "")
    updated_at = str(last_event.get("timestamp") or "")
    source_event_ids = [value for value in [event_id(event) for event in cluster.events] if value]

    action_type = cluster.kind
    args: dict[str, Any]
    if action_type == "click":
        args = click_args(last_event)
    elif action_type == "type":
        args = {"text": cluster_text(cluster.events)}
    else:
        args = shortcut_args(cluster.events)

    builder_diagnostics = list(cluster.diagnostics)
    if primary_selector.get("selectorStrategy") == "bounds_norm":
        builder_diagnostics.append("selector-fell-back-to-bounds-norm")
    elif primary_selector.get("selectorStrategy") == "absolute_coordinate":
        builder_diagnostics.append("selector-fell-back-to-absolute-coordinate")
    elif primary_selector.get("locatorType") == "windowContext":
        builder_diagnostics.append("selector-fell-back-to-window-context")

    action = SemanticActionRecord(
        action_id=action_id,
        schema_version=SCHEMA_VERSION,
        session_id=str(task_chunk.get("sessionId") or ""),
        task_id=task_chunk.get("taskId"),
        turn_id=None,
        trace_id=f"trace-semantic-builder-{task_chunk.get('taskId')}-{step_index:03d}",
        step_id=f"step-{step_index:03d}",
        step_index=step_index,
        action_type=action_type,
        selector=primary_selector,
        args=args,
        context=action_context_payload(
            action_type=action_type,
            task_chunk=task_chunk,
            raw_event_log_path=raw_event_log_path,
            task_chunk_path=task_chunk_path,
            workspace_root=workspace_root,
            cluster=cluster,
            selector=primary_selector,
            selector_summary=chain_summary,
            builder_diagnostics=builder_diagnostics,
        ),
        confidence=float(primary_selector.get("confidence") or 0.0),
        source_event_ids=source_event_ids,
        source_frame_ids=[],
        source_path=repo_relative_or_abs(task_chunk_path, workspace_root),
        preferred_locator_type=primary_selector.get("locatorType"),
        manual_review_required=selector_manual_review_required(primary_selector)
        or primary_selector.get("locatorType") == "unknown",
        legacy_coordinate=event_pointer(last_event) if action_type == "click" else None,
        created_at=created_at,
        updated_at=updated_at,
    )
    return ActionBuildBundle(
        action=action,
        targets=build_target_records(action_id, selectors, created_at),
        assertions=build_assertions(action_id, primary_selector, context, created_at),
        execution_logs=[],
        diagnostics=builder_diagnostics,
    )


def build_transition_action(
    *,
    action_id: str,
    step_index: int,
    task_chunk: dict[str, Any],
    task_chunk_path: Path,
    raw_event_log_path: Path,
    previous_event: dict[str, Any],
    current_event: dict[str, Any],
    workspace_root: Path,
) -> ActionBuildBundle | None:
    previous_context = event_context(previous_event)
    current_context = event_context(current_event)

    if previous_context.get("appBundleId") != current_context.get("appBundleId"):
        action_type = "switch_app"
        selector = app_context_selector(current_context)
        diagnostics = ["context-transition-app-bundle-changed"]
        args = {
            "fromAppBundleId": previous_context.get("appBundleId"),
            "toAppBundleId": current_context.get("appBundleId"),
            "fromAppName": previous_context.get("appName"),
            "toAppName": current_context.get("appName"),
        }
    elif (
        previous_context.get("windowTitle") != current_context.get("windowTitle")
        or (
            isinstance(previous_context.get("windowSignature"), dict)
            and isinstance(current_context.get("windowSignature"), dict)
            and previous_context["windowSignature"].get("signature")
            != current_context["windowSignature"].get("signature")
        )
    ):
        action_type = "focus_window"
        selector = window_context_selector(current_context)
        diagnostics = ["context-transition-window-changed"]
        args = {
            "fromWindowTitle": previous_context.get("windowTitle"),
            "toWindowTitle": current_context.get("windowTitle"),
            "fromWindowSignature": previous_context.get("windowSignature"),
            "toWindowSignature": current_context.get("windowSignature"),
        }
    else:
        return None

    if selector.get("confidence") is None:
        selector["confidence"] = selector_strategy_confidence(str(selector.get("selectorStrategy") or ""))
    created_at = str(current_event.get("timestamp") or previous_event.get("timestamp") or "")
    source_event_ids = [value for value in [event_id(previous_event), event_id(current_event)] if value]
    cluster = EventCluster(kind=action_type, events=[current_event], diagnostics=diagnostics)

    action = SemanticActionRecord(
        action_id=action_id,
        schema_version=SCHEMA_VERSION,
        session_id=str(task_chunk.get("sessionId") or ""),
        task_id=task_chunk.get("taskId"),
        turn_id=None,
        trace_id=f"trace-semantic-builder-{task_chunk.get('taskId')}-{step_index:03d}",
        step_id=f"step-{step_index:03d}",
        step_index=step_index,
        action_type=action_type,
        selector=selector,
        args=args,
        context=action_context_payload(
            action_type=action_type,
            task_chunk=task_chunk,
            raw_event_log_path=raw_event_log_path,
            task_chunk_path=task_chunk_path,
            workspace_root=workspace_root,
            cluster=cluster,
            selector=selector,
            selector_summary=selector_chain_summary([selector]),
            builder_diagnostics=diagnostics,
        ),
        confidence=float(selector.get("confidence") or 0.0),
        source_event_ids=source_event_ids,
        source_frame_ids=[],
        source_path=repo_relative_or_abs(task_chunk_path, workspace_root),
        preferred_locator_type=selector.get("locatorType"),
        manual_review_required=False,
        legacy_coordinate=None,
        created_at=created_at,
        updated_at=created_at,
    )
    return ActionBuildBundle(
        action=action,
        targets=build_target_records(action_id, [selector], created_at),
        assertions=build_assertions(action_id, selector, current_context, created_at),
        execution_logs=[],
        diagnostics=diagnostics,
    )


def build_actions_for_task_chunk(
    *,
    task_chunk: dict[str, Any],
    task_chunk_path: Path,
    raw_event_log_path: Path,
    events: list[dict[str, Any]],
    workspace_root: Path,
    config: ActionBuilderConfig | None = None,
) -> tuple[list[ActionBuildBundle], dict[str, Any]]:
    if config is None:
        config = ActionBuilderConfig()

    bundles: list[ActionBuildBundle] = []
    skipped_events: list[str] = []
    cluster: EventCluster | None = None
    action_index = 0
    task_id = str(task_chunk.get("taskId") or task_chunk.get("sessionId") or "task")

    def next_action_ref() -> tuple[str, int]:
        nonlocal action_index
        action_index += 1
        return f"semantic-action-{task_id}-{action_index:03d}", action_index

    def flush_cluster() -> None:
        nonlocal cluster
        if cluster is None or not cluster.events:
            cluster = None
            return
        action_id, step_index = next_action_ref()
        bundle = build_cluster_action(
            action_id=action_id,
            step_index=step_index,
            task_chunk=task_chunk,
            task_chunk_path=task_chunk_path,
            raw_event_log_path=raw_event_log_path,
            cluster=cluster,
            workspace_root=workspace_root,
        )
        bundles.append(bundle)
        cluster = None

    previous_event: dict[str, Any] | None = None
    for event in events:
        kind = event_kind(event)
        if kind is None:
            raw_event_id = event_id(event)
            skipped_events.append(raw_event_id or "unknown")
            continue

        if previous_event is not None and not same_context(previous_event, event):
            flush_cluster()
            action_id, step_index = next_action_ref()
            transition_bundle = build_transition_action(
                action_id=action_id,
                step_index=step_index,
                task_chunk=task_chunk,
                task_chunk_path=task_chunk_path,
                raw_event_log_path=raw_event_log_path,
                previous_event=previous_event,
                current_event=event,
                workspace_root=workspace_root,
            )
            if transition_bundle is not None:
                bundles.append(transition_bundle)

        if cluster is None:
            cluster = EventCluster(kind=kind, events=[event], diagnostics=[])
        elif should_merge(cluster, event, config):
            cluster.events.append(event)
            if kind == "type":
                cluster.diagnostics.append("merged-nearby-keydown-events-into-type")
            elif kind == "shortcut":
                cluster.diagnostics.append("merged-repeated-shortcut-events")
        else:
            flush_cluster()
            cluster = EventCluster(kind=kind, events=[event], diagnostics=[])

        previous_event = event

    flush_cluster()

    source_event_ids = {event_id(event) for event in events if event_id(event)}
    semanticized_event_ids = {
        source_event_id
        for bundle in bundles
        for source_event_id in bundle.action.source_event_ids
        if source_event_id in source_event_ids
    }
    diagnostics_count = sum(len(bundle.diagnostics) for bundle in bundles)
    summary = {
        "taskId": task_chunk.get("taskId"),
        "sessionId": task_chunk.get("sessionId"),
        "inputEventCount": len(events),
        "builtActionCount": len(bundles),
        "semanticizedEventCount": len(semanticized_event_ids),
        "semanticizedEventRatio": (len(semanticized_event_ids) / len(source_event_ids)) if source_event_ids else 0.0,
        "manualReviewRequiredCount": sum(1 for bundle in bundles if bundle.action.manual_review_required),
        "diagnosticCount": diagnostics_count,
        "skippedEventIds": skipped_events,
    }
    return bundles, summary
