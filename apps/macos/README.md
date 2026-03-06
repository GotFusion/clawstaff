# apps/macos/

macOS GUI shell built with SwiftUI (Phase 0 baseline).

## Run

From repository root:

```bash
make dev
```

## Build

```bash
make build
```

## Layout

- `Package.swift`: Swift package entry for macOS app shell.
- `Sources/OpenStaffApp/OpenStaffApp.swift`: minimal window for baseline validation.

## Planned Features

- Three-mode switcher: teaching / assist / student.
- Capture status panel and permissions state.
- Knowledge and execution log review panels.
- Assist confirmation prompt and emergency stop controls.
