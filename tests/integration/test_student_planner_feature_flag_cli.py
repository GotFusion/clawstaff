import json
from pathlib import Path
import tempfile
import unittest

from tests.swift_cli_test_utils import extract_last_json_object, run_swift_target


class StudentPlannerFeatureFlagCLITests(unittest.TestCase):
    def test_student_planner_uses_preference_aware_strategy_when_flag_enabled(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            root = Path(tmpdir)
            knowledge_root = root / "knowledge"
            preferences_root = root / "preferences"
            logs_root = root / "logs"
            reports_root = root / "reports"
            profiles_root = preferences_root / "profiles"

            knowledge_root.mkdir(parents=True)
            profiles_root.mkdir(parents=True)

            (knowledge_root / "knowledge-001.json").write_text(
                json.dumps(
                    {
                        "schemaVersion": "knowledge.item.v0",
                        "knowledgeItemId": "knowledge-001",
                        "taskId": "task-open-tab-menu",
                        "sessionId": "session-001",
                        "goal": "在 Safari 打开新标签页",
                        "summary": "通过菜单逐步打开新标签页。",
                        "steps": [
                            {
                                "stepId": "step-001",
                                "instruction": "点击 File 菜单",
                                "sourceEventIds": ["evt-1"],
                            },
                            {
                                "stepId": "step-002",
                                "instruction": "点击 New Tab",
                                "sourceEventIds": ["evt-2"],
                            },
                        ],
                        "context": {
                            "appName": "Safari",
                            "appBundleId": "com.apple.Safari",
                            "windowTitle": "Main",
                            "windowId": None,
                        },
                        "constraints": [
                            {
                                "type": "manualConfirmationRequired",
                                "description": "菜单切换前需要确认当前页面状态。",
                            }
                        ],
                        "source": {
                            "taskChunkSchemaVersion": "task.chunk.v0",
                            "startTimestamp": "2026-03-19T10:00:00Z",
                            "endTimestamp": "2026-03-19T10:00:10Z",
                            "eventCount": 2,
                            "boundaryReason": "sessionEnd",
                        },
                        "createdAt": "2026-03-19T10:00:10Z",
                        "generatorVersion": "rule-v0",
                    },
                    ensure_ascii=False,
                ),
                encoding="utf-8",
            )
            (knowledge_root / "knowledge-002.json").write_text(
                json.dumps(
                    {
                        "schemaVersion": "knowledge.item.v0",
                        "knowledgeItemId": "knowledge-002",
                        "taskId": "task-open-tab-shortcut",
                        "sessionId": "session-001",
                        "goal": "在 Safari 打开新标签页",
                        "summary": "直接使用快捷键打开新标签页。",
                        "steps": [
                            {
                                "stepId": "step-001",
                                "instruction": "按下 Command+T 打开新标签页",
                                "sourceEventIds": ["evt-1"],
                                "target": {
                                    "semanticTargets": [
                                        {
                                            "locatorType": "roleAndTitle",
                                            "appBundleId": "com.apple.Safari",
                                            "windowTitlePattern": "^Main$",
                                            "elementRole": "AXButton",
                                            "elementTitle": "New Tab",
                                            "confidence": 0.92,
                                            "source": "capture",
                                        }
                                    ],
                                    "preferredLocatorType": "roleAndTitle",
                                },
                            }
                        ],
                        "context": {
                            "appName": "Safari",
                            "appBundleId": "com.apple.Safari",
                            "windowTitle": "Main",
                            "windowId": None,
                        },
                        "constraints": [],
                        "source": {
                            "taskChunkSchemaVersion": "task.chunk.v0",
                            "startTimestamp": "2026-03-19T10:00:00Z",
                            "endTimestamp": "2026-03-19T10:00:05Z",
                            "eventCount": 1,
                            "boundaryReason": "sessionEnd",
                        },
                        "createdAt": "2026-03-19T10:00:05Z",
                        "generatorVersion": "rule-v0",
                    },
                    ensure_ascii=False,
                ),
                encoding="utf-8",
            )

            (profiles_root / "latest.json").write_text(
                json.dumps({"profileVersion": "profile-test-001"}, ensure_ascii=False),
                encoding="utf-8",
            )
            (profiles_root / "profile-test-001.json").write_text(
                json.dumps(
                    {
                        "schemaVersion": "openstaff.learning.preference-profile-snapshot.v0",
                        "profileVersion": "profile-test-001",
                        "profile": {
                            "schemaVersion": "openstaff.learning.preference-profile.v0",
                            "profileVersion": "profile-test-001",
                            "activeRuleIds": ["rule-safari-shortcut-001"],
                            "assistPreferences": [],
                            "skillPreferences": [],
                            "repairPreferences": [],
                            "reviewPreferences": [],
                            "plannerPreferences": [
                                {
                                    "ruleId": "rule-safari-shortcut-001",
                                    "type": "procedure",
                                    "scope": {
                                        "level": "app",
                                        "appBundleId": "com.apple.Safari",
                                        "appName": "Safari",
                                    },
                                    "statement": "Prefer keyboard shortcut execution for tab workflows.",
                                    "hint": "Prefer keyboard shortcut execution for tab workflows.",
                                    "proposedAction": "prefer_keyboard_shortcut",
                                    "teacherConfirmed": True,
                                    "updatedAt": "2026-03-19T10:20:00Z",
                                }
                            ],
                            "generatedAt": "2026-03-19T10:30:00Z",
                        },
                        "sourceRuleIds": ["rule-safari-shortcut-001"],
                        "createdAt": "2026-03-19T10:30:00Z",
                        "previousProfileVersion": None,
                        "note": "Integration test profile",
                    },
                    ensure_ascii=False,
                ),
                encoding="utf-8",
            )

            result = run_swift_target(
                "OpenStaffStudentCLI",
                [
                    "--goal",
                    "在 Safari 打开新标签页",
                    "--knowledge",
                    str(knowledge_root),
                    "--enable-preference-aware-planner",
                    "--student-planner-benchmark-safe",
                    "--preferences-root",
                    str(preferences_root),
                    "--logs-root",
                    str(logs_root),
                    "--reports-root",
                    str(reports_root),
                    "--trace-id",
                    "trace-student-pref-001",
                    "--timestamp",
                    "2026-03-19T10:35:00+08:00",
                    "--json-result",
                ],
            )

            self.assertEqual(result.returncode, 0, msg=result.stderr or result.stdout)
            payload = extract_last_json_object(result.stdout)
            self.assertEqual(payload.get("finalStatus"), "completed")
            self.assertEqual(payload["plan"]["strategy"], "preferenceAwareRuleV1")
            self.assertEqual(payload["plan"]["plannerVersion"], "preference-aware-rule-v1")
            self.assertEqual(payload["plan"]["selectedKnowledgeItemId"], "knowledge-002")
            self.assertEqual(
                payload["plan"]["preferenceDecision"]["executionStyle"],
                "assertive",
            )
            self.assertEqual(
                payload["plan"]["preferenceDecision"]["appliedRuleIds"],
                ["rule-safari-shortcut-001"],
            )


if __name__ == "__main__":
    unittest.main()
