# apps/macos/

macOS GUI + CLI package built with SwiftUI and Swift 6.

## Run

From repository root:

```bash
make dev
make capture
make slice
make knowledge
make replay-verify
make preference-profile
```

## Build

```bash
make build
make test-swift
```

仓库内所有 `make` 触发的 Swift 命令都会通过 `scripts/dev/with_xcode_env.sh` 自动检查当前 developer dir。
如果本机装有完整 Xcode 且 `xcode-select` 仍指向 `CommandLineTools`，wrapper 会自动注入：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
```

因此在这个仓库里运行 `make build`、`make dev`、`make test-swift` 时，不需要再手工处理 `XCTest` 缺失问题。

若你想直接手敲 `swift test`，可用：

```bash
./scripts/dev/with_xcode_env.sh swift test --package-path apps/macos
```

## Layout

- `Package.swift`: Swift package entry for macOS app shell.
- `Sources/OpenStaffApp/OpenStaffApp.swift`: Phase 6.1 dashboard UI（首页 + 状态工作台、模式切换、学习记录/审阅、安全控制）。
- `Sources/OpenStaffApp/OpenStaffHomeView.swift`: 首页视图（核心交互入口与三模式快捷操作）。
- `Sources/OpenStaffCaptureCLI/`: Phase 1.3 capture CLI (permission check, click capture, context snapshot, JSONL persistence + rotation).
- `Sources/OpenStaffTaskSlicerCLI/`: Phase 2.1 task slicer CLI (session events -> TaskChunk files).
- `Sources/OpenStaffKnowledgeBuilderCLI/`: Phase 2.2 knowledge builder CLI (TaskChunk -> KnowledgeItem).
- `Sources/OpenStaffReplayVerifyCLI/`: Phase 7.3 replay verify CLI (KnowledgeItem -> dry-run semantic resolution report).
- `Sources/OpenStaffPreferenceProfileCLI/`: Phase 11.3 preference profile CLI（当前偏好快照查看 / 重建 / 落盘）。

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
- `data/task-chunks/{yyyy-mm-dd}/{taskId}.json`

## Knowledge Builder CLI

```bash
# Build KnowledgeItem files from task chunks
make knowledge ARGS="--session-id session-20260307-a1 --date 2026-03-07"

# Print generated KnowledgeItem JSON lines (including summary)
make knowledge ARGS="--session-id session-20260307-a1 --json"
```

Knowledge items are written to:
- `data/knowledge/{yyyy-mm-dd}/{taskId}.json`

## Replay Verify CLI

```bash
# Verify sample knowledge against an offline snapshot
make replay-verify ARGS="--knowledge core/knowledge/examples/knowledge-item.sample.json --snapshot core/executor/examples/replay-environment.sample.json --json"

# Verify a real knowledge file against the current frontmost app/window
make replay-verify ARGS="--knowledge data/knowledge/2026-03-13/task-session-20260313-a1-001.json"
```

Exit code `2` means at least one step degraded to coordinate fallback or failed semantic resolution.

## Preference Profile CLI

```bash
# Rebuild and persist the latest preference profile snapshot
make preference-profile ARGS="--preferences-root data/preferences --rebuild --persist --json"

# Only inspect the latest stored snapshot
make preference-profile ARGS="--preferences-root data/preferences --json"
```

默认会读取 `data/preferences/rules/*.json` 中的 active 规则，并按 `assist / skill / repair / review / planner` 五个模块聚合当前快照。

## GUI Status (Phase 6.1)

- Three-mode switcher: `teaching / assist / student`（复用状态机守卫）。
- Current status card: 当前模式、状态码、能力白名单、未满足守卫信息。
- Permission status card: 辅助功能权限 + 数据目录可写性。
- Recent task panel: 汇总 `data/logs/**/*.log` 与 `data/knowledge/**/*.json`。
- Learning browser: 会话列表、任务列表、任务详情与知识条目（目标/摘要/约束/步骤）浏览。
- Review and feedback: 执行日志详情查看 + 老师反馈入口（通过/驳回/修正），并在存在最新 `data/preferences` profile 时显示偏好化审阅建议、推荐短备注与规则来源；反馈写入 `data/feedback/**/*.jsonl`。
- Safety controls: 紧急停止按钮、全局快捷键 `Cmd+Shift+.`、状态提示；执行层高风险动作拦截（关键词 + 正则）。
