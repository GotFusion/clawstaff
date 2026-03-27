import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "scripts/learning"))

from semantic_action_store import SemanticActionRepository  # noqa: E402


SCRIPT = REPO_ROOT / "scripts/learning/build_semantic_actions.py"


class SemanticActionBuilderIntegrationTests(unittest.TestCase):
    def run_cmd(self, args):
        return subprocess.run(
            args,
            cwd=REPO_ROOT,
            capture_output=True,
            text=True,
            check=False,
        )

    def test_cli_builds_semantic_actions_from_task_chunk_and_raw_log(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            workspace_root = Path(tmpdir)
            raw_events_root = workspace_root / "data/raw-events/2026-04-06"
            task_chunks_root = workspace_root / "data/task-chunks/2026-04-06"
            db_path = workspace_root / "data/semantic-actions/semantic-actions.sqlite"

            raw_events_root.mkdir(parents=True, exist_ok=True)
            task_chunks_root.mkdir(parents=True, exist_ok=True)

            raw_log = raw_events_root / "session-001.jsonl"
            raw_log.write_text(
                "\n".join(
                    [
                        json.dumps(
                            {
                                "schemaVersion": "capture.raw.v0",
                                "eventId": "event-001",
                                "sessionId": "session-001",
                                "timestamp": "2026-04-06T09:00:00Z",
                                "source": "mouse",
                                "action": "leftClick",
                                "pointer": {"x": 24, "y": 24, "coordinateSpace": "screen"},
                                "contextSnapshot": {
                                    "appBundleId": "com.apple.dt.Xcode",
                                    "appName": "Xcode",
                                    "windowTitle": "Package.swift",
                                    "isFrontmost": True,
                                },
                                "modifiers": [],
                            },
                            ensure_ascii=False,
                        ),
                        json.dumps(
                            {
                                "schemaVersion": "capture.raw.v0",
                                "eventId": "event-002",
                                "sessionId": "session-001",
                                "timestamp": "2026-04-06T09:00:01Z",
                                "source": "mouse",
                                "action": "leftClick",
                                "pointer": {"x": 220, "y": 320, "coordinateSpace": "screen"},
                                "contextSnapshot": {
                                    "appBundleId": "com.apple.Safari",
                                    "appName": "Safari",
                                    "windowTitle": "Start Page",
                                    "isFrontmost": True,
                                    "windowSignature": {
                                        "signature": "window-start-page",
                                        "signatureVersion": "window-v1",
                                        "role": "AXWindow",
                                        "subrole": "AXStandardWindow",
                                    },
                                    "url": "https://www.google.com/",
                                    "focusedElement": {
                                        "role": "AXButton",
                                        "title": "Search",
                                        "identifier": "search-button",
                                        "boundingRect": {
                                            "x": 200,
                                            "y": 300,
                                            "width": 120,
                                            "height": 40,
                                            "coordinateSpace": "screen",
                                        },
                                        "valueRedacted": False,
                                    },
                                },
                                "modifiers": [],
                            },
                            ensure_ascii=False,
                        ),
                        json.dumps(
                            {
                                "schemaVersion": "capture.raw.v0",
                                "eventId": "event-003",
                                "sessionId": "session-001",
                                "timestamp": "2026-04-06T09:00:02Z",
                                "source": "keyboard",
                                "action": "keyDown",
                                "pointer": {"x": 400, "y": 90, "coordinateSpace": "screen"},
                                "contextSnapshot": {
                                    "appBundleId": "com.apple.Safari",
                                    "appName": "Safari",
                                    "windowTitle": "Start Page",
                                    "isFrontmost": True,
                                    "windowSignature": {
                                        "signature": "window-start-page",
                                        "signatureVersion": "window-v1",
                                        "role": "AXWindow",
                                        "subrole": "AXStandardWindow",
                                    },
                                    "url": "https://www.google.com/",
                                    "focusedElement": {
                                        "role": "AXTextField",
                                        "title": "Address",
                                        "identifier": "address-bar",
                                        "boundingRect": {
                                            "x": 150,
                                            "y": 80,
                                            "width": 640,
                                            "height": 32,
                                            "coordinateSpace": "screen",
                                        },
                                        "valueRedacted": False,
                                    },
                                },
                                "keyboard": {
                                    "characters": "h",
                                    "charactersIgnoringModifiers": "h",
                                    "isRepeat": False,
                                    "keyCode": 4,
                                },
                                "modifiers": [],
                            },
                            ensure_ascii=False,
                        ),
                        json.dumps(
                            {
                                "schemaVersion": "capture.raw.v0",
                                "eventId": "event-004",
                                "sessionId": "session-001",
                                "timestamp": "2026-04-06T09:00:02.250Z",
                                "source": "keyboard",
                                "action": "keyDown",
                                "pointer": {"x": 400, "y": 90, "coordinateSpace": "screen"},
                                "contextSnapshot": {
                                    "appBundleId": "com.apple.Safari",
                                    "appName": "Safari",
                                    "windowTitle": "Start Page",
                                    "isFrontmost": True,
                                    "windowSignature": {
                                        "signature": "window-start-page",
                                        "signatureVersion": "window-v1",
                                        "role": "AXWindow",
                                        "subrole": "AXStandardWindow",
                                    },
                                    "url": "https://www.google.com/",
                                    "focusedElement": {
                                        "role": "AXTextField",
                                        "title": "Address",
                                        "identifier": "address-bar",
                                        "boundingRect": {
                                            "x": 150,
                                            "y": 80,
                                            "width": 640,
                                            "height": 32,
                                            "coordinateSpace": "screen",
                                        },
                                        "valueRedacted": False,
                                    },
                                },
                                "keyboard": {
                                    "characters": "i",
                                    "charactersIgnoringModifiers": "i",
                                    "isRepeat": False,
                                    "keyCode": 34,
                                },
                                "modifiers": [],
                            },
                            ensure_ascii=False,
                        ),
                    ]
                )
                + "\n",
                encoding="utf-8",
            )

            task_chunk = task_chunks_root / "task-001.json"
            task_chunk.write_text(
                json.dumps(
                    {
                        "schemaVersion": "knowledge.task-chunk.v0",
                        "taskId": "task-001",
                        "sessionId": "session-001",
                        "boundaryReason": "sessionEnd",
                        "eventIds": ["event-001", "event-002", "event-003", "event-004"],
                        "startTimestamp": "2026-04-06T09:00:00Z",
                        "endTimestamp": "2026-04-06T09:00:02.250Z",
                    },
                    ensure_ascii=False,
                    indent=2,
                )
                + "\n",
                encoding="utf-8",
            )

            result = self.run_cmd(
                [
                    sys.executable,
                    str(SCRIPT),
                    "--workspace-root",
                    str(workspace_root),
                    "--raw-events-root",
                    str(workspace_root / "data/raw-events"),
                    "--task-chunks-root",
                    str(workspace_root / "data/task-chunks"),
                    "--db-path",
                    str(db_path),
                    "--json",
                ]
            )

            self.assertEqual(result.returncode, 0, msg=result.stderr or result.stdout)
            summary = json.loads(result.stdout)
            self.assertEqual(summary["processedChunkCount"], 1)
            self.assertEqual(summary["writtenActions"], 4)
            self.assertGreaterEqual(summary["semanticizedEventRatio"], 1.0)

            repository = SemanticActionRepository(db_path)
            actions = repository.list_actions(session_id="session-001")
            self.assertEqual([action["action_type"] for action in actions], ["click", "switch_app", "click", "type"])
            self.assertEqual(actions[-1]["args_json"]["text"], "hi")
            self.assertFalse(actions[-1]["manual_review_required"])
            self.assertEqual(actions[2]["selector_json"]["selectorStrategy"], "automation_id")
            self.assertEqual(
                [target["selector_json"]["selectorStrategy"] for target in actions[2]["targets"]],
                [
                    "automation_id",
                    "role_and_name",
                    "role_and_ancestry_path",
                    "bounds_norm",
                    "absolute_coordinate",
                ],
            )
            self.assertEqual(actions[2]["context_json"]["selectorSummary"]["candidateCount"], 5)

    def test_cli_reports_semanticized_ratio_above_threshold_for_fixture_corpus(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            workspace_root = Path(tmpdir)
            raw_events_root = workspace_root / "data/raw-events/2026-04-07"
            task_chunks_root = workspace_root / "data/task-chunks/2026-04-07"
            db_path = workspace_root / "data/semantic-actions/semantic-actions.sqlite"

            raw_events_root.mkdir(parents=True, exist_ok=True)
            task_chunks_root.mkdir(parents=True, exist_ok=True)

            raw_events_root.joinpath("session-002.jsonl").write_text(
                "\n".join(
                    [
                        json.dumps(
                            {
                                "schemaVersion": "capture.raw.v0",
                                "eventId": "event-101",
                                "sessionId": "session-002",
                                "timestamp": "2026-04-07T10:00:00Z",
                                "source": "mouse",
                                "action": "leftClick",
                                "pointer": {"x": 50, "y": 50, "coordinateSpace": "screen"},
                                "contextSnapshot": {
                                    "appBundleId": "com.apple.dt.Xcode",
                                    "appName": "Xcode",
                                    "windowTitle": "Editor",
                                    "isFrontmost": True,
                                },
                                "modifiers": [],
                            },
                            ensure_ascii=False,
                        ),
                        json.dumps(
                            {
                                "schemaVersion": "capture.raw.v0",
                                "eventId": "event-102",
                                "sessionId": "session-002",
                                "timestamp": "2026-04-07T10:00:01Z",
                                "source": "keyboard",
                                "action": "keyDown",
                                "pointer": {"x": 200, "y": 90, "coordinateSpace": "screen"},
                                "contextSnapshot": {
                                    "appBundleId": "com.apple.Safari",
                                    "appName": "Safari",
                                    "windowTitle": "Home",
                                    "isFrontmost": True,
                                },
                                "keyboard": {
                                    "characters": "o",
                                    "charactersIgnoringModifiers": "o",
                                    "isRepeat": False,
                                    "keyCode": 31,
                                },
                                "modifiers": [],
                            },
                            ensure_ascii=False,
                        ),
                        json.dumps(
                            {
                                "schemaVersion": "capture.raw.v0",
                                "eventId": "event-103",
                                "sessionId": "session-002",
                                "timestamp": "2026-04-07T10:00:01.200Z",
                                "source": "keyboard",
                                "action": "keyDown",
                                "pointer": {"x": 200, "y": 90, "coordinateSpace": "screen"},
                                "contextSnapshot": {
                                    "appBundleId": "com.apple.Safari",
                                    "appName": "Safari",
                                    "windowTitle": "Home",
                                    "isFrontmost": True,
                                },
                                "keyboard": {
                                    "characters": "k",
                                    "charactersIgnoringModifiers": "k",
                                    "isRepeat": False,
                                    "keyCode": 40,
                                },
                                "modifiers": [],
                            },
                            ensure_ascii=False,
                        ),
                        json.dumps(
                            {
                                "schemaVersion": "capture.raw.v0",
                                "eventId": "event-104",
                                "sessionId": "session-002",
                                "timestamp": "2026-04-07T10:00:02Z",
                                "source": "keyboard",
                                "action": "keyDown",
                                "pointer": {"x": 200, "y": 90, "coordinateSpace": "screen"},
                                "contextSnapshot": {
                                    "appBundleId": "com.apple.Safari",
                                    "appName": "Safari",
                                    "windowTitle": "Home",
                                    "isFrontmost": True,
                                },
                                "keyboard": {
                                    "characters": "\r",
                                    "charactersIgnoringModifiers": "\r",
                                    "isRepeat": False,
                                    "keyCode": 36,
                                },
                                "modifiers": [],
                            },
                            ensure_ascii=False,
                        ),
                        json.dumps(
                            {
                                "schemaVersion": "capture.raw.v0",
                                "eventId": "event-105",
                                "sessionId": "session-002",
                                "timestamp": "2026-04-07T10:00:03Z",
                                "source": "mouse",
                                "action": "mouseMoved",
                                "pointer": {"x": 220, "y": 120, "coordinateSpace": "screen"},
                                "contextSnapshot": {
                                    "appBundleId": "com.apple.Safari",
                                    "appName": "Safari",
                                    "windowTitle": "Home",
                                    "isFrontmost": True,
                                },
                                "modifiers": [],
                            },
                            ensure_ascii=False,
                        ),
                        json.dumps(
                            {
                                "schemaVersion": "capture.raw.v0",
                                "eventId": "event-106",
                                "sessionId": "session-002",
                                "timestamp": "2026-04-07T10:00:04Z",
                                "source": "mouse",
                                "action": "leftClick",
                                "pointer": {"x": 400, "y": 400, "coordinateSpace": "screen"},
                                "contextSnapshot": {
                                    "appBundleId": "com.apple.Safari",
                                    "appName": "Safari",
                                    "windowTitle": "Results",
                                    "isFrontmost": True,
                                },
                                "modifiers": [],
                            },
                            ensure_ascii=False,
                        ),
                    ]
                )
                + "\n",
                encoding="utf-8",
            )

            task_chunks_root.joinpath("task-002.json").write_text(
                json.dumps(
                    {
                        "schemaVersion": "knowledge.task-chunk.v0",
                        "taskId": "task-002",
                        "sessionId": "session-002",
                        "boundaryReason": "sessionEnd",
                        "eventIds": ["event-101", "event-102", "event-103", "event-104", "event-105", "event-106"],
                        "startTimestamp": "2026-04-07T10:00:00Z",
                        "endTimestamp": "2026-04-07T10:00:04Z",
                    },
                    ensure_ascii=False,
                    indent=2,
                )
                + "\n",
                encoding="utf-8",
            )

            result = self.run_cmd(
                [
                    sys.executable,
                    str(SCRIPT),
                    "--workspace-root",
                    str(workspace_root),
                    "--raw-events-root",
                    str(workspace_root / "data/raw-events"),
                    "--task-chunks-root",
                    str(workspace_root / "data/task-chunks"),
                    "--db-path",
                    str(db_path),
                    "--clean",
                    "--json",
                ]
            )

            self.assertEqual(result.returncode, 0, msg=result.stderr or result.stdout)
            summary = json.loads(result.stdout)
            self.assertGreater(summary["writtenActions"], 0)
            self.assertGreaterEqual(summary["semanticizedEventRatio"], 0.8)
            self.assertIn("click", summary["actionTypeCounts"])
            self.assertEqual(summary["missingEventCount"], 0)


if __name__ == "__main__":
    unittest.main()
