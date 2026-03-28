# data/

Local-only runtime data for development and demos.

- `raw-events/`: append-only JSONL event stream (`{yyyy-mm-dd}/{sessionId}.jsonl` + rotated segments).
- `task-chunks/`: intermediate TaskChunk files (`{yyyy-mm-dd}/{taskId}.json`).
- `knowledge/`: final KnowledgeItem files (`{yyyy-mm-dd}/{taskId}.json`).
- `logs/`: runtime and execution logs.
- `feedback/`: teacher feedback records (`{yyyy-mm-dd}/{sessionId}-{taskId}-teacher-feedback.jsonl`), each line now embeds a normalized `teacherReview` evidence payload for quick feedback actions.
- `learning/`: derived learning artifacts, including `turns/{date}/{sessionId}/*.json` and `evidence/{date}/{sessionId}/*.jsonl`.
- `benchmarks/`: frozen regression corpora and generated benchmark artifacts (`personal-desktop/*`).
- `semantic-actions/`: SQLite semantic action store, teacher confirmation artifacts, and related execution diagnostics.
- `reports/`: generated review reports and observability outputs, including `semantic-action-observability/{metrics-summary.json,dashboard.md}`.

This directory is the default storage root in baseline mode.
