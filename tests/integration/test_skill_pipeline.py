import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


REPO_ROOT = Path(__file__).resolve().parents[2]
MAPPER = REPO_ROOT / "scripts/skills/openclaw_skill_mapper.py"
VALIDATOR = REPO_ROOT / "scripts/skills/validate_openclaw_skill.py"


class SkillPipelineIntegrationTests(unittest.TestCase):
    def run_cmd(self, args):
        return subprocess.run(
            args,
            cwd=REPO_ROOT,
            capture_output=True,
            text=True,
            check=False,
        )

    def test_pipeline_with_valid_llm_output(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            skills_root = Path(tmpdir) / "skills"
            mapper = self.run_cmd(
                [
                    sys.executable,
                    str(MAPPER),
                    "--knowledge-item",
                    "core/knowledge/examples/knowledge-item.sample.json",
                    "--llm-output",
                    "scripts/llm/examples/knowledge-parse-output.sample.json",
                    "--skills-root",
                    str(skills_root),
                    "--overwrite",
                ]
            )
            self.assertEqual(mapper.returncode, 0, msg=mapper.stderr or mapper.stdout)

            skill_dir = skills_root / "openstaff-task-session-20260307-a1-001"
            self.assertTrue((skill_dir / "SKILL.md").exists())
            self.assertTrue((skill_dir / "openstaff-skill.json").exists())
            mapping = json.loads((skill_dir / "openstaff-skill.json").read_text(encoding="utf-8"))
            self.assertEqual(mapping["schemaVersion"], "openstaff.openclaw-skill.v1")
            self.assertEqual(mapping["provenance"]["knowledge"]["taskId"], mapping["taskId"])

            validator = self.run_cmd([sys.executable, str(VALIDATOR), "--skill-dir", str(skill_dir)])
            self.assertEqual(validator.returncode, 0, msg=validator.stderr or validator.stdout)

    def test_pipeline_fallback_with_invalid_llm_output(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            skills_root = Path(tmpdir) / "skills"
            mapper = self.run_cmd(
                [
                    sys.executable,
                    str(MAPPER),
                    "--knowledge-item",
                    "scripts/skills/examples/knowledge-item.sample.terminal.json",
                    "--llm-output",
                    "scripts/skills/examples/llm-output.sample.terminal-invalid.txt",
                    "--skills-root",
                    str(skills_root),
                    "--overwrite",
                ]
            )
            self.assertEqual(mapper.returncode, 0, msg=mapper.stderr or mapper.stdout)

            skill_dir = skills_root / "openstaff-task-session-20260307-c3-001"
            mapping = json.loads((skill_dir / "openstaff-skill.json").read_text(encoding="utf-8"))
            self.assertFalse(mapping["llmOutputAccepted"])
            self.assertGreater(len(mapping["diagnostics"]), 0)
            self.assertEqual(mapping["schemaVersion"], "openstaff.openclaw-skill.v1")
            self.assertEqual(mapping["provenance"]["skillBuild"]["repairVersion"], 0)

            validator = self.run_cmd([sys.executable, str(VALIDATOR), "--skill-dir", str(skill_dir)])
            self.assertEqual(validator.returncode, 0, msg=validator.stderr or validator.stdout)

    def test_pipeline_with_preference_profile_records_rule_traceability(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_path = Path(tmpdir)
            skills_root = tmp_path / "skills"
            profile_path = tmp_path / "profile.json"
            profile_path.write_text(
                json.dumps(
                    {
                        "schemaVersion": "openstaff.learning.preference-profile.v0",
                        "profileVersion": "profile-skill-pipeline-001",
                        "skillPreferences": [
                            {
                                "ruleId": "rule-safari-locator-001",
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
                                "ruleId": "rule-browser-risk-001",
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
                        ],
                    },
                    ensure_ascii=False,
                    indent=2,
                )
                + "\n",
                encoding="utf-8",
            )

            mapper = self.run_cmd(
                [
                    sys.executable,
                    str(MAPPER),
                    "--knowledge-item",
                    "core/knowledge/examples/knowledge-item.sample.json",
                    "--llm-output",
                    "scripts/llm/examples/knowledge-parse-output.sample.json",
                    "--skills-root",
                    str(skills_root),
                    "--overwrite",
                    "--preference-profile",
                    str(profile_path),
                    "--task-family",
                    "browser.navigation",
                ]
            )
            self.assertEqual(mapper.returncode, 0, msg=mapper.stderr or mapper.stdout)

            skill_dir = skills_root / "openstaff-task-session-20260307-a1-001"
            mapping = json.loads((skill_dir / "openstaff-skill.json").read_text(encoding="utf-8"))
            skill_build = mapping["provenance"]["skillBuild"]
            self.assertEqual(skill_build["preferenceProfileVersion"], "profile-skill-pipeline-001")
            self.assertEqual(
                skill_build["appliedPreferenceRuleIds"],
                ["rule-safari-locator-001", "rule-browser-risk-001"],
            )
            first_step = mapping["provenance"]["stepMappings"][0]
            self.assertEqual(first_step["actionKind"], "guiAction")
            self.assertEqual(
                first_step["locatorStrategyOrder"],
                ["ax", "textAnchor", "imageAnchor", "relativeCoordinate", "absoluteCoordinate"],
            )
            self.assertTrue(mapping["mappedOutput"]["executionPlan"]["requiresTeacherConfirmation"])

            validator = self.run_cmd([sys.executable, str(VALIDATOR), "--skill-dir", str(skill_dir)])
            self.assertEqual(validator.returncode, 0, msg=validator.stderr or validator.stdout)


if __name__ == "__main__":
    unittest.main()
