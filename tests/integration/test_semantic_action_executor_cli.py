from __future__ import annotations

import json
from pathlib import Path
import tempfile
import unittest

from tests.swift_cli_test_utils import extract_last_json_object, run_swift_target


REPO_ROOT = Path(__file__).resolve().parents[2]

import sys

sys.path.insert(0, str(REPO_ROOT / "scripts/learning"))

from semantic_action_store import (  # noqa: E402
    SemanticActionMigrationManager,
    SemanticActionRecord,
    SemanticActionRepository,
    SemanticActionTargetRecord,
)


class SemanticActionExecutorCLITests(unittest.TestCase):
    def test_cli_executes_dry_run_and_appends_action_execution_log(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            workspace_root = Path(tmpdir)
            db_path = workspace_root / "semantic-actions.sqlite"
            snapshot_path = workspace_root / "snapshot.json"

            manager = SemanticActionMigrationManager(db_path)
            manager.migrate_up()
            repository = SemanticActionRepository(db_path)
            repository.replace_action(
                SemanticActionRecord(
                    action_id="action-click-001",
                    session_id="session-001",
                    task_id="task-001",
                    trace_id="trace-001",
                    step_id="step-001",
                    action_type="click",
                    selector={
                        "locatorType": "roleAndTitle",
                        "appBundleId": "com.test.app",
                        "windowTitlePattern": "^Main$",
                        "elementRole": "AXButton",
                        "elementTitle": "Open",
                        "elementIdentifier": "open-button",
                        "confidence": 0.92,
                    },
                    args={"button": "left"},
                    context={},
                    confidence=0.92,
                    created_at="2026-03-27T13:20:00Z",
                    updated_at="2026-03-27T13:20:00Z",
                    preferred_locator_type="roleAndTitle",
                ),
                targets=[
                    SemanticActionTargetRecord(
                        target_id="action-click-001:target:01",
                        target_role="primary",
                        ordinal=1,
                        locator_type="roleAndTitle",
                        selector={
                            "locatorType": "roleAndTitle",
                            "appBundleId": "com.test.app",
                            "windowTitlePattern": "^Main$",
                            "elementRole": "AXButton",
                            "elementTitle": "Open",
                            "elementIdentifier": "open-button",
                            "confidence": 0.92,
                        },
                        created_at="2026-03-27T13:20:00Z",
                        is_preferred=True,
                    )
                ],
            )

            snapshot_path.write_text(
                json.dumps(
                    {
                        "capturedAt": "2026-03-27T13:21:00Z",
                        "appName": "TestApp",
                        "appBundleId": "com.test.app",
                        "windowTitle": "Main",
                        "windowId": "1",
                        "windowSignature": {
                            "signature": "window-signature-001",
                            "signatureVersion": "window-v1",
                            "normalizedTitle": "main",
                            "role": "AXWindow",
                            "subrole": "AXStandardWindow",
                            "sizeBucket": "12x8",
                        },
                        "focusedElement": {
                            "axPath": "AXWindow/AXButton[0]",
                            "role": "AXButton",
                            "title": "Open",
                            "identifier": "open-button",
                            "boundingRect": {
                                "x": 220,
                                "y": 140,
                                "width": 72,
                                "height": 28,
                                "coordinateSpace": "screen",
                            },
                        },
                        "visibleElements": [
                            {
                                "axPath": "AXWindow/AXButton[0]",
                                "role": "AXButton",
                                "title": "Open",
                                "identifier": "open-button",
                                "boundingRect": {
                                    "x": 220,
                                    "y": 140,
                                    "width": 72,
                                    "height": 28,
                                    "coordinateSpace": "screen",
                                },
                            }
                        ],
                        "screenshotAnchors": [],
                        "captureDiagnostics": [],
                    },
                    ensure_ascii=False,
                    indent=2,
                )
                + "\n",
                encoding="utf-8",
            )

            result = run_swift_target(
                "OpenStaffReplayVerifyCLI",
                [
                    "--semantic-action-db",
                    str(db_path),
                    "--action-id",
                    "action-click-001",
                    "--snapshot",
                    str(snapshot_path),
                    "--dry-run",
                    "--json",
                ],
            )

            self.assertEqual(result.returncode, 0, msg=result.stderr or result.stdout)
            payload = extract_last_json_object(result.stdout)
            self.assertEqual(payload["status"], "succeeded")
            self.assertEqual(payload["matchedLocatorType"], "roleAndTitle")
            self.assertEqual(payload["selectorHitPath"], ["roleAndTitle"])
            self.assertTrue(payload["dryRun"])

            action = repository.get_action("action-click-001")
            self.assertIsNotNone(action)
            assert action is not None
            self.assertEqual(len(action["execution_logs"]), 1)
            self.assertEqual(
                action["execution_logs"][0]["status"],
                "STATUS_SEMANTIC_ACTION_DRY_RUN_SUCCEEDED",
            )
            self.assertEqual(action["execution_logs"][0]["selector_hit_path_json"], ["roleAndTitle"])
            self.assertGreaterEqual(action["execution_logs"][0]["duration_ms"], 0)

    def test_cli_blocks_context_mismatch_and_records_structured_reason(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            workspace_root = Path(tmpdir)
            db_path = workspace_root / "semantic-actions.sqlite"
            snapshot_path = workspace_root / "snapshot.json"

            manager = SemanticActionMigrationManager(db_path)
            manager.migrate_up()
            repository = SemanticActionRepository(db_path)
            repository.replace_action(
                SemanticActionRecord(
                    action_id="action-click-ctx-001",
                    session_id="session-001",
                    task_id="task-001",
                    trace_id="trace-ctx-001",
                    step_id="step-ctx-001",
                    action_type="click",
                    selector={
                        "locatorType": "roleAndTitle",
                        "appBundleId": "com.test.app",
                        "windowTitlePattern": "^Main$",
                        "elementRole": "AXButton",
                        "elementTitle": "Open",
                        "elementIdentifier": "open-button",
                    },
                    args={"button": "left"},
                    context={},
                    confidence=0.91,
                    created_at="2026-03-27T13:30:00Z",
                    updated_at="2026-03-27T13:30:00Z",
                    preferred_locator_type="roleAndTitle",
                ),
                targets=[
                    SemanticActionTargetRecord(
                        target_id="action-click-ctx-001:target:01",
                        target_role="primary",
                        ordinal=1,
                        locator_type="roleAndTitle",
                        selector={
                            "locatorType": "roleAndTitle",
                            "appBundleId": "com.test.app",
                            "windowTitlePattern": "^Main$",
                            "elementRole": "AXButton",
                            "elementTitle": "Open",
                            "elementIdentifier": "open-button",
                        },
                        created_at="2026-03-27T13:30:00Z",
                        is_preferred=True,
                    )
                ],
            )

            snapshot_path.write_text(
                json.dumps(
                    {
                        "capturedAt": "2026-03-27T13:31:00Z",
                        "appName": "OtherApp",
                        "appBundleId": "com.other.app",
                        "windowTitle": "Main",
                        "windowId": "1",
                        "windowSignature": {
                            "signature": "window-signature-001",
                            "signatureVersion": "window-v1",
                            "normalizedTitle": "main",
                            "role": "AXWindow",
                            "subrole": "AXStandardWindow",
                            "sizeBucket": "12x8",
                        },
                        "visibleElements": [],
                        "screenshotAnchors": [],
                        "captureDiagnostics": [],
                    },
                    ensure_ascii=False,
                    indent=2,
                )
                + "\n",
                encoding="utf-8",
            )

            result = run_swift_target(
                "OpenStaffReplayVerifyCLI",
                [
                    "--semantic-action-db",
                    str(db_path),
                    "--action-id",
                    "action-click-ctx-001",
                    "--snapshot",
                    str(snapshot_path),
                    "--dry-run",
                    "--json",
                ],
            )

            self.assertEqual(result.returncode, 2, msg=result.stderr or result.stdout)
            payload = extract_last_json_object(result.stdout)
            self.assertEqual(payload["status"], "blocked")
            self.assertEqual(payload["errorCode"], "SEM202-CONTEXT-MISMATCH")
            self.assertEqual(payload["contextGuard"]["status"], "blocked")
            self.assertEqual(
                payload["contextGuard"]["mismatches"][0]["dimension"],
                "requiredFrontmostApp",
            )
            self.assertEqual(payload["contextGuard"]["actual"]["appBundleId"], "com.other.app")

            action = repository.get_action("action-click-ctx-001")
            self.assertIsNotNone(action)
            assert action is not None
            self.assertEqual(len(action["execution_logs"]), 1)
            self.assertEqual(
                action["execution_logs"][0]["status"],
                "STATUS_SEMANTIC_ACTION_DRY_RUN_BLOCKED",
            )
            self.assertEqual(
                action["execution_logs"][0]["result_json"]["contextGuard"]["mismatches"][0]["dimension"],
                "requiredFrontmostApp",
            )


if __name__ == "__main__":
    unittest.main()
