import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


REPO_ROOT = Path(__file__).resolve().parents[2]
RUNNER = REPO_ROOT / "scripts/benchmarks/run_semantic_action_e2e_benchmark.py"
CATALOG = REPO_ROOT / "data/benchmarks/semantic-action-e2e/catalog.json"
REPLAY_VERIFY_EXECUTABLE = REPO_ROOT / "apps/macos/.build/debug/OpenStaffReplayVerifyCLI"


class SemanticActionE2EBenchmarkIntegrationTests(unittest.TestCase):
    def run_cmd(self, args):
        return subprocess.run(
            args,
            cwd=REPO_ROOT,
            capture_output=True,
            text=True,
            check=False,
        )

    def test_catalog_covers_all_sem401_scenarios(self):
        payload = json.loads(CATALOG.read_text(encoding="utf-8"))
        cases = payload["cases"]
        coverage = {item for case in cases for item in case["coverage"]}

        self.assertEqual(payload["benchmarkId"], "semantic-action-e2e-v20260328")
        self.assertEqual(len(cases), 8)
        self.assertEqual(
            coverage,
            {
                "browser_url",
                "drag_list",
                "drag_window",
                "focus_window",
                "multi_display",
                "shortcut",
                "switch_app",
                "type",
            },
        )

    def test_runner_materializes_subset_with_structured_attempt_artifacts(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            benchmark_root = Path(tmpdir) / "benchmark"
            manifest_path = benchmark_root / "manifest.json"
            command = [
                sys.executable,
                str(RUNNER),
                "--benchmark-root",
                str(benchmark_root),
                "--report",
                str(manifest_path),
                "--case-id",
                "sem401-switch-app-safari-to-finder",
                "--case-id",
                "sem401-drag-window-move",
                "--case-id",
                "sem401-browser-url-guard-mismatch",
            ]
            if REPLAY_VERIFY_EXECUTABLE.exists():
                command.extend(["--replay-verify-executable", str(REPLAY_VERIFY_EXECUTABLE)])

            result = self.run_cmd(command)

            self.assertEqual(result.returncode, 0, msg=result.stderr or result.stdout)
            self.assertTrue(manifest_path.exists())

            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            self.assertEqual(manifest["totalCases"], 3)
            self.assertEqual(manifest["passedCases"], 3)
            self.assertEqual(manifest["failedCases"], [])
            self.assertEqual(manifest["coverageCounts"]["switch_app"], 1)
            self.assertEqual(manifest["coverageCounts"]["drag_window"], 1)
            self.assertEqual(manifest["coverageCounts"]["browser_url"], 1)

            cases = {case["caseId"]: case for case in manifest["cases"]}
            blocked_case = cases["sem401-browser-url-guard-mismatch"]
            self.assertTrue(blocked_case["passed"])
            self.assertEqual(blocked_case["results"]["report"]["status"], "blocked")
            self.assertEqual(
                blocked_case["results"]["report"]["errorCode"],
                "SEM202-CONTEXT-MISMATCH",
            )

            for case in manifest["cases"]:
                case_dir = benchmark_root / "generated" / case["caseId"]
                attempt_dir = case_dir / "attempts" / "attempt-01"
                self.assertTrue((case_dir / "source-record.json").exists())
                self.assertTrue((case_dir / "case-report.json").exists())
                self.assertTrue((attempt_dir / "semantic-actions.sqlite").exists())
                self.assertTrue((attempt_dir / "cli-report.json").exists())
                self.assertTrue((attempt_dir / "execution-log.json").exists())
                self.assertTrue((attempt_dir / "attempt-report.json").exists())


if __name__ == "__main__":
    unittest.main()
