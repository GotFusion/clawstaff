import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


REPO_ROOT = Path(__file__).resolve().parents[2]
VALIDATOR_PATH = REPO_ROOT / "scripts/validation/validate_skill_bundle.py"
SAMPLE_SKILL_DIR = REPO_ROOT / "scripts/skills/examples/generated/openstaff-task-session-20260307-a1-001"


def load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    assert spec is not None and spec.loader is not None
    spec.loader.exec_module(module)
    return module


def make_policy_risky_skill(skill_dir: Path) -> None:
    payload_path = skill_dir / "openstaff-skill.json"
    payload = json.loads(payload_path.read_text(encoding="utf-8"))
    payload["mappedOutput"]["executionPlan"]["requiresTeacherConfirmation"] = False
    payload["mappedOutput"]["context"]["windowTitle"] = "Checkout - 支付中心"
    payload["mappedOutput"]["confidence"] = 0.42

    step = payload["mappedOutput"]["executionPlan"]["steps"][0]
    step["instruction"] = "点击确认支付"
    step["target"] = "button:确认支付"

    step_mapping = payload["provenance"]["stepMappings"][0]
    step_mapping["semanticTargets"] = [
        {
            "locatorType": "coordinateFallback",
            "appBundleId": "com.apple.Safari",
            "windowTitlePattern": "Checkout - 支付中心",
            "boundingRect": {
                "x": 640,
                "y": 360,
                "width": 120,
                "height": 44,
                "coordinateSpace": "screen",
            },
            "confidence": 0.42,
            "source": "teaching.capture",
        }
    ]
    step_mapping["coordinate"] = {
        "x": 700,
        "y": 382,
        "coordinateSpace": "screen",
    }

    payload_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


class ValidateSkillBundleTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.validator = load_module("validate_skill_bundle", VALIDATOR_PATH)

    def test_build_report_marks_sample_as_needing_teacher_confirmation(self):
        report = self.validator.build_report(SAMPLE_SKILL_DIR, [])

        self.assertEqual(report["status"], "needs_teacher_confirmation")
        self.assertFalse(report["isAutoRunnable"])
        self.assertTrue(report["requiresTeacherConfirmation"])
        self.assertTrue(any(item["code"] == "SPF-MANUAL-CONFIRMATION-REQUIRED" for item in report["issues"]))

    def test_build_report_fails_when_context_app_is_unknown(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            skill_dir = Path(tmpdir) / "skill"
            shutil.copytree(SAMPLE_SKILL_DIR, skill_dir)

            payload_path = skill_dir / "openstaff-skill.json"
            payload = json.loads(payload_path.read_text(encoding="utf-8"))
            payload["mappedOutput"]["context"]["appBundleId"] = "unknown"
            payload["mappedOutput"]["executionPlan"]["completionCriteria"]["requiredFrontmostAppBundleId"] = "unknown"
            payload_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

            report = self.validator.build_report(skill_dir, [])

            self.assertEqual(report["status"], "failed")
            self.assertTrue(any(item["code"] == "SPF-MISSING-CONTEXT-APP" for item in report["issues"]))

    def test_build_report_blocks_sensitive_window_auto_run_by_default(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            skill_dir = Path(tmpdir) / "skill"
            shutil.copytree(SAMPLE_SKILL_DIR, skill_dir)
            make_policy_risky_skill(skill_dir)

            report = self.validator.build_report(skill_dir, [])

            self.assertEqual(report["status"], "needs_teacher_confirmation")
            self.assertFalse(report["isAutoRunnable"])
            step = report["steps"][0]
            self.assertTrue(step["highRisk"])
            self.assertTrue(step["lowConfidence"])
            self.assertTrue(step["lowReproducibility"])
            self.assertTrue(step["blocksAutoExecution"])
            self.assertIn("payment", step["sensitiveWindowTags"])
            self.assertTrue(any(item["code"] == "SPF-SENSITIVE-WINDOW" for item in step["issues"]))
            self.assertTrue(any(item["code"] == "SPF-AUTO-EXECUTION-BLOCKED" for item in step["issues"]))

    def test_build_report_allowlist_can_override_policy_block(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            skill_dir = Path(tmpdir) / "skill"
            shutil.copytree(SAMPLE_SKILL_DIR, skill_dir)
            make_policy_risky_skill(skill_dir)

            rules_path = Path(tmpdir) / "safety-rules.yaml"
            rules = {
                "schemaVersion": "openstaff.safety-rules.v1",
                "lowConfidenceThreshold": 0.8,
                "highRiskKeywords": ["支付"],
                "highRiskRegexPatterns": [],
                "autoExecutionAllowlist": {
                    "apps": ["com.apple.Safari"],
                    "tasks": ["task-session-20260307-a1-001"],
                    "skills": ["openstaff-task-session-20260307-a1-001"],
                },
                "sensitiveWindows": [
                    {
                        "tag": "payment",
                        "appBundleIds": [],
                        "windowTitleKeywords": ["支付中心"],
                        "windowTitleRegexPatterns": [],
                    }
                ],
            }
            rules_path.write_text(json.dumps(rules, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

            report = self.validator.build_report(skill_dir, [], rules_path)

            self.assertEqual(report["status"], "passed")
            self.assertTrue(report["isAutoRunnable"])
            step = report["steps"][0]
            self.assertFalse(step["requiresTeacherConfirmation"])
            self.assertFalse(step["blocksAutoExecution"])
            self.assertEqual(
                set(step["matchedAllowlistScopes"]),
                {
                    "app:com.apple.Safari",
                    "task:task-session-20260307-a1-001",
                    "skill:openstaff-task-session-20260307-a1-001",
                },
            )

    def test_build_report_keeps_declared_cross_app_skill_confirmation_gated(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            skill_dir = Path(tmpdir) / "skill"
            shutil.copytree(SAMPLE_SKILL_DIR, skill_dir)

            payload_path = skill_dir / "openstaff-skill.json"
            payload = json.loads(payload_path.read_text(encoding="utf-8"))
            payload["mappedOutput"]["context"]["appBundleId"] = "com.apple.finder"
            payload["mappedOutput"]["context"]["appName"] = "Finder"
            payload["mappedOutput"]["executionPlan"]["completionCriteria"]["requiredFrontmostAppBundleId"] = "com.apple.finder"
            payload_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

            report = self.validator.build_report(skill_dir, [])

            self.assertEqual(report["status"], "needs_teacher_confirmation")
            self.assertEqual(report["allowedAppBundleIds"], ["com.apple.finder", "com.apple.Safari"])
            self.assertFalse(any(item["code"] == "SPF-TARGET-APP-NOT-ALLOWED" for item in report["issues"]))

    def test_cli_require_auto_runnable_fails_confirmation_required_skill(self):
        completed = subprocess.run(
            [
                sys.executable,
                str(VALIDATOR_PATH),
                "--skill-dir",
                str(SAMPLE_SKILL_DIR),
                "--require-auto-runnable",
            ],
            cwd=REPO_ROOT,
            capture_output=True,
            text=True,
            check=False,
        )

        self.assertEqual(completed.returncode, 1)
        self.assertIn("NEEDS_TEACHER_CONFIRMATION", completed.stdout)


if __name__ == "__main__":
    unittest.main()
