import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT = REPO_ROOT / "scripts/learning/extract_preference_signals.py"


class PreferenceSignalExtractorCLIIntegrationTests(unittest.TestCase):
    def run_cmd(self, args):
        return subprocess.run(
            args,
            cwd=REPO_ROOT,
            capture_output=True,
            text=True,
            check=False,
        )

    def write_fixture_files(self, root: Path) -> tuple[Path, Path]:
        turn = {
            "schemaVersion": "openstaff.learning.interaction-turn.v0",
            "turnId": "turn-assist-taskProgression-task-001-step-001",
            "traceId": "trace-learning-assist-task-001-step-001",
            "sessionId": "session-001",
            "taskId": "task-001",
            "stepId": "step-001",
            "mode": "assist",
            "turnKind": "taskProgression",
            "actionSummary": "点击保存按钮。",
            "intentSummary": "在目标窗口中保存当前修改。",
            "appContext": {
                "appName": "Xcode",
                "appBundleId": "com.apple.dt.Xcode",
                "windowTitle": "Package.swift",
            },
            "review": {
                "decision": "needsRevision",
                "note": "先确认当前窗口标题，再点击目标按钮。",
            },
        }
        evidence_rows = [
            {
                "schemaVersion": "openstaff.learning.next-state-evidence.v0",
                "evidenceId": "evidence-teacher-001",
                "turnId": "turn-assist-taskProgression-task-001-step-001",
                "traceId": "trace-learning-assist-task-001-step-001",
                "sessionId": "session-001",
                "taskId": "task-001",
                "stepId": "step-001",
                "source": "teacherReview",
                "summary": "Teacher requested a correction before replaying the step.",
                "rawRefs": [],
                "timestamp": "2026-03-18T12:00:00Z",
                "confidence": 1.0,
                "severity": "warning",
                "role": "directive",
                "guiFailureBucket": None,
                "evaluativeCandidate": None,
                "directiveCandidate": {
                    "action": "adjust_procedure",
                    "hint": "先确认当前窗口标题，再点击目标按钮。",
                    "repairActionType": None,
                },
            }
        ]

        turn_path = root / "turn.json"
        evidence_path = root / "evidence.jsonl"
        turn_path.write_text(json.dumps(turn, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        evidence_path.write_text(
            "".join(json.dumps(row, ensure_ascii=False) + "\n" for row in evidence_rows),
            encoding="utf-8",
        )
        return turn_path, evidence_path

    def test_cli_writes_accepted_report_when_two_votes_match(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_root = Path(tmpdir)
            turn_path, evidence_path = self.write_fixture_files(tmp_root)
            mock_path = tmp_root / "accepted-votes.json"
            mock_path.write_text(
                json.dumps(
                    [
                        {
                            "decision": "fail",
                            "hint": "先确认当前窗口标题，再点击目标按钮。",
                            "signalType": "procedure",
                            "scope": "taskFamily",
                            "confidence": 0.84,
                        },
                        {
                            "decision": "fail",
                            "hint": "先确认当前窗口标题，再点击目标按钮。",
                            "signalType": "procedure",
                            "scope": "taskFamily",
                            "confidence": 0.82,
                        },
                        {
                            "decision": "fail",
                            "hint": "保持回答简洁，并去掉多余说明。",
                            "signalType": "style",
                            "scope": "global",
                            "confidence": 0.8,
                        },
                    ],
                    ensure_ascii=False,
                    indent=2,
                )
                + "\n",
                encoding="utf-8",
            )
            output_root = tmp_root / "preferences"

            result = self.run_cmd(
                [
                    sys.executable,
                    str(SCRIPT),
                    "--turn",
                    str(turn_path),
                    "--evidence",
                    str(evidence_path),
                    "--provider",
                    "mock",
                    "--mock-responses",
                    str(mock_path),
                    "--output-root",
                    str(output_root),
                ]
            )

            self.assertEqual(result.returncode, 0, msg=result.stderr or result.stdout)
            payload = json.loads(result.stdout)
            self.assertEqual(payload["result"]["status"], "accepted")
            self.assertEqual(payload["result"]["signalType"], "procedure")
            self.assertEqual(payload["candidateSignal"]["scope"]["taskFamily"], "assist.taskProgression")

            written = sorted(output_root.glob("extractions/*/*/*.json"))
            self.assertEqual(len(written), 1)
            stored = json.loads(written[0].read_text(encoding="utf-8"))
            self.assertEqual(stored["result"]["status"], "accepted")

    def test_cli_routes_low_confidence_majority_into_needs_review(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_root = Path(tmpdir)
            turn_path, evidence_path = self.write_fixture_files(tmp_root)
            mock_path = tmp_root / "review-votes.json"
            mock_path.write_text(
                json.dumps(
                    [
                        {
                            "decision": "fail",
                            "hint": "先确认当前窗口标题，再点击目标按钮。",
                            "signalType": "procedure",
                            "scope": "taskFamily",
                            "confidence": 0.55,
                        },
                        {
                            "decision": "fail",
                            "hint": "先确认当前窗口标题，再点击目标按钮。",
                            "signalType": "procedure",
                            "scope": "taskFamily",
                            "confidence": 0.58,
                        },
                        {
                            "decision": "fail",
                            "hint": "先确认当前窗口标题，再点击目标按钮。",
                            "signalType": "procedure",
                            "scope": "taskFamily",
                            "confidence": 0.57,
                        },
                    ],
                    ensure_ascii=False,
                    indent=2,
                )
                + "\n",
                encoding="utf-8",
            )
            output_root = tmp_root / "preferences"

            result = self.run_cmd(
                [
                    sys.executable,
                    str(SCRIPT),
                    "--turn",
                    str(turn_path),
                    "--evidence",
                    str(evidence_path),
                    "--provider",
                    "mock",
                    "--mock-responses",
                    str(mock_path),
                    "--output-root",
                    str(output_root),
                ]
            )

            self.assertEqual(result.returncode, 0, msg=result.stderr or result.stdout)
            payload = json.loads(result.stdout)
            self.assertEqual(payload["result"]["status"], "needs_review")
            self.assertEqual(payload["result"]["reason"], "low_confidence")

            written = sorted(output_root.glob("needs-review/*/*/*.json"))
            self.assertEqual(len(written), 1)
            stored = json.loads(written[0].read_text(encoding="utf-8"))
            self.assertEqual(stored["result"]["status"], "needs_review")


if __name__ == "__main__":
    unittest.main()
