# 语义动作迁移复盘（2026-03）

更新时间：2026-03-28

## 1. 目标回顾

本轮迁移的核心目标是把 OpenStaff 从“纯坐标回放”切到“语义捕获 + 语义执行”：
- 学习阶段保留坐标仅作 provenance。
- 执行阶段只允许语义 selector、上下文守卫和断言链路。
- 发布链路不再存在恢复坐标执行的开关。

## 2. 已完成里程碑

1. `SEM-001 ~ SEM-003`
   - 冻结 semantic-only 决策。
   - 建立语义动作独立存储。
   - 在 CI 中阻止新的坐标执行调用流回主干。
2. `SEM-101 ~ SEM-103`
   - 建成 action builder、selector extractor、drag 语义化。
3. `SEM-201 ~ SEM-203`
   - 建成 semantic executor、context guard、post-assertion。
4. `SEM-301 ~ SEM-303`
   - 完成历史任务回填、老师审核工作流、观测与指标看板。
5. `SEM-401 ~ SEM-402`
   - 建成 E2E benchmark、性能与鲁棒性 gate。
6. `SEM-501 ~ SEM-502`
   - 正式切流到 semantic-only。
   - 物理删除 App 内 legacy coordinate bridge 与 helper/XPC 通道。

## 3. 这次 SEM-502 真正清掉了什么

已删除：
- `OpenStaffActionExecutor`
- `OpenStaffExecutorXPCClient`
- `OpenStaffExecutorHelper`
- `OpenStaffExecutorShared`
- `OpenStaffExecutorHelper` 对应的 SwiftPM product / target

已替换：
- `LearnedSkillRunner` 不再在 App 内直接 synthesize 坐标输入，而是统一调 `OpenStaffOpenClawCLI`。
- App 内“已学技能回放”状态面板不再显示 helper/backend 切换，只保留 semantic-only CLI 运行时信息。
- `SEM-003` guard 从“冻结遗留计数”升级为“零白名单”。

## 4. 结果

正向结果：
- 仓库主链上不再有可执行坐标路径。
- 技能回放和学生模式执行统一到同一条 semantic-only 执行链。
- 静态守门、回归测试、用户手册和发布文档口径对齐。

保留但不执行的内容：
- `coordinateFallback`
- 历史 `coordinate:x,y`
- raw event pointer / bounds / benchmark 样本中的坐标事实

这些字段仍可用于：
- provenance
- 迁移诊断
- drift / review 解释
- benchmark 与样本回放分析

## 5. 剩余运营项

`SEM-501` 里的“全量后一周核心指标稳定”仍属于真实 prod 观测项，需继续按：
- `docs/semantic-only-cutover-runbook.md`
- `make semantic-observability-gates`
- `make benchmark-semantic-e2e-preflight`

完成发布后验收。
