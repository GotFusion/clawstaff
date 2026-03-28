import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


REPO_ROOT = Path(__file__).resolve().parents[2]
RUNNER = REPO_ROOT / "scripts/release/run_regression.py"
PREFERENCE_METRICS_CONFIG = REPO_ROOT / "data/benchmarks/personal-preference/metrics-v0.json"
OPENCLAW_EXECUTABLE = REPO_ROOT / "apps/macos/.build/debug/OpenStaffOpenClawCLI"
REPLAY_VERIFY_EXECUTABLE = REPO_ROOT / "apps/macos/.build/debug/OpenStaffReplayVerifyCLI"
ASSIST_EXECUTABLE = REPO_ROOT / "apps/macos/.build/debug/OpenStaffAssistCLI"


class ReleaseRegressionIntegrationTests(unittest.TestCase):
    def run_cmd(self, args):
        return subprocess.run(
            args,
            cwd=REPO_ROOT,
            capture_output=True,
            text=True,
            check=False,
        )

    def test_release_regression_covers_validation_replay_semantic_and_preference_benchmarks(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            output_root = Path(tmpdir) / "release"
            report_path = output_root / "report.json"
            command = [
                sys.executable,
                str(RUNNER),
                "--skip-tests",
                "--skip-desktop-benchmark",
                "--benchmark-case-limit",
                "2",
                "--output-root",
                str(output_root),
                "--report",
                str(report_path),
            ]
            if OPENCLAW_EXECUTABLE.exists():
                command.extend(["--openclaw-executable", str(OPENCLAW_EXECUTABLE)])
            if REPLAY_VERIFY_EXECUTABLE.exists():
                command.extend(["--replay-verify-executable", str(REPLAY_VERIFY_EXECUTABLE)])
            if ASSIST_EXECUTABLE.exists():
                command.extend(["--assist-executable", str(ASSIST_EXECUTABLE)])

            result = self.run_cmd(command)

            self.assertEqual(result.returncode, 0, msg=result.stderr or result.stdout)
            self.assertTrue(report_path.exists())

            payload = json.loads(report_path.read_text(encoding="utf-8"))
            self.assertTrue(payload["passed"])
            check_names = {check["name"] for check in payload["checks"]}
            self.assertIn("raw-events-sample-strict", check_names)
            self.assertIn("knowledge-data-compat", check_names)
            self.assertIn("replay-verify-sample", check_names)
            self.assertIn("benchmark-semantic-action-e2e", check_names)
            self.assertIn("benchmark-personal-preference", check_names)
            self.assertIn("benchmark-personal-preference-gates", check_names)

    def test_release_regression_fails_when_preference_gate_regresses(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            output_root = Path(tmpdir) / "release"
            report_path = output_root / "report.json"
            config_path = Path(tmpdir) / "metrics-v0.strict.json"
            config = json.loads(PREFERENCE_METRICS_CONFIG.read_text(encoding="utf-8"))
            config["gates"]["preferenceMatchRate"] = {"type": "minimum", "value": 1.1}
            config_path.write_text(json.dumps(config, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

            command = [
                sys.executable,
                str(RUNNER),
                "--skip-tests",
                "--skip-desktop-benchmark",
                "--benchmark-case-limit",
                "2",
                "--output-root",
                str(output_root),
                "--report",
                str(report_path),
                "--preference-metrics-config",
                str(config_path),
            ]
            if REPLAY_VERIFY_EXECUTABLE.exists():
                command.extend(["--replay-verify-executable", str(REPLAY_VERIFY_EXECUTABLE)])
            if ASSIST_EXECUTABLE.exists():
                command.extend(["--assist-executable", str(ASSIST_EXECUTABLE)])

            result = self.run_cmd(command)

            self.assertEqual(result.returncode, 1, msg=result.stderr or result.stdout)
            self.assertTrue(report_path.exists())

            payload = json.loads(report_path.read_text(encoding="utf-8"))
            self.assertFalse(payload["passed"])
            self.assertIn("benchmark-personal-preference-gates", payload["failedChecks"])
            check_names = {check["name"] for check in payload["checks"]}
            self.assertIn("benchmark-semantic-action-e2e", check_names)
            self.assertIn("benchmark-personal-preference", check_names)
            self.assertIn("benchmark-personal-preference-gates", check_names)


if __name__ == "__main__":
    unittest.main()
