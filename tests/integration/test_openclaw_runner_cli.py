from pathlib import Path
import json
import shutil
import tempfile
import unittest

from tests.swift_cli_test_utils import extract_last_json_object, run_swift_target


REPO_ROOT = Path(__file__).resolve().parents[2]
SKILL_SAMPLE_DIRECTORIES = [
    REPO_ROOT / "scripts/skills/examples/generated/openstaff-task-session-20260307-a1-001",
    REPO_ROOT / "scripts/skills/examples/generated/openstaff-task-session-20260307-b2-001",
    REPO_ROOT / "scripts/skills/examples/generated/openstaff-task-session-20260307-c3-001",
]


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


class OpenClawRunnerCLITests(unittest.TestCase):
    def test_runner_executes_three_sample_skills_via_subprocess(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            logs_root = Path(tmpdir) / "logs"

            for skill_dir in SKILL_SAMPLE_DIRECTORIES:
                result = run_swift_target(
                    "OpenStaffOpenClawCLI",
                    [
                        "--skill-dir",
                        str(skill_dir),
                        "--logs-root",
                        str(logs_root),
                        "--teacher-confirmed",
                        "--json-result",
                    ],
                )

                self.assertEqual(result.returncode, 0, msg=result.stderr or result.stdout)
                payload = extract_last_json_object(result.stdout)
                self.assertEqual(payload["status"], "succeeded")
                self.assertEqual(payload["exitCode"], 0)
                self.assertGreater(payload["totalSteps"], 0)
                self.assertEqual(payload["review"]["status"], "succeeded")
                self.assertTrue(Path(payload["review"]["logFilePath"]).exists())

    def test_runner_returns_structured_failure_when_gateway_step_fails(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            logs_root = Path(tmpdir) / "logs"
            result = run_swift_target(
                "OpenStaffOpenClawCLI",
                [
                    "--skill-dir",
                    str(SKILL_SAMPLE_DIRECTORIES[0]),
                    "--logs-root",
                    str(logs_root),
                    "--simulate-runtime-failure-step",
                    "1",
                    "--teacher-confirmed",
                    "--json-result",
                ],
            )

            self.assertEqual(result.returncode, 2, msg=result.stderr or result.stdout)
            payload = extract_last_json_object(result.stdout)
            self.assertEqual(payload["status"], "failed")
            self.assertEqual(payload["errorCode"], "OCW-RUNTIME-FAILED")
            self.assertEqual(payload["failedSteps"], 1)
            self.assertEqual(payload["stepResults"][0]["errorCode"], "OCW-RUNTIME-FAILED")
            self.assertIn("OpenClaw gateway error", payload["stderr"])
            self.assertTrue(Path(payload["review"]["logFilePath"]).exists())

    def test_runner_blocks_confirmation_required_skill_without_teacher_confirmation(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            logs_root = Path(tmpdir) / "logs"
            result = run_swift_target(
                "OpenStaffOpenClawCLI",
                [
                    "--skill-dir",
                    str(SKILL_SAMPLE_DIRECTORIES[0]),
                    "--logs-root",
                    str(logs_root),
                    "--json-result",
                ],
            )

            self.assertEqual(result.returncode, 2, msg=result.stderr or result.stdout)
            payload = extract_last_json_object(result.stdout)
            self.assertEqual(payload["status"], "blocked")
            self.assertEqual(payload["errorCode"], "OCW-SKILL-CONFIRMATION-REQUIRED")
            self.assertEqual(payload["preflight"]["status"], "needs_teacher_confirmation")
            self.assertTrue(
                any(item["code"] == "SPF-MANUAL-CONFIRMATION-REQUIRED" for item in payload["preflight"]["issues"])
            )

    def test_runner_blocks_preflight_failure_before_gateway(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            skill_dir = Path(tmpdir) / "skill"
            shutil.copytree(SKILL_SAMPLE_DIRECTORIES[0], skill_dir)
            payload_path = skill_dir / "openstaff-skill.json"
            payload = json.loads(payload_path.read_text(encoding="utf-8"))
            payload["mappedOutput"]["context"]["appBundleId"] = "unknown"
            payload["mappedOutput"]["executionPlan"]["completionCriteria"]["requiredFrontmostAppBundleId"] = "unknown"
            payload_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

            logs_root = Path(tmpdir) / "logs"
            result = run_swift_target(
                "OpenStaffOpenClawCLI",
                [
                    "--skill-dir",
                    str(skill_dir),
                    "--logs-root",
                    str(logs_root),
                    "--teacher-confirmed",
                    "--json-result",
                ],
            )

            self.assertEqual(result.returncode, 2, msg=result.stderr or result.stdout)
            payload = extract_last_json_object(result.stdout)
            self.assertEqual(payload["status"], "blocked")
            self.assertEqual(payload["errorCode"], "OCW-SKILL-PREFLIGHT-FAILED")
            self.assertEqual(payload["preflight"]["status"], "failed")
            self.assertTrue(any(item["code"] == "SPF-MISSING-CONTEXT-APP" for item in payload["preflight"]["issues"]))

    def test_runner_blocks_sensitive_window_skill_by_default(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            skill_dir = Path(tmpdir) / "skill"
            shutil.copytree(SKILL_SAMPLE_DIRECTORIES[0], skill_dir)
            make_policy_risky_skill(skill_dir)

            logs_root = Path(tmpdir) / "logs"
            result = run_swift_target(
                "OpenStaffOpenClawCLI",
                [
                    "--skill-dir",
                    str(skill_dir),
                    "--logs-root",
                    str(logs_root),
                    "--json-result",
                ],
            )

            self.assertEqual(result.returncode, 2, msg=result.stderr or result.stdout)
            payload = extract_last_json_object(result.stdout)
            self.assertEqual(payload["status"], "blocked")
            self.assertEqual(payload["errorCode"], "OCW-SKILL-CONFIRMATION-REQUIRED")
            self.assertEqual(payload["preflight"]["status"], "needs_teacher_confirmation")
            step = payload["preflight"]["steps"][0]
            self.assertTrue(step["blocksAutoExecution"])
            self.assertIn("payment", step["sensitiveWindowTags"])
            self.assertTrue(any(item["code"] == "SPF-SENSITIVE-WINDOW" for item in step["issues"]))
            self.assertTrue(any(item["code"] == "SPF-AUTO-EXECUTION-BLOCKED" for item in step["issues"]))

    def test_runner_accepts_allowlisted_sensitive_skill(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            skill_dir = Path(tmpdir) / "skill"
            shutil.copytree(SKILL_SAMPLE_DIRECTORIES[0], skill_dir)
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

            logs_root = Path(tmpdir) / "logs"
            result = run_swift_target(
                "OpenStaffOpenClawCLI",
                [
                    "--skill-dir",
                    str(skill_dir),
                    "--logs-root",
                    str(logs_root),
                    "--safety-rules",
                    str(rules_path),
                    "--json-result",
                ],
            )

            self.assertEqual(result.returncode, 0, msg=result.stderr or result.stdout)
            payload = extract_last_json_object(result.stdout)
            self.assertEqual(payload["status"], "succeeded")
            self.assertEqual(payload["preflight"]["status"], "passed")
            step = payload["preflight"]["steps"][0]
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


if __name__ == "__main__":
    unittest.main()
