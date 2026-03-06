# apps/macos/

macOS GUI shell built with SwiftUI (Phase 0 baseline).

## Run

From repository root:

```bash
make dev
make capture
```

## Build

```bash
make build
```

## Layout

- `Package.swift`: Swift package entry for macOS app shell.
- `Sources/OpenStaffApp/OpenStaffApp.swift`: minimal window for baseline validation.
- `Sources/OpenStaffCaptureCLI/`: Phase 1.2 capture CLI (permission check, click capture, context snapshot, local queue).

## Capture CLI

```bash
# Start capture with auto-stop at 20 events
make capture ARGS="--max-events 20"

# Print RawEvent JSONL lines
make capture ARGS="--json --max-events 20"
```

If accessibility permission is missing, CLI prints a clear error and points to:
`System Settings > Privacy & Security > Accessibility`.

## Planned Features

- Three-mode switcher: teaching / assist / student.
- Capture status panel and permissions state.
- Knowledge and execution log review panels.
- Assist confirmation prompt and emergency stop controls.
