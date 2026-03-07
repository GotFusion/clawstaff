# apps/macos/

macOS GUI shell built with SwiftUI (Phase 0 baseline).

## Run

From repository root:

```bash
make dev
make capture
make slice
```

## Build

```bash
make build
```

## Layout

- `Package.swift`: Swift package entry for macOS app shell.
- `Sources/OpenStaffApp/OpenStaffApp.swift`: minimal window for baseline validation.
- `Sources/OpenStaffCaptureCLI/`: Phase 1.3 capture CLI (permission check, click capture, context snapshot, JSONL persistence + rotation).
- `Sources/OpenStaffTaskSlicerCLI/`: Phase 2.1 task slicer CLI (session events -> TaskChunk files).

## Capture CLI

```bash
# Start capture with auto-stop at 20 events
make capture ARGS="--max-events 20"

# Print RawEvent JSONL lines
make capture ARGS="--json --max-events 20"

# Configure output root and rotation policy
make capture ARGS="--output-dir data/raw-events --rotate-max-bytes 1048576 --rotate-max-seconds 1800"
```

If accessibility permission is missing, CLI prints a clear error and points to:
`System Settings > Privacy & Security > Accessibility`.

Captured raw events are stored under:
- `data/raw-events/{yyyy-mm-dd}/{sessionId}.jsonl`
- `data/raw-events/{yyyy-mm-dd}/{sessionId}-r0001.jsonl` ... (rotation)

## Task Slicer CLI

```bash
# Slice one session into task chunks
make slice ARGS="--session-id session-20260307-a1 --date 2026-03-07"

# Adjust idle threshold and print generated TaskChunk JSON lines
make slice ARGS="--session-id session-20260307-a1 --idle-gap-seconds 30 --json"
```

Task chunks are written to:
- `data/knowledge/{yyyy-mm-dd}/{taskId}.json`

## Planned Features

- Three-mode switcher: teaching / assist / student.
- Capture status panel and permissions state.
- Knowledge and execution log review panels.
- Assist confirmation prompt and emergency stop controls.
