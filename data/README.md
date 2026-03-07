# data/

Local-only runtime data for development and demos.

- `raw-events/`: append-only JSONL event stream (`{yyyy-mm-dd}/{sessionId}.jsonl` + rotated segments).
- `task-chunks/`: intermediate TaskChunk files (`{yyyy-mm-dd}/{taskId}.json`).
- `knowledge/`: final KnowledgeItem files (`{yyyy-mm-dd}/{taskId}.json`).
- `logs/`: runtime and execution logs.
- `feedback/`: teacher feedback records (`{yyyy-mm-dd}/{sessionId}-{taskId}-teacher-feedback.jsonl`).

This directory is the default storage root in baseline mode.
