# Capture Engine v0（TODO 1.2）

## 1. 范围

当前实现为最小 CLI 采集器：`OpenStaffCaptureCLI`。

能力覆盖：
- 辅助功能权限检查。
- 全局鼠标点击监听（左键/右键，双击识别）。
- 前台应用与窗口标题采集。
- 原始事件写入本地内存队列（进程内）。

## 2. 运行方式

仓库根目录执行：

```bash
make capture
```

常用参数：

```bash
# 捕获 20 条后自动停止（用于验收）
make capture ARGS="--max-events 20"

# 输出 JSONL 行
make capture ARGS="--json --max-events 20"
```

## 3. 权限策略

启动时执行 Accessibility 权限检查：
- 未授权时返回 `CAP-PERMISSION-DENIED`，并输出系统设置指引。
- 可通过 `--no-permission-prompt` 禁止弹出系统授权提示。

## 4. 输出行为

- 默认输出人类可读日志（包含点击类型、前台 app、窗口标题、坐标、队列计数）。
- `--json` 输出 `RawEvent` JSON 行，字段与 `capture.raw.v0` 对齐。

## 5. 已知限制

- 当前仅内存队列，不落盘。
- 当前仅鼠标点击，不采集键盘文本输入。
- 窗口 ID 依赖 AX 属性，部分应用可能为空。

## 6. 下一步（TODO 1.3）

1. 将队列事件追加写入 `data/raw-events/{date}/{sessionId}.jsonl`。
2. 增加文件轮转（按大小阈值）与中断恢复。
3. 将 schema 校验接入写盘前检查。
