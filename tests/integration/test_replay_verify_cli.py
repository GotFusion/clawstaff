from pathlib import Path
import unittest

from tests.swift_cli_test_utils import extract_last_json_object, run_swift_target


REPO_ROOT = Path(__file__).resolve().parents[2]
KNOWLEDGE_SAMPLE = REPO_ROOT / "core/knowledge/examples/knowledge-item.sample.json"
SNAPSHOT_SAMPLE = REPO_ROOT / "core/executor/examples/replay-environment.sample.json"


class ReplayVerifyCLITests(unittest.TestCase):
    def test_replay_verify_cli_resolves_sample_knowledge_with_sample_snapshot(self):
        result = run_swift_target(
            "OpenStaffReplayVerifyCLI",
            [
                "--knowledge",
                str(KNOWLEDGE_SAMPLE),
                "--snapshot",
                str(SNAPSHOT_SAMPLE),
                "--json",
            ],
        )

        self.assertEqual(result.returncode, 0, msg=result.stderr or result.stdout)
        payload = extract_last_json_object(result.stdout)
        summary = payload["summary"]

        self.assertEqual(summary["knowledgeItemCount"], 1)
        self.assertEqual(summary["resolvedSteps"], 2)
        self.assertEqual(summary["degradedSteps"], 0)
        self.assertEqual(summary["failedSteps"], 0)


if __name__ == "__main__":
    unittest.main()
