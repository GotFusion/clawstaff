SHELL := /bin/zsh
APP_PACKAGE_PATH := apps/macos
APP_TARGET := OpenStaffApp
CAPTURE_TARGET := OpenStaffCaptureCLI
SLICE_TARGET := OpenStaffTaskSlicerCLI
KNOWLEDGE_TARGET := OpenStaffKnowledgeBuilderCLI
ORCHESTRATOR_TARGET := OpenStaffOrchestratorCLI
ASSIST_TARGET := OpenStaffAssistCLI
REPLAY_VERIFY_TARGET := OpenStaffReplayVerifyCLI
REVIEW_TARGET := OpenStaffExecutionReviewCLI
PREFERENCE_PROFILE_TARGET := OpenStaffPreferenceProfileCLI
OPENCLAW_TARGET := OpenStaffOpenClawCLI
STUDENT_TARGET := OpenStaffStudentCLI
PREFERENCE_BENCHMARK_ROOT ?= data/benchmarks/personal-preference
PREFERENCE_BENCHMARK_MANIFEST ?= $(PREFERENCE_BENCHMARK_ROOT)/manifest.json
SEMANTIC_ACTION_E2E_BENCHMARK_ROOT ?= data/benchmarks/semantic-action-e2e
SEMANTIC_ACTION_E2E_BENCHMARK_MANIFEST ?= $(SEMANTIC_ACTION_E2E_BENCHMARK_ROOT)/manifest.json
SEMANTIC_ACTION_E2E_METRICS_CONFIG ?= $(SEMANTIC_ACTION_E2E_BENCHMARK_ROOT)/metrics-v0.json
SEMANTIC_ACTION_E2E_METRICS_SUMMARY ?= $(SEMANTIC_ACTION_E2E_BENCHMARK_ROOT)/metrics-summary.json
SEMANTIC_ACTION_E2E_REPEAT_COUNT ?= 1
SEMANTIC_ACTION_E2E_PREFLIGHT_REPEAT_COUNT ?= 3
SEMANTIC_ACTION_DB ?= data/semantic-actions/semantic-actions.sqlite
SEMANTIC_ACTION_OBSERVABILITY_CONFIG ?= config/semantic-action-observability.v0.json
SEMANTIC_ACTION_OBSERVABILITY_OUTPUT ?= data/reports/semantic-action-observability/metrics-summary.json
SEMANTIC_ACTION_OBSERVABILITY_DASHBOARD ?= data/reports/semantic-action-observability/dashboard.md
SWIFT_WRAPPER := ./scripts/dev/with_xcode_env.sh
SWIFT := $(SWIFT_WRAPPER) swift
ARGS ?=

.PHONY: build dev xcode-open capture slice knowledge orchestrator assist replay-verify review preference-profile learning-bundle-export learning-bundle-verify learning-bundle-restore semantic-actions-build semantic-actions-migrate semantic-observability-dashboard semantic-observability-gates openclaw student llm-prompts llm-validate llm-call llm-retry skill-build skills-sample skills-validate-sample validate-raw-events validate-knowledge validate-replay-sample validate-semantic-guard benchmark-personal benchmark-semantic-e2e benchmark-semantic-e2e-gates benchmark-semantic-e2e-preflight benchmark-preference benchmark-preference-gates benchmark-preference-preflight test-swift test test-unit test-integration test-e2e release-regression release-preflight

build:
	$(SWIFT) build --package-path $(APP_PACKAGE_PATH)

dev:
	$(SWIFT) build --package-path $(APP_PACKAGE_PATH) --product $(APP_TARGET)
	"$$($(SWIFT) build --package-path $(APP_PACKAGE_PATH) --show-bin-path)/$(APP_TARGET)"

xcode-open:
	./scripts/dev/open_xcode_workspace.sh

capture:
	$(SWIFT) run --package-path $(APP_PACKAGE_PATH) $(CAPTURE_TARGET) $(ARGS)

slice:
	$(SWIFT) run --package-path $(APP_PACKAGE_PATH) $(SLICE_TARGET) $(ARGS)

knowledge:
	$(SWIFT) run --package-path $(APP_PACKAGE_PATH) $(KNOWLEDGE_TARGET) $(ARGS)

orchestrator:
	$(SWIFT) run --package-path $(APP_PACKAGE_PATH) $(ORCHESTRATOR_TARGET) $(ARGS)

assist:
	$(SWIFT) run --package-path $(APP_PACKAGE_PATH) $(ASSIST_TARGET) $(ARGS)

replay-verify:
	$(SWIFT) run --package-path $(APP_PACKAGE_PATH) $(REPLAY_VERIFY_TARGET) $(ARGS)

review:
	$(SWIFT) run --package-path $(APP_PACKAGE_PATH) $(REVIEW_TARGET) $(ARGS)

preference-profile:
	$(SWIFT) run --package-path $(APP_PACKAGE_PATH) $(PREFERENCE_PROFILE_TARGET) $(ARGS)

learning-bundle-export:
	python3 scripts/learning/export_learning_bundle.py $(ARGS)

learning-bundle-verify:
	python3 scripts/learning/verify_learning_bundle.py $(ARGS)

learning-bundle-restore:
	python3 scripts/learning/verify_learning_bundle.py $(ARGS)

semantic-actions-build:
	python3 scripts/learning/build_semantic_actions.py $(ARGS)

semantic-actions-migrate:
	python3 scripts/learning/migrate_semantic_actions.py $(ARGS)

semantic-observability-dashboard:
	python3 scripts/observability/build_semantic_action_dashboard.py --db-path $(SEMANTIC_ACTION_DB) --config $(SEMANTIC_ACTION_OBSERVABILITY_CONFIG) --output $(SEMANTIC_ACTION_OBSERVABILITY_OUTPUT) --dashboard-output $(SEMANTIC_ACTION_OBSERVABILITY_DASHBOARD) $(ARGS)

semantic-observability-gates:
	python3 scripts/observability/build_semantic_action_dashboard.py --db-path $(SEMANTIC_ACTION_DB) --config $(SEMANTIC_ACTION_OBSERVABILITY_CONFIG) --output $(SEMANTIC_ACTION_OBSERVABILITY_OUTPUT) --dashboard-output $(SEMANTIC_ACTION_OBSERVABILITY_DASHBOARD) --check-gates $(ARGS)

openclaw:
	$(SWIFT) run --package-path $(APP_PACKAGE_PATH) $(OPENCLAW_TARGET) $(ARGS)

student:
	$(SWIFT) run --package-path $(APP_PACKAGE_PATH) $(STUDENT_TARGET) $(ARGS)

test-swift:
	$(SWIFT) test --package-path $(APP_PACKAGE_PATH) $(ARGS)

llm-prompts:
	python3 scripts/llm/render_knowledge_prompts.py --knowledge-item core/knowledge/examples/knowledge-item.sample.json --out-dir /tmp/openstaff-llm-prompts

llm-validate:
	python3 scripts/llm/validate_knowledge_parse_output.py --input scripts/llm/examples/knowledge-parse-output.sample.json --knowledge-item core/knowledge/examples/knowledge-item.sample.json

llm-call:
	python3 scripts/llm/chatgpt_adapter.py --provider text --knowledge-item core/knowledge/examples/knowledge-item.sample.json --output /tmp/openstaff-llm-call-output.json $(ARGS)

llm-retry:
	python3 scripts/llm/chatgpt_adapter.py --provider text --knowledge-item core/knowledge/examples/knowledge-item.sample.json --simulate-transient-failures 2 --max-retries 3 --output /tmp/openstaff-llm-retry-output.json $(ARGS)

skill-build:
	python3 scripts/skills/openclaw_skill_mapper.py --knowledge-item core/knowledge/examples/knowledge-item.sample.json --llm-output scripts/llm/examples/knowledge-parse-output.sample.json --skills-root /tmp/openstaff-skills --overwrite $(ARGS)

skills-sample:
	python3 scripts/skills/openclaw_skill_mapper.py --knowledge-item core/knowledge/examples/knowledge-item.sample.json --llm-output scripts/llm/examples/knowledge-parse-output.sample.json --skills-root /tmp/openstaff-skills-sample --overwrite
	python3 scripts/skills/openclaw_skill_mapper.py --knowledge-item scripts/skills/examples/knowledge-item.sample.finder.json --llm-output scripts/skills/examples/llm-output.sample.finder.json --skills-root /tmp/openstaff-skills-sample --overwrite
	python3 scripts/skills/openclaw_skill_mapper.py --knowledge-item scripts/skills/examples/knowledge-item.sample.terminal.json --llm-output scripts/skills/examples/llm-output.sample.terminal-invalid.txt --skills-root /tmp/openstaff-skills-sample --overwrite

skills-validate-sample: skills-sample
	python3 scripts/skills/validate_openclaw_skill.py --skill-dir /tmp/openstaff-skills-sample/openstaff-task-session-20260307-a1-001
	python3 scripts/skills/validate_openclaw_skill.py --skill-dir /tmp/openstaff-skills-sample/openstaff-task-session-20260307-b2-001
	python3 scripts/skills/validate_openclaw_skill.py --skill-dir /tmp/openstaff-skills-sample/openstaff-task-session-20260307-c3-001

validate-raw-events:
	python3 scripts/validation/validate_raw_event_logs.py --input data/raw-events --mode compat $(ARGS)

validate-knowledge:
	python3 scripts/validation/validate_knowledge_items.py --input data/knowledge --mode compat $(ARGS)

validate-replay-sample:
	python3 scripts/validation/run_replay_verify_check.py --knowledge core/knowledge/examples/knowledge-item.sample.json --snapshot core/executor/examples/replay-environment.sample.json $(ARGS)

validate-semantic-guard:
	python3 scripts/validation/guard_coordinate_execution.py $(ARGS)

benchmark-personal:
	python3 scripts/benchmarks/run_personal_desktop_benchmark.py $(ARGS)

benchmark-semantic-e2e:
	python3 scripts/benchmarks/run_semantic_action_e2e_benchmark.py --benchmark-root $(SEMANTIC_ACTION_E2E_BENCHMARK_ROOT) --report $(SEMANTIC_ACTION_E2E_BENCHMARK_MANIFEST) --repeat-count $(SEMANTIC_ACTION_E2E_REPEAT_COUNT) $(ARGS)

benchmark-semantic-e2e-gates:
	python3 scripts/benchmarks/aggregate_semantic_action_e2e_metrics.py --benchmark-root $(SEMANTIC_ACTION_E2E_BENCHMARK_ROOT) --manifest $(SEMANTIC_ACTION_E2E_BENCHMARK_MANIFEST) --config $(SEMANTIC_ACTION_E2E_METRICS_CONFIG) --output $(SEMANTIC_ACTION_E2E_METRICS_SUMMARY) --check-gates $(ARGS)

benchmark-semantic-e2e-preflight:
	python3 scripts/benchmarks/run_semantic_action_e2e_benchmark.py --benchmark-root $(SEMANTIC_ACTION_E2E_BENCHMARK_ROOT) --report $(SEMANTIC_ACTION_E2E_BENCHMARK_MANIFEST) --repeat-count $(SEMANTIC_ACTION_E2E_PREFLIGHT_REPEAT_COUNT) $(ARGS)
	python3 scripts/benchmarks/aggregate_semantic_action_e2e_metrics.py --benchmark-root $(SEMANTIC_ACTION_E2E_BENCHMARK_ROOT) --manifest $(SEMANTIC_ACTION_E2E_BENCHMARK_MANIFEST) --config $(SEMANTIC_ACTION_E2E_METRICS_CONFIG) --output $(SEMANTIC_ACTION_E2E_METRICS_SUMMARY) --check-gates

benchmark-preference:
	python3 scripts/benchmarks/run_personal_preference_benchmark.py $(ARGS)

benchmark-preference-gates:
	python3 scripts/benchmarks/aggregate_preference_metrics.py --benchmark-root $(PREFERENCE_BENCHMARK_ROOT) --manifest $(PREFERENCE_BENCHMARK_MANIFEST) --check-gates $(ARGS)

benchmark-preference-preflight:
	python3 scripts/benchmarks/run_personal_preference_benchmark.py --benchmark-root $(PREFERENCE_BENCHMARK_ROOT) --report $(PREFERENCE_BENCHMARK_MANIFEST) $(ARGS)
	python3 scripts/benchmarks/aggregate_preference_metrics.py --benchmark-root $(PREFERENCE_BENCHMARK_ROOT) --manifest $(PREFERENCE_BENCHMARK_MANIFEST) --check-gates

test:
	python3 scripts/tests/run_all.py --suite all

test-unit:
	python3 scripts/tests/run_all.py --suite unit

test-integration:
	python3 scripts/tests/run_all.py --suite integration

test-e2e:
	python3 scripts/tests/run_all.py --suite e2e

release-regression:
	python3 scripts/release/run_regression.py --suite all $(ARGS)

release-preflight:
	python3 scripts/release/run_regression.py --output-root /tmp/openstaff-release-preflight/regression --suite all $(ARGS)
