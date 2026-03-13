import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


REPO_ROOT = Path(__file__).resolve().parents[2]
RUNNER = REPO_ROOT / "scripts/benchmarks/run_personal_desktop_benchmark.py"
CATALOG = REPO_ROOT / "data/benchmarks/personal-desktop/catalog.json"
OPENCLAW_EXECUTABLE = REPO_ROOT / "apps/macos/.build/debug/OpenStaffOpenClawCLI"


class PersonalDesktopBenchmarkIntegrationTests(unittest.TestCase):
    def run_cmd(self, args):
        return subprocess.run(
            args,
            cwd=REPO_ROOT,
            capture_output=True,
            text=True,
            check=False,
        )

    def test_catalog_has_at_least_twenty_cases_across_four_categories(self):
        payload = json.loads(CATALOG.read_text(encoding="utf-8"))
        cases = payload["cases"]
        categories = {case["category"] for case in cases}

        self.assertGreaterEqual(len(cases), 20)
        self.assertEqual(len(categories), 4)

    def test_runner_materializes_two_case_subset(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            benchmark_root = Path(tmpdir) / "benchmark"
            manifest_path = benchmark_root / "manifest.json"
            command = [
                sys.executable,
                str(RUNNER),
                "--benchmark-root",
                str(benchmark_root),
                "--case-limit",
                "2",
                "--report",
                str(manifest_path),
            ]
            if OPENCLAW_EXECUTABLE.exists():
                command.extend(["--openclaw-executable", str(OPENCLAW_EXECUTABLE)])

            result = self.run_cmd(command)

            self.assertEqual(result.returncode, 0, msg=result.stderr or result.stdout)
            self.assertTrue(manifest_path.exists())

            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            self.assertEqual(manifest["totalCases"], 2)
            self.assertEqual(manifest["passedCases"], 2)
            self.assertEqual(len(manifest["failedCases"]), 0)

            for case in manifest["cases"]:
                self.assertTrue(case["passed"])
                case_dir = benchmark_root / "generated" / case["caseId"]
                self.assertTrue((case_dir / "case-report.json").exists())
                self.assertTrue((case_dir / "review-result.json").exists())
                self.assertTrue((case_dir / "skill-preflight.json").exists())


if __name__ == "__main__":
    unittest.main()
