# ADR-0022 Learning Bundle Export And Restore

## Status

Accepted

## Context

Phase 11 在 `turn / evidence / signal / rule / profile / audit` 都已经存在后，仍缺一个可迁移资产层：

- 这些对象无法被稳定打包交付。
- 外部 worker 很难在不直接读内部目录的前提下复用学习结果。
- 出问题后也缺少“先预览、再恢复”的安全恢复流程。

如果没有 learning bundle，偏好学习链路虽然能在单机仓库内运行，但还不具备：

1. 可移植性
2. 可校验性
3. 可恢复性

## Decision

采用 `directory bundle + manifest + verification report` 作为 v0 方案。

### v0 打包对象

只纳入：

- `turns`
- `evidence`
- `signals`
- `rules`
- `profiles`
- `audit`

### v0 恢复策略

- 恢复前必须先做 verify。
- restore 默认只做 dry-run 预览。
- 只有显式 `--apply` 才允许写盘。
- 默认不覆盖已有文件，冲突时中止；需显式 `--overwrite` 才覆盖。

### v0 结构选择

采用“目录型 bundle”，而不是压缩包或数据库快照。

原因：

1. 目录结构更容易直接审阅与 diff。
2. `manifest.json` 可直接承载 restore 路径与 checksum。
3. 后续若要做压缩分发，可以在外层再套 tar/zip，不影响内部协议。

## Why Not Include Assembly In v0

`PolicyAssemblyDecision` 很有价值，但它更偏运行时解释和 drift 监控辅助事实源。

v0 不纳入 `assembly`，原因是：

1. 当前 TODO 的最小闭环是 learning 资产迁移，而不是解释层完整迁移。
2. `profile rebuild` 只依赖 `rules`，不依赖 `assembly`。
3. 先把恢复边界压到最核心 6 类对象，更容易保证稳定与测试覆盖。

后续如要扩展到 `assembly`，应作为 v1 增量字段，不破坏 v0 manifest。

## Consequences

正向结果：

- 学习层第一次具备“可导出、可校验、可恢复”的统一资产协议。
- 恢复流程默认更安全，因为先 dry-run 再 apply。
- Bundle 可作为后续 gateway / hook 的稳定传输边界。

代价与限制：

- v0 仍不恢复信号索引与规则索引，只恢复原始 payload 与 `profiles/latest.json`。
- audit 文件在过滤导出时允许被裁切，因此 verify 对 audit 缺失关联只给 warning。
- 不包含 screenshot / AX / OCR 等重资产，仍需通过 `observationRef` 回到原始来源。

## Follow-Up

- 在 v1 评估是否纳入 `assembly`。
- 视 bundle 体积与流转方式，增加可选的 tar/zip 封装。
- 为外部 worker / gateway 暴露 `preferences.exportBundle` 标准接口。
