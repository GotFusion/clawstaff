import importlib.util
import json
import sys
from pathlib import Path
import unittest


REPO_ROOT = Path(__file__).resolve().parents[2]
MODULE_PATH = REPO_ROOT / "scripts/llm/render_knowledge_prompts.py"


def load_module():
    sys.path.insert(0, str(MODULE_PATH.parent))
    try:
        spec = importlib.util.spec_from_file_location("render_knowledge_prompts", MODULE_PATH)
        module = importlib.util.module_from_spec(spec)
        assert spec is not None and spec.loader is not None
        spec.loader.exec_module(module)
        return module
    finally:
        sys.path.pop(0)


class RenderKnowledgePromptsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.mod = load_module()
        cls.sample_knowledge = json.loads(
            (REPO_ROOT / "core/knowledge/examples/knowledge-item.sample.json").read_text(encoding="utf-8")
        )
        cls.task_template = (
            REPO_ROOT / "scripts/llm/prompts/task-knowledge-parser-v0.md"
        ).read_text(encoding="utf-8")
        cls.output_schema = json.loads(
            (REPO_ROOT / "scripts/llm/schemas/knowledge-parse-output.schema.json").read_text(encoding="utf-8")
        )

    def test_build_prompt_knowledge_item_omits_coordinate_payloads(self):
        prompt_item = self.mod.build_prompt_knowledge_item(self.sample_knowledge)

        serialized = json.dumps(prompt_item, ensure_ascii=False, sort_keys=True)
        self.assertIn("button:Pull requests", serialized)
        self.assertIn("link:Issues", serialized)
        self.assertNotIn("coordinateFallback", serialized)
        self.assertNotIn("boundingRect", serialized)
        self.assertNotIn('"coordinate"', serialized)
        self.assertNotIn("x=842", serialized)
        self.assertNotIn("x=911", serialized)

    def test_render_task_prompt_is_semantic_first(self):
        rendered = self.mod.render_task_prompt(
            self.task_template,
            self.sample_knowledge,
            self.output_schema,
        )

        self.assertIn("button:Pull requests", rendered)
        self.assertIn("link:Issues", rendered)
        self.assertIn('"coordinatesIncluded": false', rendered)
        self.assertNotIn("coordinate:842,516", rendered)
        self.assertNotIn("x=842", rendered)
        self.assertNotIn("coordinateFallback", rendered)
        self.assertNotIn("boundingRect", rendered)


if __name__ == "__main__":
    unittest.main()
