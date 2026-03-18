import importlib.util
from pathlib import Path
import sys
import unittest


REPO_ROOT = Path(__file__).resolve().parents[2]
MODULE_PATH = REPO_ROOT / "scripts/learning/extract_preference_signals.py"


def load_module():
    spec = importlib.util.spec_from_file_location("extract_preference_signals", MODULE_PATH)
    module = importlib.util.module_from_spec(spec)
    assert spec is not None and spec.loader is not None
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


class ExtractPreferenceSignalsUnitTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.mod = load_module()

    def test_validate_output_accepts_minimal_valid_payload(self):
        payload = {
            "decision": "fail",
            "hint": "先确认当前窗口标题，再点击目标按钮。",
            "signalType": "procedure",
            "scope": "taskFamily",
            "confidence": 0.86,
        }

        errors = self.mod.validate_output(payload)

        self.assertEqual(errors, [])

    def test_validate_output_rejects_non_actionable_hint(self):
        payload = {
            "decision": "fail",
            "hint": "这一步做得不够好。",
            "signalType": "style",
            "scope": "global",
            "confidence": 0.7,
        }

        errors = self.mod.validate_output(payload)

        self.assertTrue(any("executable guidance" in error for error in errors))

    def test_extract_json_from_text_accepts_fenced_json(self):
        text = """
        before
        ```json
        {
          "decision": "fail",
          "hint": "更新按钮标题锚点后再重试。",
          "signalType": "locator",
          "scope": "app",
          "confidence": 0.81
        }
        ```
        after
        """

        payload = self.mod.extract_json_from_text(text)

        self.assertEqual(payload["signalType"], "locator")
        self.assertEqual(payload["scope"], "app")

    def test_majority_decision_accepts_matching_two_of_three_votes(self):
        votes = [
            {
                "voteIndex": 1,
                "status": "accepted",
                "structuredOutput": {
                    "decision": "fail",
                    "hint": "保持回答简洁，并去掉额外背景说明。",
                    "signalType": "style",
                    "scope": "global",
                    "confidence": 0.82,
                },
            },
            {
                "voteIndex": 2,
                "status": "accepted",
                "structuredOutput": {
                    "decision": "fail",
                    "hint": "保持回答简洁，并去掉额外背景说明。",
                    "signalType": "style",
                    "scope": "global",
                    "confidence": 0.88,
                },
            },
            {
                "voteIndex": 3,
                "status": "accepted",
                "structuredOutput": {
                    "decision": "fail",
                    "hint": "先检查页面状态，再回答。",
                    "signalType": "procedure",
                    "scope": "taskFamily",
                    "confidence": 0.8,
                },
            },
        ]

        result, candidate = self.mod.majority_decision(
            votes=votes,
            minimum_confidence=0.75,
            threshold=2,
        )

        self.assertEqual(result["status"], "accepted")
        self.assertEqual(result["signalType"], "style")
        self.assertAlmostEqual(result["confidence"], 0.85, places=2)
        self.assertEqual(candidate["scope"], "global")

    def test_majority_decision_routes_low_confidence_to_needs_review(self):
        votes = [
            {
                "voteIndex": 1,
                "status": "accepted",
                "structuredOutput": {
                    "decision": "fail",
                    "hint": "先补上前置检查，再执行下一步。",
                    "signalType": "procedure",
                    "scope": "taskFamily",
                    "confidence": 0.58,
                },
            },
            {
                "voteIndex": 2,
                "status": "accepted",
                "structuredOutput": {
                    "decision": "fail",
                    "hint": "先补上前置检查，再执行下一步。",
                    "signalType": "procedure",
                    "scope": "taskFamily",
                    "confidence": 0.62,
                },
            },
            {
                "voteIndex": 3,
                "status": "invalid",
                "errors": ["bad json"],
            },
        ]

        result, _candidate = self.mod.majority_decision(
            votes=votes,
            minimum_confidence=0.75,
            threshold=2,
        )

        self.assertEqual(result["status"], "needs_review")
        self.assertEqual(result["reason"], "low_confidence")

    def test_heuristic_provider_extracts_style_signal(self):
        provider = self.mod.HeuristicPreferenceProvider()
        context = self.mod.ExtractionContext(
            turn_path=Path("turn.json"),
            evidence_path=Path("evidence.jsonl"),
            turn={"turnId": "turn-001"},
            evidence={"evidenceId": "evidence-001"},
            teacher_note="回答要更简洁，直接给结论。",
            teacher_note_source="test",
            action_summary="生成回答",
            next_state_summary="Teacher marked the answer as too verbose.",
            next_state_role="directive",
            prompt_version="test",
            schema_path=Path("schema.json"),
            task_family="assist.reply",
            skill_family=None,
        )

        payload = self.mod.extract_json_from_text(
            provider.generate(
                system_prompt="",
                user_prompt="",
                context=context,
                timeout_seconds=1,
            )
        )

        self.assertEqual(payload["signalType"], "style")
        self.assertEqual(payload["scope"], "global")

    def test_heuristic_provider_extracts_risk_signal(self):
        provider = self.mod.HeuristicPreferenceProvider()
        context = self.mod.ExtractionContext(
            turn_path=Path("turn.json"),
            evidence_path=Path("evidence.jsonl"),
            turn={"turnId": "turn-001"},
            evidence={"evidenceId": "evidence-001"},
            teacher_note="这类删除操作不要自动执行，必须先让我确认。",
            teacher_note_source="test",
            action_summary="删除文件",
            next_state_summary="Teacher blocked the action as dangerous.",
            next_state_role="directive",
            prompt_version="test",
            schema_path=Path("schema.json"),
            task_family="student.execution",
            skill_family=None,
        )

        payload = self.mod.extract_json_from_text(
            provider.generate(
                system_prompt="",
                user_prompt="",
                context=context,
                timeout_seconds=1,
            )
        )

        self.assertEqual(payload["signalType"], "risk")
        self.assertEqual(payload["scope"], "app")


if __name__ == "__main__":
    unittest.main()
