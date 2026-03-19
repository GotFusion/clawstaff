import json
from collections import Counter
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


REPO_ROOT = Path(__file__).resolve().parents[2]
RUNNER = REPO_ROOT / "scripts/benchmarks/run_personal_preference_benchmark.py"
METRICS_RUNNER = REPO_ROOT / "scripts/benchmarks/aggregate_preference_metrics.py"
CATALOG = REPO_ROOT / "data/benchmarks/personal-preference/catalog.json"
ASSIST_EXECUTABLE = REPO_ROOT / "apps/macos/.build/debug/OpenStaffAssistCLI"
STUDENT_EXECUTABLE = REPO_ROOT / "apps/macos/.build/debug/OpenStaffStudentCLI"
REPLAY_VERIFY_EXECUTABLE = REPO_ROOT / "apps/macos/.build/debug/OpenStaffReplayVerifyCLI"
REVIEW_EXECUTABLE = REPO_ROOT / "apps/macos/.build/debug/OpenStaffExecutionReviewCLI"


class PersonalPreferenceBenchmarkIntegrationTests(unittest.TestCase):
    def run_cmd(self, args):
        return subprocess.run(
            args,
            cwd=REPO_ROOT,
            capture_output=True,
            text=True,
            check=False,
        )

    def test_catalog_has_twenty_four_cases_balanced_across_categories_and_sources(self):
        payload = json.loads(CATALOG.read_text(encoding="utf-8"))
        cases = payload["cases"]
        category_counts = Counter(case["preferenceCategory"] for case in cases)
        source_counts = Counter(case["sourceType"] for case in cases)
        module_counts = Counter(case["module"] for case in cases)

        self.assertEqual(payload["benchmarkId"], "personal-preference-v20260319")
        self.assertEqual(len(payload["profiles"]), 12)
        self.assertEqual(len(cases), 24)
        self.assertEqual(category_counts, Counter({"style": 6, "procedure": 6, "risk": 6, "repair": 6}))
        self.assertEqual(source_counts, Counter({"real": 12, "perturbation": 12}))
        self.assertEqual(set(module_counts), {"assist", "student", "review", "repair"})

    def test_runner_materializes_cross_module_subset(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            benchmark_root = Path(tmpdir) / "benchmark"
            manifest_path = benchmark_root / "manifest.json"
            metrics_path = benchmark_root / "metrics-summary.json"
            command = [
                sys.executable,
                str(RUNNER),
                "--benchmark-root",
                str(benchmark_root),
                "--report",
                str(manifest_path),
                "--case-id",
                "ppb-001-assist-style-toolbar-real",
                "--case-id",
                "ppb-011-student-procedure-shortcut-real",
                "--case-id",
                "ppb-017-review-risk-guard-real",
                "--case-id",
                "ppb-021-repair-relocalize-real",
            ]
            if ASSIST_EXECUTABLE.exists():
                command.extend(["--assist-executable", str(ASSIST_EXECUTABLE)])
            if STUDENT_EXECUTABLE.exists():
                command.extend(["--student-executable", str(STUDENT_EXECUTABLE)])
            if REPLAY_VERIFY_EXECUTABLE.exists():
                command.extend(["--replay-verify-executable", str(REPLAY_VERIFY_EXECUTABLE)])
            if REVIEW_EXECUTABLE.exists():
                command.extend(["--review-executable", str(REVIEW_EXECUTABLE)])

            result = self.run_cmd(command)

            self.assertEqual(result.returncode, 0, msg=result.stderr or result.stdout)
            self.assertTrue(manifest_path.exists())
            self.assertTrue(metrics_path.exists())

            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            self.assertEqual(manifest["totalCases"], 4)
            self.assertEqual(manifest["passedCases"], 4)
            self.assertEqual(len(manifest["failedCases"]), 0)
            self.assertEqual(manifest["metrics"]["preferenceMatchRate"], 1.0)
            self.assertTrue(manifest["metricsSummaryPath"].endswith("metrics-summary.json"))
            self.assertEqual(
                manifest["metrics"]["caseCountByModule"],
                {"assist": 1, "repair": 1, "review": 1, "student": 1},
            )

            metrics_summary = json.loads(metrics_path.read_text(encoding="utf-8"))
            self.assertTrue(metrics_summary["gates"]["passed"])
            self.assertEqual(metrics_summary["metrics"]["preferenceMatchRate"]["value"], 1.0)
            self.assertEqual(metrics_summary["metrics"]["assistAcceptanceRate"]["value"], 1.0)
            self.assertEqual(metrics_summary["metrics"]["repairPathHitRate"]["value"], 1.0)
            self.assertEqual(metrics_summary["metrics"]["teacherOverrideRate"]["value"], 0.0)
            self.assertEqual(metrics_summary["metrics"]["quickFeedbackCompletionRate"]["value"], 1.0)

            for case in manifest["cases"]:
                self.assertTrue(case["passed"])
                self.assertIn("measurements", case)
                self.assertGreaterEqual(case["measurements"]["moduleExecutionDurationSeconds"], 0)
                case_dir = benchmark_root / "generated" / case["caseId"]
                self.assertTrue((case_dir / "source-record.json").exists())
                self.assertTrue((case_dir / "profile-snapshot.json").exists())
                self.assertTrue((case_dir / "module-result.json").exists())
                self.assertTrue((case_dir / "review-result.json").exists())
                self.assertTrue((case_dir / "case-report.json").exists())

            recomputed_metrics_path = benchmark_root / "metrics-summary.recomputed.json"
            recompute = self.run_cmd(
                [
                    sys.executable,
                    str(METRICS_RUNNER),
                    "--benchmark-root",
                    str(benchmark_root),
                    "--manifest",
                    str(manifest_path),
                    "--catalog",
                    str(CATALOG),
                    "--output",
                    str(recomputed_metrics_path),
                    "--check-gates",
                ]
            )
            self.assertEqual(recompute.returncode, 0, msg=recompute.stderr or recompute.stdout)
            recomputed = json.loads(recomputed_metrics_path.read_text(encoding="utf-8"))
            self.assertEqual(recomputed["metrics"]["preferenceMatchRate"]["value"], 1.0)
            self.assertEqual(recomputed["metrics"]["unsafeAutoExecutionRegression"]["value"], 0)


if __name__ == "__main__":
    unittest.main()
