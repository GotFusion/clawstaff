import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT = REPO_ROOT / "scripts/learning/build_next_state_evidence.py"


class NextStateEvidenceBackfillIntegrationTests(unittest.TestCase):
    def run_cmd(self, args):
        return subprocess.run(
            args,
            cwd=REPO_ROOT,
            capture_output=True,
            text=True,
            check=False,
        )

    def test_backfill_generates_evidence_and_source_examples(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_root = Path(tmpdir)
            output_root = tmp_root / "evidence"
            examples_root = tmp_root / "examples"
            result = self.run_cmd(
                [
                    sys.executable,
                    str(SCRIPT),
                    "--clean",
                    "--output-root",
                    output_root.as_posix(),
                    "--examples-root",
                    examples_root.as_posix(),
                ]
            )

            self.assertEqual(result.returncode, 0, msg=result.stderr or result.stdout)
            summary = json.loads(result.stdout)
            self.assertGreaterEqual(summary["writtenEvidenceCount"], 20)
            self.assertGreaterEqual(summary["turnsWithEvidenceCount"], 15)
            self.assertIn("benchmarkResult", summary["sourceCounts"])
            self.assertIn("executionRuntime", summary["sourceCounts"])

            evidence_files = sorted(output_root.glob("*/*/*.jsonl"))
            self.assertGreaterEqual(len(evidence_files), 15)

            first_lines = evidence_files[0].read_text(encoding="utf-8").splitlines()
            self.assertGreaterEqual(len(first_lines), 1)
            sample_evidence = json.loads(first_lines[0])
            self.assertEqual(sample_evidence["schemaVersion"], "openstaff.learning.next-state-evidence.v0")
            self.assertIn(sample_evidence["source"], {"teacherReview", "executionRuntime", "benchmarkResult"})
            self.assertIn("rawRefs", sample_evidence)
            self.assertGreaterEqual(len(sample_evidence["rawRefs"]), 1)

            example_sources = set()
            for path in sorted(examples_root.glob("*.jsonl")):
                lines = [line for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]
                self.assertEqual(len(lines), 1, msg=f"{path} should contain exactly one example line")
                payload = json.loads(lines[0])
                example_sources.add(payload["source"])

            self.assertEqual(
                example_sources,
                {
                    "teacherReview",
                    "executionRuntime",
                    "replayVerify",
                    "driftDetection",
                    "chatgptSuggestion",
                    "benchmarkResult",
                },
            )


if __name__ == "__main__":
    unittest.main()
