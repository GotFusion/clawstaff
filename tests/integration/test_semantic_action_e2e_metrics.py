import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


REPO_ROOT = Path(__file__).resolve().parents[2]
RUNNER = REPO_ROOT / "scripts/benchmarks/run_semantic_action_e2e_benchmark.py"
METRICS_RUNNER = REPO_ROOT / "scripts/benchmarks/aggregate_semantic_action_e2e_metrics.py"
REPLAY_VERIFY_EXECUTABLE = REPO_ROOT / "apps/macos/.build/debug/OpenStaffReplayVerifyCLI"


class SemanticActionE2EMetricsIntegrationTests(unittest.TestCase):
    def run_cmd(self, args: list[str]) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            args,
            cwd=REPO_ROOT,
            capture_output=True,
            text=True,
            check=False,
        )

    def write_config(
        self,
        path: Path,
        *,
        selector_minimum: float,
        p95_maximum: float,
        stability_minimum: float,
    ) -> None:
        payload = {
            "schemaVersion": "openstaff.semantic-action-e2e-metrics-config.v0",
            "configId": "semantic-action-e2e-metrics-test",
            "benchmarkId": "semantic-action-e2e-v20260328",
            "baseline": {
                "casePassRate": 1.0,
                "selectorResolutionRate": 0.5,
                "p95ActionDurationMs": 1.0,
                "maxActionDurationMs": 1.0,
                "timeoutCount": 0,
                "flakeRecoveryRate": 0.0,
            },
            "gates": {
                "casePassRate": {"type": "minimum", "value": 1.0},
                "selectorResolutionRate": {"type": "minimum", "value": selector_minimum},
                "p95ActionDurationMs": {"type": "maximum", "value": p95_maximum},
                "timeoutCount": {"type": "maximum", "value": 0},
                "stabilityPassRate": {"type": "minimum", "value": stability_minimum},
            },
        }
        path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    def test_metrics_summary_aggregates_p95_and_stability_rate(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_root = Path(tmpdir)
            benchmark_root = tmp_root / "benchmark"
            manifest_path = benchmark_root / "manifest.json"
            config_path = tmp_root / "metrics.json"
            output_path = tmp_root / "metrics-summary.json"

            benchmark_command = [
                sys.executable,
                str(RUNNER),
                "--benchmark-root",
                str(benchmark_root),
                "--report",
                str(manifest_path),
                "--repeat-count",
                "3",
                "--case-id",
                "sem401-switch-app-safari-to-finder",
                "--case-id",
                "sem401-browser-url-guard-mismatch",
            ]
            if REPLAY_VERIFY_EXECUTABLE.exists():
                benchmark_command.extend(["--replay-verify-executable", str(REPLAY_VERIFY_EXECUTABLE)])
            benchmark_result = self.run_cmd(benchmark_command)
            self.assertEqual(benchmark_result.returncode, 0, msg=benchmark_result.stderr or benchmark_result.stdout)

            self.write_config(
                config_path,
                selector_minimum=0.5,
                p95_maximum=25,
                stability_minimum=1.0,
            )
            metrics_result = self.run_cmd(
                [
                    sys.executable,
                    str(METRICS_RUNNER),
                    "--benchmark-root",
                    str(benchmark_root),
                    "--manifest",
                    str(manifest_path),
                    "--config",
                    str(config_path),
                    "--output",
                    str(output_path),
                    "--check-gates",
                ]
            )

            self.assertEqual(metrics_result.returncode, 0, msg=metrics_result.stderr or metrics_result.stdout)
            self.assertTrue(output_path.exists())
            summary = json.loads(output_path.read_text(encoding="utf-8"))
            self.assertTrue(summary["gates"]["passed"])
            self.assertEqual(summary["repeatCount"], 3)
            self.assertEqual(summary["selectedCaseCount"], 6)
            self.assertEqual(summary["metrics"]["casePassRate"]["value"], 1.0)
            self.assertEqual(summary["metrics"]["selectorResolutionRate"]["value"], 0.5)
            self.assertEqual(summary["metrics"]["stabilityPassRate"]["value"], 1.0)
            self.assertEqual(summary["metrics"]["timeoutCount"]["value"], 0)
            self.assertGreaterEqual(summary["metrics"]["p95ActionDurationMs"]["value"], 0)

    def test_metrics_summary_fails_when_p95_gate_is_too_strict(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_root = Path(tmpdir)
            benchmark_root = tmp_root / "benchmark"
            manifest_path = benchmark_root / "manifest.json"
            config_path = tmp_root / "metrics.strict.json"
            output_path = tmp_root / "metrics-summary.json"

            benchmark_command = [
                sys.executable,
                str(RUNNER),
                "--benchmark-root",
                str(benchmark_root),
                "--report",
                str(manifest_path),
                "--case-id",
                "sem401-switch-app-safari-to-finder",
            ]
            if REPLAY_VERIFY_EXECUTABLE.exists():
                benchmark_command.extend(["--replay-verify-executable", str(REPLAY_VERIFY_EXECUTABLE)])
            benchmark_result = self.run_cmd(benchmark_command)
            self.assertEqual(benchmark_result.returncode, 0, msg=benchmark_result.stderr or benchmark_result.stdout)

            self.write_config(
                config_path,
                selector_minimum=1.0,
                p95_maximum=-1,
                stability_minimum=1.0,
            )
            metrics_result = self.run_cmd(
                [
                    sys.executable,
                    str(METRICS_RUNNER),
                    "--benchmark-root",
                    str(benchmark_root),
                    "--manifest",
                    str(manifest_path),
                    "--config",
                    str(config_path),
                    "--output",
                    str(output_path),
                    "--check-gates",
                ]
            )

            self.assertEqual(metrics_result.returncode, 1, msg=metrics_result.stderr or metrics_result.stdout)
            summary = json.loads(output_path.read_text(encoding="utf-8"))
            self.assertFalse(summary["gates"]["passed"])
            self.assertEqual(summary["gates"]["failed"], 1)
            failed_metric = next(
                result["metric"]
                for result in summary["gates"]["results"]
                if result.get("passed") is False
            )
            self.assertEqual(failed_metric, "p95ActionDurationMs")


if __name__ == "__main__":
    unittest.main()
