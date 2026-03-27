from __future__ import annotations

from pathlib import Path
import sys
import unittest


REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "scripts/learning"))

from semantic_action_builder import build_actions_for_task_chunk  # noqa: E402


def raw_event(
    *,
    event_id: str,
    timestamp: str,
    action: str,
    app_bundle_id: str,
    app_name: str,
    window_title: str | None,
    pointer: tuple[int, int] = (0, 0),
    key: str | None = None,
    key_code: int | None = None,
    focused_element: dict | None = None,
) -> dict:
    payload = {
        "schemaVersion": "capture.raw.v0",
        "eventId": event_id,
        "sessionId": "session-001",
        "timestamp": timestamp,
        "source": "mouse" if action in {"leftClick", "rightClick", "doubleClick"} else "keyboard",
        "action": action,
        "pointer": {
            "x": pointer[0],
            "y": pointer[1],
            "coordinateSpace": "screen",
        },
        "contextSnapshot": {
            "appBundleId": app_bundle_id,
            "appName": app_name,
            "windowTitle": window_title,
            "isFrontmost": True,
        },
        "modifiers": [],
    }
    if focused_element is not None:
        payload["contextSnapshot"]["focusedElement"] = focused_element
    if action == "keyDown":
        payload["keyboard"] = {
            "characters": key,
            "charactersIgnoringModifiers": key,
            "isRepeat": False,
            "keyCode": key_code if key_code is not None else 0,
        }
    return payload


class SemanticActionBuilderTests(unittest.TestCase):
    def test_builder_groups_type_shortcut_and_context_transitions(self):
        task_chunk = {
            "taskId": "task-001",
            "sessionId": "session-001",
            "boundaryReason": "sessionEnd",
            "eventIds": ["event-001", "event-002", "event-003", "event-004", "event-005", "event-006", "event-007"],
        }
        focused_button = {
            "role": "AXButton",
            "subrole": None,
            "title": "Search",
            "identifier": "search-button",
            "descriptionText": "Search",
            "helpText": "",
            "boundingRect": {"x": 200, "y": 300, "width": 120, "height": 40, "coordinateSpace": "screen"},
            "valueRedacted": False,
        }
        focused_field = {
            "role": "AXTextField",
            "subrole": None,
            "title": "Address",
            "identifier": "address-bar",
            "descriptionText": "Address bar",
            "helpText": "",
            "boundingRect": {"x": 150, "y": 80, "width": 640, "height": 32, "coordinateSpace": "screen"},
            "valueRedacted": False,
        }
        events = [
            raw_event(
                event_id="event-001",
                timestamp="2026-04-06T09:00:00Z",
                action="leftClick",
                app_bundle_id="com.apple.dt.Xcode",
                app_name="Xcode",
                window_title="Package.swift",
                pointer=(24, 24),
            ),
            raw_event(
                event_id="event-002",
                timestamp="2026-04-06T09:00:01Z",
                action="leftClick",
                app_bundle_id="com.apple.Safari",
                app_name="Safari",
                window_title="Start Page",
                pointer=(220, 320),
                focused_element=focused_button,
            ),
            raw_event(
                event_id="event-003",
                timestamp="2026-04-06T09:00:02Z",
                action="keyDown",
                app_bundle_id="com.apple.Safari",
                app_name="Safari",
                window_title="Start Page",
                key="h",
                key_code=4,
                pointer=(400, 90),
                focused_element=focused_field,
            ),
            raw_event(
                event_id="event-004",
                timestamp="2026-04-06T09:00:02.200Z",
                action="keyDown",
                app_bundle_id="com.apple.Safari",
                app_name="Safari",
                window_title="Start Page",
                key="i",
                key_code=34,
                pointer=(400, 90),
                focused_element=focused_field,
            ),
            raw_event(
                event_id="event-005",
                timestamp="2026-04-06T09:00:03Z",
                action="keyDown",
                app_bundle_id="com.apple.Safari",
                app_name="Safari",
                window_title="Start Page",
                key="\r",
                key_code=36,
                pointer=(400, 90),
                focused_element=focused_field,
            ),
            raw_event(
                event_id="event-006",
                timestamp="2026-04-06T09:00:04Z",
                action="leftClick",
                app_bundle_id="com.apple.Safari",
                app_name="Safari",
                window_title="Search Results",
                pointer=(520, 640),
                focused_element=focused_button,
            ),
            raw_event(
                event_id="event-007",
                timestamp="2026-04-06T09:00:04.400Z",
                action="keyDown",
                app_bundle_id="com.apple.Safari",
                app_name="Safari",
                window_title="Search Results",
                key="\r",
                key_code=36,
                pointer=(520, 640),
                focused_element=focused_button,
            ),
        ]

        bundles, summary = build_actions_for_task_chunk(
            task_chunk=task_chunk,
            task_chunk_path=REPO_ROOT / "data/task-chunks/fixture/task-001.json",
            raw_event_log_path=REPO_ROOT / "data/raw-events/fixture/session-001.jsonl",
            events=events,
            workspace_root=REPO_ROOT,
        )

        action_types = [bundle.action.action_type for bundle in bundles]
        self.assertEqual(
            action_types,
            ["click", "switch_app", "click", "type", "shortcut", "focus_window", "click", "shortcut"],
        )
        self.assertEqual(summary["semanticizedEventCount"], 7)
        self.assertGreaterEqual(summary["semanticizedEventRatio"], 1.0)

        first_click = bundles[0].action
        self.assertTrue(first_click.manual_review_required)
        self.assertEqual(first_click.preferred_locator_type, "coordinateFallback")

        switch_app = bundles[1].action
        self.assertEqual(switch_app.args["fromAppBundleId"], "com.apple.dt.Xcode")
        self.assertEqual(switch_app.args["toAppBundleId"], "com.apple.Safari")

        safari_click = bundles[2]
        self.assertEqual(safari_click.action.preferred_locator_type, "focusedElement")
        self.assertEqual(len(safari_click.targets), 2)
        self.assertEqual(safari_click.targets[0].locator_type, "focusedElement")
        self.assertEqual(safari_click.targets[1].locator_type, "coordinateFallback")

        type_action = bundles[3].action
        self.assertEqual(type_action.args["text"], "hi")
        self.assertEqual(type_action.source_event_ids, ["event-003", "event-004"])

        shortcut = bundles[4].action
        self.assertEqual(shortcut.args["keys"], ["return"])
        self.assertEqual(shortcut.args["repeat"], 1)

        focus_window = bundles[5].action
        self.assertEqual(focus_window.action_type, "focus_window")
        self.assertEqual(focus_window.args["toWindowTitle"], "Search Results")

    def test_builder_merges_repeated_shortcuts(self):
        task_chunk = {
            "taskId": "task-002",
            "sessionId": "session-001",
            "boundaryReason": "sessionEnd",
            "eventIds": ["event-001", "event-002"],
        }
        events = [
            raw_event(
                event_id="event-001",
                timestamp="2026-04-06T09:10:00Z",
                action="keyDown",
                app_bundle_id="com.apple.Safari",
                app_name="Safari",
                window_title="Results",
                key="\r",
                key_code=36,
            ),
            raw_event(
                event_id="event-002",
                timestamp="2026-04-06T09:10:00.400Z",
                action="keyDown",
                app_bundle_id="com.apple.Safari",
                app_name="Safari",
                window_title="Results",
                key="\r",
                key_code=36,
            ),
        ]

        bundles, _ = build_actions_for_task_chunk(
            task_chunk=task_chunk,
            task_chunk_path=REPO_ROOT / "data/task-chunks/fixture/task-002.json",
            raw_event_log_path=REPO_ROOT / "data/raw-events/fixture/session-001.jsonl",
            events=events,
            workspace_root=REPO_ROOT,
        )

        self.assertEqual(len(bundles), 1)
        self.assertEqual(bundles[0].action.action_type, "shortcut")
        self.assertEqual(bundles[0].action.args["repeat"], 2)
        self.assertIn("merged-repeated-shortcut-events", bundles[0].diagnostics)


if __name__ == "__main__":
    unittest.main()
