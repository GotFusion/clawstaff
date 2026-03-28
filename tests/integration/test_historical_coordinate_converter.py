import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "scripts/learning"))

from semantic_action_store import SemanticActionRepository  # noqa: E402


SCRIPT = REPO_ROOT / "scripts/learning/migrate_semantic_actions.py"
AUTO_CONVERTED = "SEM301-AUTO-CONVERTED-FROM-RAW-EVENTS"
NO_MATCH = "SEM301-NO-HISTORICAL-MATCH"


def raw_event(
    *,
    event_id: str,
    timestamp: str,
    action: str,
    app_bundle_id: str,
    app_name: str,
    window_title: str | None,
    pointer: tuple[int, int] = (0, 0),
    focused_element: dict | None = None,
    key: str | None = None,
    key_code: int | None = None,
    window_signature: dict | None = None,
    url: str | None = None,
) -> dict:
    payload = {
        "schemaVersion": "capture.raw.v0",
        "eventId": event_id,
        "sessionId": "session-history-001",
        "timestamp": timestamp,
        "source": "mouse" if action == "leftClick" else "keyboard",
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
    if window_signature is not None:
        payload["contextSnapshot"]["windowSignature"] = window_signature
    if url is not None:
        payload["contextSnapshot"]["url"] = url
    if action == "keyDown":
        payload["keyboard"] = {
            "characters": key,
            "charactersIgnoringModifiers": key,
            "isRepeat": False,
            "keyCode": key_code if key_code is not None else 0,
        }
    return payload


def coordinate_target(*, app_bundle_id: str, x: int, y: int) -> dict:
    return {
        "preferredLocatorType": "coordinateFallback",
        "candidateCount": 1,
        "semanticTargets": [
            {
                "locatorType": "coordinateFallback",
                "appBundleId": app_bundle_id,
                "boundingRect": {
                    "x": x,
                    "y": y,
                    "width": 1,
                    "height": 1,
                    "coordinateSpace": "screen",
                },
                "confidence": 0.2,
                "source": "legacy-coordinate",
            }
        ],
    }


def historical_turn(
    *,
    turn_id: str,
    step_index: int,
    action_summary: str,
    source_event_ids: list[str],
    raw_event_log_path: str,
    task_chunk_path: str,
    app_context: dict,
    coordinate: tuple[int, int],
) -> dict:
    return {
        "schemaVersion": "openstaff.learning.interaction-turn.v0",
        "turnId": turn_id,
        "traceId": f"trace-{turn_id}",
        "sessionId": "session-history-001",
        "taskId": "task-history-001",
        "stepId": f"step-{step_index:03d}",
        "mode": "teaching",
        "turnKind": "taskProgression",
        "stepIndex": step_index,
        "intentSummary": action_summary,
        "actionSummary": action_summary,
        "actionKind": "guiAction",
        "status": "captured",
        "learningState": "linked",
        "privacyTags": [],
        "riskLevel": "low",
        "appContext": app_context,
        "observationRef": {
            "rawEventLogPath": raw_event_log_path,
            "taskChunkPath": task_chunk_path,
            "eventIds": source_event_ids,
            "screenshotRefs": [],
            "axRefs": [],
            "ocrRefs": [],
        },
        "semanticTargetSetRef": coordinate_target(
            app_bundle_id=str(app_context.get("appBundleId") or ""),
            x=coordinate[0],
            y=coordinate[1],
        ),
        "stepReference": {
            "stepId": f"step-{step_index:03d}",
            "stepIndex": step_index,
            "instruction": action_summary,
            "sourceEventIds": source_event_ids,
        },
        "review": None,
        "sourceRefs": [],
        "buildDiagnostics": [],
        "startedAt": "2026-04-20T09:00:00Z",
        "endedAt": "2026-04-20T09:00:01Z",
    }


class HistoricalCoordinateConverterIntegrationTests(unittest.TestCase):
    def run_cmd(self, args):
        return subprocess.run(
            args,
            cwd=REPO_ROOT,
            capture_output=True,
            text=True,
            check=False,
        )

    def test_cli_converts_historical_coordinate_turns_to_semantic_actions(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            workspace_root = Path(tmpdir)
            raw_events_root = workspace_root / "data/raw-events/2026-04-20"
            task_chunks_root = workspace_root / "data/task-chunks/2026-04-20"
            turns_root = workspace_root / "data/learning/turns/2026-04-20/session-history-001"
            db_path = workspace_root / "data/semantic-actions/semantic-actions.sqlite"

            raw_events_root.mkdir(parents=True, exist_ok=True)
            task_chunks_root.mkdir(parents=True, exist_ok=True)
            turns_root.mkdir(parents=True, exist_ok=True)

            window_signature = {
                "signature": "window-history-main",
                "signatureVersion": "window-v1",
                "role": "AXWindow",
                "subrole": "AXStandardWindow",
            }
            search_button = {
                "role": "AXButton",
                "title": "Search",
                "identifier": "search-button",
                "descriptionText": "Search",
                "boundingRect": {
                    "x": 200,
                    "y": 300,
                    "width": 120,
                    "height": 40,
                    "coordinateSpace": "screen",
                },
                "valueRedacted": False,
            }
            address_bar = {
                "role": "AXTextField",
                "title": "Address",
                "identifier": "address-bar",
                "descriptionText": "Address bar",
                "boundingRect": {
                    "x": 150,
                    "y": 80,
                    "width": 640,
                    "height": 32,
                    "coordinateSpace": "screen",
                },
                "valueRedacted": False,
            }
            submit_button = {
                "role": "AXButton",
                "title": "提交",
                "identifier": "submit-button",
                "descriptionText": "提交",
                "boundingRect": {
                    "x": 520,
                    "y": 640,
                    "width": 96,
                    "height": 40,
                    "coordinateSpace": "screen",
                },
                "valueRedacted": False,
            }

            raw_log = raw_events_root / "session-history-001.jsonl"
            raw_log.write_text(
                "\n".join(
                    [
                        json.dumps(
                            raw_event(
                                event_id="event-001",
                                timestamp="2026-04-20T09:00:00Z",
                                action="leftClick",
                                app_bundle_id="com.apple.Safari",
                                app_name="Safari",
                                window_title="Start Page",
                                pointer=(220, 320),
                                focused_element=search_button,
                                window_signature=window_signature,
                                url="https://www.google.com/",
                            ),
                            ensure_ascii=False,
                        ),
                        json.dumps(
                            raw_event(
                                event_id="event-002",
                                timestamp="2026-04-20T09:00:01Z",
                                action="keyDown",
                                app_bundle_id="com.apple.Safari",
                                app_name="Safari",
                                window_title="Start Page",
                                pointer=(400, 90),
                                focused_element=address_bar,
                                key="h",
                                key_code=4,
                                window_signature=window_signature,
                                url="https://www.google.com/",
                            ),
                            ensure_ascii=False,
                        ),
                        json.dumps(
                            raw_event(
                                event_id="event-003",
                                timestamp="2026-04-20T09:00:01.200Z",
                                action="keyDown",
                                app_bundle_id="com.apple.Safari",
                                app_name="Safari",
                                window_title="Start Page",
                                pointer=(400, 90),
                                focused_element=address_bar,
                                key="i",
                                key_code=34,
                                window_signature=window_signature,
                                url="https://www.google.com/",
                            ),
                            ensure_ascii=False,
                        ),
                        json.dumps(
                            raw_event(
                                event_id="event-004",
                                timestamp="2026-04-20T09:00:02Z",
                                action="leftClick",
                                app_bundle_id="com.apple.Safari",
                                app_name="Safari",
                                window_title="Start Page",
                                pointer=(520, 640),
                                focused_element=submit_button,
                                window_signature=window_signature,
                                url="https://www.google.com/search?q=hi",
                            ),
                            ensure_ascii=False,
                        ),
                    ]
                )
                + "\n",
                encoding="utf-8",
            )

            task_chunk = task_chunks_root / "task-history-001.json"
            task_chunk.write_text(
                json.dumps(
                    {
                        "schemaVersion": "knowledge.task-chunk.v0",
                        "taskId": "task-history-001",
                        "sessionId": "session-history-001",
                        "boundaryReason": "sessionEnd",
                        "eventIds": ["event-001", "event-002", "event-003", "event-004"],
                        "startTimestamp": "2026-04-20T09:00:00Z",
                        "endTimestamp": "2026-04-20T09:00:02Z",
                    },
                    ensure_ascii=False,
                    indent=2,
                )
                + "\n",
                encoding="utf-8",
            )

            safari_app_context = {
                "appName": "Safari",
                "appBundleId": "com.apple.Safari",
                "windowTitle": "Start Page",
                "windowSignature": "window-history-main",
            }

            turns = [
                historical_turn(
                    turn_id="turn-001",
                    step_index=1,
                    action_summary="点击 Search 按钮。",
                    source_event_ids=["event-001"],
                    raw_event_log_path="data/raw-events/2026-04-20/session-history-001.jsonl",
                    task_chunk_path="data/task-chunks/2026-04-20/task-history-001.json",
                    app_context=safari_app_context,
                    coordinate=(220, 320),
                ),
                historical_turn(
                    turn_id="turn-002",
                    step_index=2,
                    action_summary='输入 "hi"。',
                    source_event_ids=["event-002", "event-003"],
                    raw_event_log_path="data/raw-events/2026-04-20/session-history-001.jsonl",
                    task_chunk_path="data/task-chunks/2026-04-20/task-history-001.json",
                    app_context=safari_app_context,
                    coordinate=(400, 90),
                ),
                historical_turn(
                    turn_id="turn-003",
                    step_index=3,
                    action_summary="点击提交按钮。",
                    source_event_ids=["event-004"],
                    raw_event_log_path="data/raw-events/2026-04-20/session-history-001.jsonl",
                    task_chunk_path="data/task-chunks/2026-04-20/task-history-001.json",
                    app_context=safari_app_context,
                    coordinate=(520, 640),
                ),
                historical_turn(
                    turn_id="turn-004",
                    step_index=4,
                    action_summary="点击缺失按钮。",
                    source_event_ids=["event-999"],
                    raw_event_log_path="data/raw-events/2026-04-20/session-history-001.jsonl",
                    task_chunk_path="data/task-chunks/2026-04-20/task-history-001.json",
                    app_context=safari_app_context,
                    coordinate=(999, 999),
                ),
            ]

            for turn in turns:
                (turns_root / f"{turn['turnId']}.json").write_text(
                    json.dumps(turn, ensure_ascii=False, indent=2) + "\n",
                    encoding="utf-8",
                )

            result = self.run_cmd(
                [
                    sys.executable,
                    str(SCRIPT),
                    "--workspace-root",
                    str(workspace_root),
                    "--turns-root",
                    str(workspace_root / "data/learning/turns"),
                    "--db-path",
                    str(db_path),
                    "--clean",
                    "--json",
                ]
            )

            self.assertEqual(result.returncode, 0, msg=result.stderr or result.stdout)
            summary = json.loads(result.stdout)
            backfill = summary["backfill"]

            self.assertEqual(backfill["writtenActions"], 4)
            self.assertEqual(backfill["historicalCoordinateCandidateCount"], 4)
            self.assertEqual(backfill["historicalAutoConvertedCount"], 3)
            self.assertAlmostEqual(backfill["historicalAutoConversionRate"], 0.75)
            self.assertEqual(backfill["historicalConversionReasonCounts"][AUTO_CONVERTED], 3)
            self.assertEqual(backfill["historicalConversionReasonCounts"][NO_MATCH], 1)

            repository = SemanticActionRepository(db_path)

            first_click = repository.get_action("semantic-action-turn-001")
            self.assertIsNotNone(first_click)
            self.assertFalse(first_click["manual_review_required"])
            self.assertNotEqual(first_click["selector_json"]["locatorType"], "coordinateFallback")
            self.assertNotEqual(first_click["selector_json"]["selectorStrategy"], "absolute_coordinate")
            self.assertEqual(
                first_click["context_json"]["historicalConversion"]["reasonCode"],
                AUTO_CONVERTED,
            )

            typed = repository.get_action("semantic-action-turn-002")
            self.assertIsNotNone(typed)
            self.assertEqual(typed["action_type"], "type")
            self.assertEqual(typed["args_json"]["text"], "hi")
            self.assertFalse(typed["manual_review_required"])
            self.assertNotEqual(typed["selector_json"]["locatorType"], "coordinateFallback")

            unmatched = repository.get_action("semantic-action-turn-004")
            self.assertIsNotNone(unmatched)
            self.assertTrue(unmatched["manual_review_required"])
            self.assertEqual(
                unmatched["context_json"]["historicalConversion"]["reasonCode"],
                NO_MATCH,
            )
            self.assertEqual(unmatched["selector_json"]["locatorType"], "coordinateFallback")


if __name__ == "__main__":
    unittest.main()
