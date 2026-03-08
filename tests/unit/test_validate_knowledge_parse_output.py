import copy
import importlib.util
import json
from pathlib import Path
import unittest


REPO_ROOT = Path(__file__).resolve().parents[2]
MODULE_PATH = REPO_ROOT / "scripts/llm/validate_knowledge_parse_output.py"


def load_module():
    spec = importlib.util.spec_from_file_location("validate_knowledge_parse_output", MODULE_PATH)
    module = importlib.util.module_from_spec(spec)
    assert spec is not None and spec.loader is not None
    spec.loader.exec_module(module)
    return module


class ValidateKnowledgeParseOutputTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.mod = load_module()
        cls.sample_output = json.loads(
            (REPO_ROOT / "scripts/llm/examples/knowledge-parse-output.sample.json").read_text(encoding="utf-8")
        )
        cls.sample_knowledge = json.loads(
            (REPO_ROOT / "core/knowledge/examples/knowledge-item.sample.json").read_text(encoding="utf-8")
        )

    def test_validate_output_accepts_sample(self):
        errors = self.mod.validate_output(self.sample_output)
        self.assertEqual(errors, [])

    def test_validate_output_rejects_confidence_out_of_range(self):
        invalid = copy.deepcopy(self.sample_output)
        invalid["confidence"] = 1.2

        errors = self.mod.validate_output(invalid)

        self.assertTrue(any("$.confidence" in err for err in errors))

    def test_extract_json_from_fenced_text(self):
        payload = '{"schemaVersion":"llm.knowledge-parse.v0","knowledgeItemId":"k","taskId":"task-a-001","sessionId":"s-1","objective":"o","context":{"appName":"a","appBundleId":"b","windowTitle":null},"executionPlan":{"requiresTeacherConfirmation":false,"steps":[{"stepId":"step-001","actionType":"click","instruction":"click","target":"coordinate:1,2","sourceEventIds":["e-1"]}],"completionCriteria":{"expectedStepCount":1,"requiredFrontmostAppBundleId":"b"},"failurePolicy":{"onContextMismatch":"stopAndAskTeacher","onStepError":"stopAndAskTeacher","onUnknownAction":"stopAndAskTeacher"}},"safetyNotes":["n"],"confidence":0.8}'
        text = "before\n```json\n" + payload + "\n```\nafter"

        data = self.mod.extract_json_from_text(text)

        self.assertEqual(data["schemaVersion"], "llm.knowledge-parse.v0")

    def test_validate_with_knowledge_item_detects_mismatch(self):
        invalid = copy.deepcopy(self.sample_output)
        invalid["objective"] = "different"

        errors = self.mod.validate_with_knowledge_item(invalid, self.sample_knowledge)

        self.assertTrue(any("objective" in err for err in errors))


if __name__ == "__main__":
    unittest.main()
