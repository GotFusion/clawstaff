import json
from pathlib import Path
import tempfile
import unittest

from tests.swift_cli_test_utils import extract_last_json_object, run_swift_target


def make_knowledge_item(
    knowledge_item_id: str,
    task_id: str,
    created_at: str,
    goal: str,
    window_title: str,
    step_titles: list[str],
) -> dict:
    steps = []
    for index, title in enumerate(step_titles, start=1):
        steps.append(
            {
                "stepId": f"step-{index:03d}",
                "instruction": f"点击 {title}",
                "sourceEventIds": [f"evt-{knowledge_item_id}-{index:03d}"],
                "target": {
                    "coordinate": {
                        "x": 300 + index,
                        "y": 400 + index,
                        "coordinateSpace": "screen",
                    },
                    "semanticTargets": [
                        {
                            "locatorType": "roleAndTitle",
                            "appBundleId": "com.apple.Safari",
                            "windowTitlePattern": "^OpenStaff\\ - GitHub$",
                            "elementRole": "AXButton",
                            "elementTitle": title,
                            "elementIdentifier": title.lower().replace(" ", "-"),
                            "confidence": 0.91,
                            "source": "capture",
                        }
                    ],
                    "preferredLocatorType": "roleAndTitle",
                },
            }
        )

    return {
        "schemaVersion": "knowledge.item.v0",
        "knowledgeItemId": knowledge_item_id,
        "taskId": task_id,
        "sessionId": f"session-{knowledge_item_id}",
        "goal": goal,
        "summary": "summary",
        "steps": steps,
        "context": {
            "appName": "Safari",
            "appBundleId": "com.apple.Safari",
            "windowTitle": window_title,
            "windowId": "1",
        },
        "constraints": [],
        "source": {
            "taskChunkSchemaVersion": "knowledge.task-chunk.v0",
            "startTimestamp": "2026-03-13T10:00:00Z",
            "endTimestamp": "2026-03-13T10:00:02Z",
            "eventCount": len(step_titles),
            "boundaryReason": "sessionEnd",
        },
        "createdAt": created_at,
        "generatorVersion": "rule-v0",
    }


class AssistRetrievalCLITests(unittest.TestCase):
    def test_assist_cli_uses_history_retrieval_and_reports_sources(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_path = Path(tmpdir)
            knowledge_dir = tmp_path / "knowledge"
            logs_root = tmp_path / "logs"
            knowledge_dir.mkdir()

            items = [
                make_knowledge_item(
                    knowledge_item_id="ki-merge-002",
                    task_id="task-merge-002",
                    created_at="2026-03-13T12:00:00Z",
                    goal="在 Safari 中处理 Pull Requests",
                    window_title="OpenStaff - GitHub",
                    step_titles=["Pull Requests", "Merge"],
                ),
                make_knowledge_item(
                    knowledge_item_id="ki-merge-001",
                    task_id="task-merge-001",
                    created_at="2026-03-13T11:00:00Z",
                    goal="在 Safari 中处理 Pull Requests",
                    window_title="OpenStaff - GitHub",
                    step_titles=["Pull Requests", "Merge"],
                ),
                make_knowledge_item(
                    knowledge_item_id="ki-issue-001",
                    task_id="task-issue-001",
                    created_at="2026-03-13T10:00:00Z",
                    goal="在 Safari 中处理 Pull Requests",
                    window_title="OpenStaff - GitHub",
                    step_titles=["Issues", "New Issue"],
                ),
            ]

            for item in items:
                (knowledge_dir / f"{item['knowledgeItemId']}.json").write_text(
                    json.dumps(item, ensure_ascii=False, indent=2),
                    encoding="utf-8",
                )

            result = run_swift_target(
                "OpenStaffAssistCLI",
                [
                    "--knowledge-item",
                    str(knowledge_dir),
                    "--from",
                    "teaching",
                    "--app-name",
                    "Safari",
                    "--app-bundle-id",
                    "com.apple.Safari",
                    "--window-title",
                    "OpenStaff - GitHub",
                    "--goal",
                    "处理 Pull Requests",
                    "--recent-step",
                    "点击 Pull Requests",
                    "--completed-steps",
                    "1",
                    "--auto-confirm",
                    "yes",
                    "--logs-root",
                    str(logs_root),
                    "--trace-id",
                    "trace-e2e-assist-retrieval-001",
                    "--timestamp",
                    "2026-03-13T10:15:00+08:00",
                    "--json-result",
                ],
            )

            self.assertEqual(result.returncode, 0, msg=result.stderr or result.stdout)
            payload = extract_last_json_object(result.stdout)
            self.assertEqual(payload.get("finalStatus"), "completed")

            suggestion = payload.get("suggestion") or {}
            action = suggestion.get("action") or {}
            evidence = suggestion.get("evidence") or []

            self.assertEqual(suggestion.get("predictorVersion"), "retrievalV1")
            self.assertEqual(suggestion.get("knowledgeItemId"), "ki-merge-002")
            self.assertEqual(action.get("instruction"), "点击 Merge")
            self.assertIn("参考了 2 条历史知识", action.get("reason", ""))
            self.assertEqual(len(evidence), 2)
            self.assertEqual(evidence[0].get("knowledgeItemId"), "ki-merge-002")
            self.assertEqual(evidence[1].get("knowledgeItemId"), "ki-merge-001")
            self.assertTrue(Path(payload["logFilePath"]).exists())

    def test_assist_cli_applies_preference_rerank_from_latest_profile(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_path = Path(tmpdir)
            knowledge_dir = tmp_path / "knowledge"
            logs_root = tmp_path / "logs"
            preferences_root = tmp_path / "preferences"
            profiles_dir = preferences_root / "profiles"
            knowledge_dir.mkdir()
            profiles_dir.mkdir(parents=True)

            items = [
                make_knowledge_item(
                    knowledge_item_id="ki-click-tab-002",
                    task_id="task-click-tab-002",
                    created_at="2026-03-13T12:00:00Z",
                    goal="在 Safari 中打开新标签页",
                    window_title="OpenStaff - GitHub",
                    step_titles=["Pull Requests", "新标签页按钮"],
                ),
                make_knowledge_item(
                    knowledge_item_id="ki-shortcut-tab-001",
                    task_id="task-shortcut-tab-001",
                    created_at="2026-03-13T11:00:00Z",
                    goal="在 Safari 中打开新标签页",
                    window_title="OpenStaff - GitHub",
                    step_titles=["Pull Requests", "Command+T 打开新标签页"],
                ),
            ]
            items[1]["steps"][1]["instruction"] = "快捷键 Command+T 打开新标签页"

            for item in items:
                (knowledge_dir / f"{item['knowledgeItemId']}.json").write_text(
                    json.dumps(item, ensure_ascii=False, indent=2),
                    encoding="utf-8",
                )

            profile = {
                "schemaVersion": "openstaff.learning.preference-profile.v0",
                "profileVersion": "profile-shortcut-001",
                "activeRuleIds": ["rule-app-shortcut-001"],
                "assistPreferences": [
                    {
                        "ruleId": "rule-app-shortcut-001",
                        "type": "procedure",
                        "scope": {
                            "level": "app",
                            "appBundleId": "com.apple.Safari",
                            "appName": "Safari",
                        },
                        "statement": "Prefer keyboard shortcuts for opening tabs in Safari.",
                        "hint": "Use shortcuts instead of toolbar clicks when opening a new tab.",
                        "proposedAction": "prefer_keyboard_shortcut",
                        "teacherConfirmed": True,
                        "updatedAt": "2026-03-19T10:00:00Z",
                    }
                ],
                "skillPreferences": [],
                "repairPreferences": [],
                "reviewPreferences": [],
                "plannerPreferences": [],
                "generatedAt": "2026-03-19T10:00:00Z",
            }
            snapshot = {
                "schemaVersion": "openstaff.learning.preference-profile-snapshot.v0",
                "profileVersion": "profile-shortcut-001",
                "profile": profile,
                "sourceRuleIds": ["rule-app-shortcut-001"],
                "createdAt": "2026-03-19T10:00:00Z",
                "note": "assist rerank e2e",
            }
            latest_pointer = {
                "profileVersion": "profile-shortcut-001",
                "updatedAt": "2026-03-19T10:00:00Z",
            }
            (profiles_dir / "profile-shortcut-001.json").write_text(
                json.dumps(snapshot, ensure_ascii=False, indent=2),
                encoding="utf-8",
            )
            (profiles_dir / "latest.json").write_text(
                json.dumps(latest_pointer, ensure_ascii=False, indent=2),
                encoding="utf-8",
            )

            result = run_swift_target(
                "OpenStaffAssistCLI",
                [
                    "--knowledge-item",
                    str(knowledge_dir),
                    "--preferences-root",
                    str(preferences_root),
                    "--from",
                    "teaching",
                    "--app-name",
                    "Safari",
                    "--app-bundle-id",
                    "com.apple.Safari",
                    "--window-title",
                    "OpenStaff - GitHub",
                    "--goal",
                    "在 Safari 中打开新标签页",
                    "--task-family",
                    "browser.navigation",
                    "--recent-step",
                    "点击 Pull Requests",
                    "--completed-steps",
                    "1",
                    "--auto-confirm",
                    "yes",
                    "--logs-root",
                    str(logs_root),
                    "--trace-id",
                    "trace-e2e-assist-preference-001",
                    "--timestamp",
                    "2026-03-19T10:15:00+08:00",
                    "--json-result",
                ],
                extra_env={"OPENSTAFF_ENABLE_POLICY_ASSEMBLY_LOG": "1"},
            )

            self.assertEqual(result.returncode, 0, msg=result.stderr or result.stdout)
            payload = extract_last_json_object(result.stdout)
            suggestion = payload.get("suggestion") or {}
            preference = suggestion.get("preferenceDecision") or {}

            self.assertEqual(payload.get("finalStatus"), "completed")
            self.assertEqual(suggestion.get("predictorVersion"), "preferenceAwareRetrievalV1")
            self.assertEqual(suggestion.get("knowledgeItemId"), "ki-shortcut-tab-001")
            self.assertEqual(preference.get("profileVersion"), "profile-shortcut-001")
            self.assertEqual(preference.get("appliedRuleIds"), ["rule-app-shortcut-001"])
            self.assertTrue(preference.get("candidateExplanations"))
            self.assertTrue(Path(payload["logFilePath"]).exists())
            assembly_files = list((preferences_root / "assembly").rglob("*.json"))
            self.assertEqual(len(assembly_files), 1)
            assembly = json.loads(assembly_files[0].read_text(encoding="utf-8"))
            self.assertEqual(assembly["targetModule"], "assist")
            self.assertEqual(assembly["strategyVersion"], "preferenceAwareRetrievalV1")
            self.assertEqual(assembly["appliedRuleIds"], ["rule-app-shortcut-001"])
            self.assertEqual(assembly["inputRef"]["traceId"], "trace-e2e-assist-preference-001")


if __name__ == "__main__":
    unittest.main()
