import json
from pathlib import Path
import tempfile
import unittest

from tests.swift_cli_test_utils import extract_last_json_object, run_swift_target


REPO_ROOT = Path(__file__).resolve().parents[2]
KNOWLEDGE_SAMPLE = REPO_ROOT / "core/knowledge/examples/knowledge-item.sample.json"


class ThreeModeCLIRoundtripTests(unittest.TestCase):
    def test_three_mode_roundtrip_with_real_clis(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_path = Path(tmpdir)
            logs_root = tmp_path / "logs"
            reports_root = tmp_path / "reports"
            timestamp = "2026-03-09T10:15:00+08:00"

            orchestrator = run_swift_target(
                "OpenStaffOrchestratorCLI",
                [
                    "--from",
                    "teaching",
                    "--to",
                    "assist",
                    "--session-id",
                    "session-20260307-a1",
                    "--teacher-confirmed",
                    "--knowledge-ready",
                    "--trace-id",
                    "trace-e2e-orchestrator-001",
                    "--timestamp",
                    timestamp,
                    "--json-decision",
                ],
            )
            self.assertEqual(orchestrator.returncode, 0, msg=orchestrator.stderr or orchestrator.stdout)
            decision = extract_last_json_object(orchestrator.stdout)
            self.assertTrue(decision.get("accepted"))
            self.assertEqual(decision.get("toMode"), "assist")

            assist = run_swift_target(
                "OpenStaffAssistCLI",
                [
                    "--knowledge-item",
                    str(KNOWLEDGE_SAMPLE),
                    "--from",
                    "teaching",
                    "--auto-confirm",
                    "yes",
                    "--logs-root",
                    str(logs_root),
                    "--trace-id",
                    "trace-e2e-assist-001",
                    "--timestamp",
                    timestamp,
                    "--json-result",
                ],
            )
            self.assertEqual(assist.returncode, 0, msg=assist.stderr or assist.stdout)
            assist_result = extract_last_json_object(assist.stdout)
            self.assertEqual(assist_result.get("finalStatus"), "completed")
            assist_log_path = Path(assist_result["logFilePath"])
            self.assertTrue(assist_log_path.exists())

            student = run_swift_target(
                "OpenStaffStudentCLI",
                [
                    "--goal",
                    "在 Safari 中复现点击流程",
                    "--knowledge",
                    str(KNOWLEDGE_SAMPLE),
                    "--from",
                    "assist",
                    "--logs-root",
                    str(logs_root),
                    "--reports-root",
                    str(reports_root),
                    "--trace-id",
                    "trace-e2e-student-001",
                    "--timestamp",
                    timestamp,
                    "--json-result",
                ],
            )
            self.assertEqual(student.returncode, 0, msg=student.stderr or student.stdout)
            student_result = extract_last_json_object(student.stdout)
            self.assertEqual(student_result.get("finalStatus"), "completed")

            student_log_path = Path(student_result["logFilePath"])
            report_file_path = Path(student_result["reportFilePath"])
            self.assertTrue(student_log_path.exists())
            self.assertTrue(report_file_path.exists())

            report_payload = json.loads(report_file_path.read_text(encoding="utf-8"))
            self.assertEqual(report_payload.get("schemaVersion"), "student.review-report.v0")
            self.assertEqual(report_payload.get("finalStatus"), "completed")


if __name__ == "__main__":
    unittest.main()
