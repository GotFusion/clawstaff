SHELL := /bin/zsh
APP_PACKAGE_PATH := apps/macos
APP_TARGET := OpenStaffApp
CAPTURE_TARGET := OpenStaffCaptureCLI
SLICE_TARGET := OpenStaffTaskSlicerCLI
KNOWLEDGE_TARGET := OpenStaffKnowledgeBuilderCLI
ORCHESTRATOR_TARGET := OpenStaffOrchestratorCLI
ASSIST_TARGET := OpenStaffAssistCLI
ARGS ?=

.PHONY: build dev capture slice knowledge orchestrator assist llm-prompts llm-validate llm-call llm-retry-demo skill-build skills-demo skills-validate-demo

build:
	swift build --package-path $(APP_PACKAGE_PATH)

dev:
	swift run --package-path $(APP_PACKAGE_PATH) $(APP_TARGET)

capture:
	swift run --package-path $(APP_PACKAGE_PATH) $(CAPTURE_TARGET) $(ARGS)

slice:
	swift run --package-path $(APP_PACKAGE_PATH) $(SLICE_TARGET) $(ARGS)

knowledge:
	swift run --package-path $(APP_PACKAGE_PATH) $(KNOWLEDGE_TARGET) $(ARGS)

orchestrator:
	swift run --package-path $(APP_PACKAGE_PATH) $(ORCHESTRATOR_TARGET) $(ARGS)

assist:
	swift run --package-path $(APP_PACKAGE_PATH) $(ASSIST_TARGET) $(ARGS)

llm-prompts:
	python3 scripts/llm/render_knowledge_prompts.py --knowledge-item core/knowledge/examples/knowledge-item.sample.json --out-dir /tmp/openstaff-llm-prompts

llm-validate:
	python3 scripts/llm/validate_knowledge_parse_output.py --input scripts/llm/examples/knowledge-parse-output.sample.json --knowledge-item core/knowledge/examples/knowledge-item.sample.json

llm-call:
	python3 scripts/llm/chatgpt_adapter.py --provider text --knowledge-item core/knowledge/examples/knowledge-item.sample.json --output /tmp/openstaff-llm-call-output.json $(ARGS)

llm-retry-demo:
	python3 scripts/llm/chatgpt_adapter.py --provider text --knowledge-item core/knowledge/examples/knowledge-item.sample.json --simulate-transient-failures 2 --max-retries 3 --output /tmp/openstaff-llm-retry-demo-output.json $(ARGS)

skill-build:
	python3 scripts/skills/openclaw_skill_mapper.py --knowledge-item core/knowledge/examples/knowledge-item.sample.json --llm-output scripts/llm/examples/knowledge-parse-output.sample.json --skills-root /tmp/openstaff-skills --overwrite $(ARGS)

skills-demo:
	python3 scripts/skills/openclaw_skill_mapper.py --knowledge-item core/knowledge/examples/knowledge-item.sample.json --llm-output scripts/llm/examples/knowledge-parse-output.sample.json --skills-root /tmp/openstaff-skills-demo --overwrite
	python3 scripts/skills/openclaw_skill_mapper.py --knowledge-item scripts/skills/examples/knowledge-item.sample.finder.json --llm-output scripts/skills/examples/llm-output.sample.finder.json --skills-root /tmp/openstaff-skills-demo --overwrite
	python3 scripts/skills/openclaw_skill_mapper.py --knowledge-item scripts/skills/examples/knowledge-item.sample.terminal.json --llm-output scripts/skills/examples/llm-output.sample.terminal-invalid.txt --skills-root /tmp/openstaff-skills-demo --overwrite

skills-validate-demo: skills-demo
	python3 scripts/skills/validate_openclaw_skill.py --skill-dir /tmp/openstaff-skills-demo/openstaff-task-session-20260307-a1-001
	python3 scripts/skills/validate_openclaw_skill.py --skill-dir /tmp/openstaff-skills-demo/openstaff-task-session-20260307-b2-001
	python3 scripts/skills/validate_openclaw_skill.py --skill-dir /tmp/openstaff-skills-demo/openstaff-task-session-20260307-c3-001
