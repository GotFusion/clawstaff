import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT = REPO_ROOT / "scripts/learning/build_interaction_turns.py"


class InteractionTurnBackfillIntegrationTests(unittest.TestCase):
    def run_cmd(self, args):
        return subprocess.run(
            args,
            cwd=REPO_ROOT,
            capture_output=True,
            text=True,
            check=False,
        )

    def test_backfill_generates_learning_turns_and_examples(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_root = Path(tmpdir)
            output_root = tmp_root / "turns"
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
            self.assertGreaterEqual(summary["writtenTurnCount"], 20)
            self.assertIn("teaching", summary["modeCounts"])
            self.assertIn("student", summary["modeCounts"])
            self.assertGreater(summary["buildDiagnosticCount"], 0)
            self.assertIn("missing_observation_source_record", summary["buildDiagnosticCounts"])

            turn_files = sorted(output_root.glob("*/*/*.json"))
            self.assertGreaterEqual(len(turn_files), 20)

            sample_turn = json.loads(turn_files[0].read_text(encoding="utf-8"))
            self.assertEqual(sample_turn["schemaVersion"], "openstaff.learning.interaction-turn.v0")
            self.assertIn(sample_turn["mode"], {"teaching", "student"})
            self.assertIn("observationRef", sample_turn)
            self.assertIn("sourceRefs", sample_turn)
            self.assertIn("buildDiagnostics", sample_turn)
            self.assertGreaterEqual(len(sample_turn["sourceRefs"]), 3)

            assist_example = json.loads(
                (examples_root / "assist-suggestion-sample.json").read_text(encoding="utf-8")
            )
            self.assertEqual(assist_example["mode"], "assist")
            self.assertEqual(assist_example["turnKind"], "taskProgression")
            self.assertIn("buildDiagnostics", assist_example)


if __name__ == "__main__":
    unittest.main()
