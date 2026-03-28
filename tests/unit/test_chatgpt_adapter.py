import importlib.util
import json
import sys
from pathlib import Path
import unittest


REPO_ROOT = Path(__file__).resolve().parents[2]
MODULE_PATH = REPO_ROOT / "scripts/llm/chatgpt_adapter.py"


def load_module():
    sys.path.insert(0, str(MODULE_PATH.parent))
    try:
        spec = importlib.util.spec_from_file_location("chatgpt_adapter", MODULE_PATH)
        module = importlib.util.module_from_spec(spec)
        assert spec is not None and spec.loader is not None
        sys.modules[spec.name] = module
        spec.loader.exec_module(module)
        return module
    finally:
        sys.path.pop(0)


class ChatGPTAdapterTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.mod = load_module()
        cls.sample_knowledge = json.loads(
            (REPO_ROOT / "core/knowledge/examples/knowledge-item.sample.json").read_text(encoding="utf-8")
        )

    def test_text_provider_output_prefers_semantic_targets(self):
        payload = self.mod.build_text_provider_output(self.sample_knowledge)

        first_step = payload["executionPlan"]["steps"][0]
        second_step = payload["executionPlan"]["steps"][1]

        self.assertEqual(first_step["target"], "button:Pull requests")
        self.assertEqual(second_step["target"], "link:Issues")
        self.assertNotIn("x=842", first_step["instruction"])
        self.assertNotIn("x=911", second_step["instruction"])
        self.assertNotIn("coordinate:", first_step["target"])


if __name__ == "__main__":
    unittest.main()
