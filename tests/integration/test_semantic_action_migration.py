import json
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile
import unittest


REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "scripts/learning"))

from semantic_action_store import (  # noqa: E402
    SemanticActionAssertionRecord,
    SemanticActionExecutionLogRecord,
    SemanticActionMigrationManager,
    SemanticActionRecord,
    SemanticActionRepository,
    SemanticActionTargetRecord,
)


SCRIPT = REPO_ROOT / "scripts/learning/migrate_semantic_actions.py"


class SemanticActionStoreIntegrationTests(unittest.TestCase):
    def test_repository_supports_up_insert_query_and_down(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            db_path = Path(tmpdir) / "semantic-actions.sqlite"
            manager = SemanticActionMigrationManager(db_path)
            repository = SemanticActionRepository(db_path)

            self.assertEqual(manager.migrate_up(), [1])

            repository.replace_action(
                SemanticActionRecord(
                    action_id="semantic-action-turn-001",
                    session_id="session-001",
                    task_id="task-001",
                    turn_id="turn-001",
                    trace_id="trace-001",
                    step_id="step-001",
                    step_index=1,
                    action_type="click",
                    selector={"locatorType": "roleAndTitle", "elementRole": "AXButton", "elementTitle": "提交"},
                    args={"instruction": "点击提交按钮"},
                    context={"mode": "teaching"},
                    confidence=0.88,
                    source_event_ids=["event-001"],
                    source_frame_ids=["frame-001"],
                    source_path="data/skills/pending/sample/openstaff-skill.json",
                    preferred_locator_type="roleAndTitle",
                    manual_review_required=False,
                    legacy_coordinate={"x": 12, "y": 34, "coordinateSpace": "screen"},
                    created_at="2026-03-26T10:00:00Z",
                    updated_at="2026-03-26T10:00:01Z",
                ),
                targets=[
                    SemanticActionTargetRecord(
                        target_id="semantic-action-turn-001:target:01",
                        target_role="primary",
                        ordinal=1,
                        locator_type="roleAndTitle",
                        selector={"locatorType": "roleAndTitle", "elementRole": "AXButton", "elementTitle": "提交"},
                        context={"preferredLocatorType": "roleAndTitle"},
                        confidence=0.88,
                        is_preferred=True,
                        created_at="2026-03-26T10:00:00Z",
                    )
                ],
                assertions=[
                    SemanticActionAssertionRecord(
                        assertion_id="semantic-action-turn-001:assertion:required-frontmost-app",
                        assertion_type="requiredFrontmostApp",
                        assertion={"appBundleId": "com.apple.Safari"},
                        source="test",
                        created_at="2026-03-26T10:00:00Z",
                    )
                ],
                execution_logs=[
                    SemanticActionExecutionLogRecord(
                        execution_log_id="semantic-action-turn-001:execution:01",
                        trace_id="trace-001",
                        component="student.openclaw.runner.step",
                        status="STATUS_OCW_STEP_SUCCEEDED",
                        error_code=None,
                        selector_hit_path=["roleAndTitle", "textAnchor"],
                        result={"skillName": "sample"},
                        duration_ms=120,
                        execution_log_path="data/logs/2026-03-26/session-001-openclaw.log",
                        execution_result_path="data/reports/2026-03-26/execution-result.json",
                        review_id="review-001",
                        executed_at="2026-03-26T10:00:01Z",
                    )
                ],
            )

            fetched = repository.get_action("semantic-action-turn-001")
            self.assertIsNotNone(fetched)
            self.assertEqual(fetched["action_type"], "click")
            self.assertEqual(fetched["selector_json"]["locatorType"], "roleAndTitle")
            self.assertEqual(fetched["source_event_ids"], ["event-001"])
            self.assertEqual(len(fetched["targets"]), 1)
            self.assertEqual(fetched["targets"][0]["target_role"], "primary")
            self.assertEqual(len(fetched["assertions"]), 1)
            self.assertEqual(fetched["assertions"][0]["assertion_type"], "requiredFrontmostApp")
            self.assertEqual(len(fetched["execution_logs"]), 1)
            self.assertEqual(fetched["execution_logs"][0]["status"], "STATUS_OCW_STEP_SUCCEEDED")

            listed = repository.list_actions(session_id="session-001", action_type="click")
            self.assertEqual(len(listed), 1)

            self.assertEqual(manager.migrate_down(), [1])
            with sqlite3.connect(db_path) as connection:
                table_names = {row[0] for row in connection.execute("SELECT name FROM sqlite_master WHERE type='table'")}
            self.assertNotIn("semantic_actions", table_names)
            self.assertNotIn("action_targets", table_names)
            self.assertIn("_openstaff_schema_migrations", table_names)

    def test_cli_backfills_semantic_actions_from_turns(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            workspace_root = Path(tmpdir)
            turns_root = workspace_root / "data/learning/turns/2026-03-26/session-001"
            skill_path = workspace_root / "data/skills/pending/sample/openstaff-skill.json"
            db_path = workspace_root / "data/semantic-actions/semantic-actions.sqlite"

            skill_path.parent.mkdir(parents=True, exist_ok=True)
            skill_path.write_text(
                json.dumps(
                    {
                        "schemaVersion": "openstaff.openclaw-skill.v1",
                        "skillName": "sample",
                        "taskId": "task-001",
                        "sessionId": "session-001",
                        "provenance": {
                            "stepMappings": [
                                {
                                    "skillStepId": "skill-step-001",
                                    "knowledgeStepId": "step-001",
                                    "instruction": "点击提交按钮。",
                                    "sourceEventIds": ["event-001"],
                                    "preferredLocatorType": "roleAndTitle",
                                    "coordinate": {"x": 320, "y": 480, "coordinateSpace": "screen"},
                                    "semanticTargets": [
                                        {
                                            "locatorType": "roleAndTitle",
                                            "appBundleId": "com.apple.Safari",
                                            "elementRole": "AXButton",
                                            "elementTitle": "提交",
                                            "confidence": 0.91,
                                            "source": "capture",
                                        },
                                        {
                                            "locatorType": "coordinateFallback",
                                            "appBundleId": "com.apple.Safari",
                                            "boundingRect": {
                                                "x": 320,
                                                "y": 480,
                                                "width": 1,
                                                "height": 1,
                                                "coordinateSpace": "screen",
                                            },
                                            "confidence": 0.24,
                                            "source": "capture",
                                        },
                                    ],
                                    "locatorStrategyOrder": ["roleAndTitle", "coordinateFallback"],
                                    "requiresTeacherConfirmation": False,
                                    "notes": ["test fixture"],
                                }
                            ]
                        },
                        "mappedOutput": {
                            "executionPlan": {
                                "steps": [
                                    {
                                        "stepId": "skill-step-001",
                                        "actionType": "click",
                                        "instruction": "点击提交按钮。",
                                        "target": "semantic:提交按钮",
                                        "sourceEventIds": ["event-001"],
                                    }
                                ]
                            }
                        },
                    },
                    ensure_ascii=False,
                    indent=2,
                )
                + "\n",
                encoding="utf-8",
            )

            turns_root.mkdir(parents=True, exist_ok=True)
            (turns_root / "turn-001.json").write_text(
                json.dumps(
                    {
                        "schemaVersion": "openstaff.learning.interaction-turn.v0",
                        "turnId": "turn-001",
                        "traceId": "trace-001",
                        "sessionId": "session-001",
                        "taskId": "task-001",
                        "stepId": "step-001",
                        "mode": "teaching",
                        "turnKind": "taskProgression",
                        "stepIndex": 1,
                        "intentSummary": "Teach click action",
                        "actionSummary": "点击提交按钮。",
                        "actionKind": "guiAction",
                        "status": "captured",
                        "learningState": "linked",
                        "privacyTags": [],
                        "riskLevel": "low",
                        "appContext": {
                            "appName": "Safari",
                            "appBundleId": "com.apple.Safari",
                            "windowTitle": "OpenStaff",
                            "windowId": "window-001",
                            "windowSignature": "window-signature-001",
                        },
                        "observationRef": {
                            "sourceRecordPath": "data/source-records/session-001.json",
                            "rawEventLogPath": "data/raw-events/2026-03-26/session-001.jsonl",
                            "taskChunkPath": "data/task-chunks/2026-03-26/task-001.json",
                            "eventIds": ["event-001"],
                            "screenshotRefs": ["frame-001"],
                            "axRefs": [],
                            "ocrRefs": [],
                            "appContext": {
                                "appName": "Safari",
                                "appBundleId": "com.apple.Safari",
                                "windowTitle": "OpenStaff",
                                "windowId": "window-001",
                                "windowSignature": "window-signature-001",
                            },
                            "note": "fixture",
                        },
                        "semanticTargetSetRef": {
                            "sourcePath": "data/skills/pending/sample/openstaff-skill.json",
                            "sourceStepId": "skill-step-001",
                            "preferredLocatorType": "roleAndTitle",
                            "candidateCount": 2,
                            "semanticTargets": [
                                {
                                    "locatorType": "roleAndTitle",
                                    "appBundleId": "com.apple.Safari",
                                    "elementRole": "AXButton",
                                    "elementTitle": "提交",
                                    "confidence": 0.91,
                                    "source": "capture",
                                },
                                {
                                    "locatorType": "coordinateFallback",
                                    "appBundleId": "com.apple.Safari",
                                    "boundingRect": {
                                        "x": 320,
                                        "y": 480,
                                        "width": 1,
                                        "height": 1,
                                        "coordinateSpace": "screen",
                                    },
                                    "confidence": 0.24,
                                    "source": "capture",
                                },
                            ],
                        },
                        "stepReference": {
                            "stepId": "step-001",
                            "stepIndex": 1,
                            "instruction": "点击提交按钮。",
                            "knowledgeItemId": "knowledge-001",
                            "knowledgeStepId": "step-001",
                            "skillStepId": "skill-step-001",
                            "planStepId": None,
                            "sourceEventIds": ["event-001"],
                        },
                        "execution": {
                            "traceId": "trace-001",
                            "component": "student.openclaw.runner.step",
                            "skillName": "sample",
                            "skillDirectoryPath": "data/skills/pending/sample",
                            "planId": "plan-001",
                            "planStepId": "plan-step-001",
                            "status": "STATUS_OCW_STEP_SUCCEEDED",
                            "errorCode": None,
                            "executionLogPath": "data/logs/2026-03-26/session-001-openclaw.log",
                            "executionResultPath": "data/reports/2026-03-26/execution-result.json",
                            "reviewId": "review-001",
                        },
                        "review": None,
                        "sourceRefs": [
                            {
                                "artifactKind": "skillBundle",
                                "path": "data/skills/pending/sample/openstaff-skill.json",
                                "identifier": "sample",
                                "sha256": None,
                            }
                        ],
                        "buildDiagnostics": [],
                        "startedAt": "2026-03-26T10:00:00Z",
                        "endedAt": "2026-03-26T10:00:01Z",
                    },
                    ensure_ascii=False,
                    indent=2,
                )
                + "\n",
                encoding="utf-8",
            )

            result = subprocess.run(
                [
                    sys.executable,
                    str(SCRIPT),
                    "--workspace-root",
                    str(workspace_root),
                    "--turns-root",
                    str(workspace_root / "data/learning/turns"),
                    "--db-path",
                    str(db_path),
                    "--json",
                ],
                cwd=REPO_ROOT,
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertEqual(result.returncode, 0, msg=result.stderr or result.stdout)
            summary = json.loads(result.stdout)
            self.assertEqual(summary["backfill"]["writtenActions"], 1)
            self.assertEqual(summary["storedActionCount"], 1)
            self.assertEqual(summary["backfill"]["actionTypeCounts"], {"click": 1})

            repository = SemanticActionRepository(db_path)
            action = repository.get_action("semantic-action-turn-001")
            self.assertIsNotNone(action)
            self.assertEqual(action["action_type"], "click")
            self.assertEqual(action["selector_json"]["locatorType"], "roleAndTitle")
            self.assertEqual(action["source_event_ids"], ["event-001"])
            self.assertEqual(action["source_frame_ids"], ["frame-001"])
            self.assertFalse(action["manual_review_required"])
            self.assertEqual(len(action["targets"]), 2)
            self.assertEqual(len(action["assertions"]), 3)
            self.assertEqual(len(action["execution_logs"]), 1)
            self.assertEqual(action["execution_logs"][0]["selector_hit_path_json"], ["roleAndTitle", "coordinateFallback"])


if __name__ == "__main__":
    unittest.main()
