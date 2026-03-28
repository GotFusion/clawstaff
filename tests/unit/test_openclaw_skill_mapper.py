import importlib.util
import json
import tempfile
from pathlib import Path
import unittest


REPO_ROOT = Path(__file__).resolve().parents[2]
MODULE_PATH = REPO_ROOT / "scripts/skills/openclaw_skill_mapper.py"


def load_module():
    spec = importlib.util.spec_from_file_location("openclaw_skill_mapper", MODULE_PATH)
    module = importlib.util.module_from_spec(spec)
    assert spec is not None and spec.loader is not None
    spec.loader.exec_module(module)
    return module


class OpenClawSkillMapperTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.mod = load_module()
        cls.sample_knowledge = json.loads(
            (REPO_ROOT / "core/knowledge/examples/knowledge-item.sample.json").read_text(encoding="utf-8")
        )
        cls.sample_llm = json.loads(
            (REPO_ROOT / "scripts/llm/examples/knowledge-parse-output.sample.json").read_text(encoding="utf-8")
        )

    def test_sanitize_skill_name_uses_slug_and_limit(self):
        skill_name = self.mod.sanitize_skill_name("task-session-20260307-a1-001", "  Bad Name/With Spaces  ")
        self.assertEqual(skill_name, "bad-name-with-spaces")

    def test_parse_llm_output_invalid_text_produces_diagnostic(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            raw = Path(tmpdir) / "invalid.txt"
            raw.write_text("not a json output", encoding="utf-8")

            parsed, diagnostics = self.mod.parse_llm_output(raw)

        self.assertIsNone(parsed)
        self.assertTrue(any("Failed to extract JSON" in d for d in diagnostics))

    def test_normalize_execution_plan_fallbacks_when_llm_invalid(self):
        normalized, diagnostics = self.mod.normalize_execution_plan(
            knowledge_item=self.sample_knowledge,
            llm_output=None,
            llm_valid=False,
        )

        self.assertGreater(len(normalized["executionPlan"]["steps"]), 0)
        self.assertTrue(any("Fallback objective" in d for d in diagnostics))

    def test_build_provenance_contains_step_level_traceability(self):
        normalized, _ = self.mod.normalize_execution_plan(
            knowledge_item=self.sample_knowledge,
            llm_output=self.sample_llm,
            llm_valid=True,
        )

        provenance = self.mod.build_provenance(
            skill_name="openstaff-task-session-20260307-a1-001",
            knowledge_item=self.sample_knowledge,
            mapped=normalized,
            created_at=self.mod.iso_now(),
            llm_output_accepted=True,
        )

        self.assertEqual(provenance["knowledge"]["knowledgeItemId"], self.sample_knowledge["knowledgeItemId"])
        self.assertEqual(len(provenance["stepMappings"]), len(normalized["executionPlan"]["steps"]))
        self.assertEqual(provenance["stepMappings"][0]["knowledgeStepId"], "step-001")
        self.assertGreater(len(provenance["stepMappings"][0]["semanticTargets"]), 0)

    def test_build_provenance_infers_coordinate_fallback_from_instruction(self):
        knowledge = json.loads(json.dumps(self.sample_knowledge))
        knowledge["steps"][0]["instruction"] = "执行第 1 步点击操作（x=321, y=654，源事件 demo-event-001）。"
        knowledge["steps"][0].pop("target", None)
        normalized, _ = self.mod.normalize_execution_plan(
            knowledge_item=knowledge,
            llm_output=None,
            llm_valid=False,
        )

        provenance = self.mod.build_provenance(
            skill_name="benchmark-coordinate-fallback",
            knowledge_item=knowledge,
            mapped=normalized,
            created_at=self.mod.iso_now(),
            llm_output_accepted=False,
        )

        first_step = provenance["stepMappings"][0]
        self.assertEqual(first_step["preferredLocatorType"], "coordinateFallback")
        self.assertEqual(first_step["coordinate"]["x"], 321)
        self.assertEqual(first_step["coordinate"]["y"], 654)
        self.assertEqual(first_step["semanticTargets"][0]["locatorType"], "coordinateFallback")

    def test_normalize_execution_plan_fallback_prefers_semantic_targets(self):
        normalized, diagnostics = self.mod.normalize_execution_plan(
            knowledge_item=self.sample_knowledge,
            llm_output=None,
            llm_valid=False,
        )

        self.assertEqual(normalized["executionPlan"]["steps"][0]["target"], "button:Pull requests")
        self.assertEqual(normalized["executionPlan"]["steps"][1]["target"], "link:Issues")
        self.assertTrue(any("Applied fallback" in item for item in diagnostics))

    def test_validate_knowledge_item_detects_missing_steps(self):
        broken = dict(self.sample_knowledge)
        broken["steps"] = []

        errors = self.mod.validate_knowledge_item(broken)

        self.assertTrue(any("steps" in err for err in errors))

    def test_preference_assembly_applies_rules_and_orders_gui_locator_candidates(self):
        knowledge = json.loads(json.dumps(self.sample_knowledge))
        knowledge["constraints"] = [
            {
                "type": "frontmostAppMustMatch",
                "description": "执行前前台应用必须是 com.apple.Safari。"
            }
        ]
        llm_output = json.loads(json.dumps(self.sample_llm))
        llm_output["executionPlan"]["requiresTeacherConfirmation"] = False
        profile = {
            "schemaVersion": "openstaff.learning.preference-profile.v0",
            "profileVersion": "profile-skill-test-001",
            "skillPreferences": [
                {
                    "ruleId": "rule-locator-001",
                    "type": "locator",
                    "scope": {
                        "level": "app",
                        "appBundleId": "com.apple.Safari",
                        "appName": "Safari",
                    },
                    "statement": "Safari GUI skills should refresh semantic anchors before coordinate fallback.",
                    "hint": "Refresh semantic anchors before falling back to coordinates.",
                    "proposedAction": "refresh_skill_locator",
                    "teacherConfirmed": True,
                    "updatedAt": "2026-03-19T09:20:00Z",
                },
                {
                    "ruleId": "rule-risk-001",
                    "type": "risk",
                    "scope": {
                        "level": "taskFamily",
                        "taskFamily": "browser.navigation",
                    },
                    "statement": "Browser navigation should stay confirmation-gated.",
                    "hint": "Require confirmation before risky browser mutations.",
                    "proposedAction": "require_teacher_confirmation",
                    "teacherConfirmed": True,
                    "updatedAt": "2026-03-19T09:10:00Z",
                },
                {
                    "ruleId": "rule-procedure-001",
                    "type": "procedure",
                    "scope": {
                        "level": "app",
                        "appBundleId": "com.apple.Safari",
                        "appName": "Safari",
                    },
                    "statement": "Safari workflows should prefer keyboard-first navigation.",
                    "hint": "Prefer keyboard shortcuts before menu traversal.",
                    "proposedAction": "prefer_keyboard_shortcut",
                    "teacherConfirmed": False,
                    "updatedAt": "2026-03-19T09:05:00Z",
                },
                {
                    "ruleId": "rule-style-001",
                    "type": "style",
                    "scope": {"level": "global"},
                    "statement": "Review copy should stay concise and conclusion-first.",
                    "hint": "Keep notes concise and conclusion-first.",
                    "proposedAction": "shorten_review_copy",
                    "teacherConfirmed": True,
                    "updatedAt": "2026-03-19T09:00:00Z",
                },
            ],
        }

        normalized, _ = self.mod.normalize_execution_plan(
            knowledge_item=knowledge,
            llm_output=llm_output,
            llm_valid=True,
        )
        preference_assembly, diagnostics = self.mod.assemble_skill_preferences(
            knowledge_item=knowledge,
            profile=profile,
            profile_path="tests/fixtures/profile-skill-test-001.json",
            task_family="browser.navigation",
        )
        step_assemblies = self.mod.apply_preference_assembly(normalized, knowledge, preference_assembly)
        provenance = self.mod.build_provenance(
            skill_name="openstaff-task-session-20260307-a1-001",
            knowledge_item=knowledge,
            mapped=normalized,
            created_at=self.mod.iso_now(),
            llm_output_accepted=True,
            preference_assembly=preference_assembly,
            step_assemblies=step_assemblies,
        )

        self.assertEqual(diagnostics, [])
        self.assertTrue(normalized["executionPlan"]["requiresTeacherConfirmation"])
        self.assertIn("Require confirmation before risky browser mutations.", normalized["safetyNotes"])
        self.assertEqual(
            provenance["skillBuild"]["appliedPreferenceRuleIds"],
            ["rule-locator-001", "rule-risk-001", "rule-procedure-001", "rule-style-001"],
        )
        first_step = provenance["stepMappings"][0]
        self.assertEqual(first_step["actionKind"], "guiAction")
        self.assertEqual(
            first_step["locatorStrategyOrder"],
            ["ax", "textAnchor", "imageAnchor", "relativeCoordinate", "absoluteCoordinate"],
        )
        self.assertEqual(first_step["semanticTargets"][0]["locatorType"], "roleAndTitle")
        self.assertEqual(first_step["semanticTargets"][1]["source"], "skill-mapper-relative-coordinate")
        self.assertEqual(first_step["semanticTargets"][-1]["locatorType"], "coordinateFallback")
        self.assertEqual(
            first_step["appliedRuleIds"],
            ["rule-locator-001", "rule-risk-001", "rule-procedure-001", "rule-style-001"],
        )

    def test_native_action_prefers_shortcuts_before_other_native_routes(self):
        knowledge = {
            "schemaVersion": "knowledge.item.v0",
            "knowledgeItemId": "ki-shortcut-001",
            "taskId": "task-shortcut-001",
            "sessionId": "session-shortcut-001",
            "goal": "Use keyboard shortcut in Finder",
            "summary": "Single shortcut step.",
            "steps": [
                {
                    "stepId": "step-001",
                    "instruction": "Press shortcut Command+Shift+G to open the Go to Folder panel.",
                    "sourceEventIds": ["event-shortcut-001"],
                }
            ],
            "context": {
                "appName": "Finder",
                "appBundleId": "com.apple.finder",
                "windowTitle": "Desktop",
            },
            "constraints": [
                {
                    "type": "frontmostAppMustMatch",
                    "description": "Frontmost app must be Finder."
                }
            ],
            "source": {
                "taskChunkSchemaVersion": "knowledge.task-chunk.v0",
                "startTimestamp": "2026-03-19T09:00:00Z",
                "endTimestamp": "2026-03-19T09:00:01Z",
                "eventCount": 1,
                "boundaryReason": "idleGap",
            },
            "createdAt": "2026-03-19T09:05:00Z",
            "generatorVersion": "rule-v0",
        }
        llm_output = {
            "objective": "Use Finder keyboard shortcut",
            "context": {
                "appName": "Finder",
                "appBundleId": "com.apple.finder",
                "windowTitle": "Desktop",
            },
            "executionPlan": {
                "requiresTeacherConfirmation": False,
                "steps": [
                    {
                        "stepId": "step-001",
                        "actionType": "shortcut",
                        "instruction": "Press shortcut Command+Shift+G to open the Go to Folder panel.",
                        "target": "unknown",
                        "sourceEventIds": ["event-shortcut-001"],
                    }
                ],
                "completionCriteria": {
                    "expectedStepCount": 1,
                    "requiredFrontmostAppBundleId": "com.apple.finder",
                },
                "failurePolicy": {
                    "onContextMismatch": "stopAndAskTeacher",
                    "onStepError": "stopAndAskTeacher",
                    "onUnknownAction": "stopAndAskTeacher",
                },
            },
            "safetyNotes": ["Frontmost app must be Finder."],
            "confidence": 0.88,
        }
        profile = {
            "schemaVersion": "openstaff.learning.preference-profile.v0",
            "profileVersion": "profile-native-001",
            "skillPreferences": [
                {
                    "ruleId": "rule-native-shortcut-001",
                    "type": "procedure",
                    "scope": {
                        "level": "app",
                        "appBundleId": "com.apple.finder",
                        "appName": "Finder",
                    },
                    "statement": "Finder workflows should prefer keyboard shortcuts before scripted fallback.",
                    "hint": "Prefer keyboard shortcuts before CLI or AppleScript fallback.",
                    "proposedAction": "prefer_keyboard_shortcut",
                    "teacherConfirmed": True,
                    "updatedAt": "2026-03-19T09:00:00Z",
                }
            ],
        }

        normalized, _ = self.mod.normalize_execution_plan(
            knowledge_item=knowledge,
            llm_output=llm_output,
            llm_valid=True,
        )
        preference_assembly, _ = self.mod.assemble_skill_preferences(
            knowledge_item=knowledge,
            profile=profile,
            profile_path="tests/fixtures/profile-native-001.json",
        )
        step_assemblies = self.mod.apply_preference_assembly(normalized, knowledge, preference_assembly)
        provenance = self.mod.build_provenance(
            skill_name="openstaff-task-shortcut-001",
            knowledge_item=knowledge,
            mapped=normalized,
            created_at=self.mod.iso_now(),
            llm_output_accepted=True,
            preference_assembly=preference_assembly,
            step_assemblies=step_assemblies,
        )

        first_step = provenance["stepMappings"][0]
        self.assertEqual(first_step["actionKind"], "nativeAction")
        self.assertEqual(first_step["preferredNativeStrategy"], "shortcuts")
        self.assertEqual(
            first_step["nativeStrategyOrder"],
            ["shortcuts", "applescript", "cli", "app_adapter"],
        )


if __name__ == "__main__":
    unittest.main()
