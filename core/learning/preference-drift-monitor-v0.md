# Preference Drift Monitor v0

## 目标

`PreferenceDriftMonitor` 用来回答一个简单但关键的问题：

- 哪些当前仍在生效的 `PreferenceRule`，已经开始偏离老师最近的真实行为？

它不直接改写规则，也不自动回滚；第一版只负责产出**可解释提醒**，供 CLI、GUI 审阅台和后续治理流程消费。

## 输入事实源

第一版只依赖已经落地的 4 类事实源：

1. `data/preferences/rules/*.json`
   - 当前规则本体、scope、risk level、更新时间。
2. `data/preferences/profiles/*.json`
   - 当前或指定 `PreferenceProfileSnapshot` 的 active rule 集合。
3. `data/preferences/audit/{date}.jsonl`
   - 老师是否显式驳回、撤销、覆盖某条规则。
4. `data/preferences/assembly/{date}/{module}/{sessionId}/*.json`
   - 规则最近是否仍被装配命中，还是经常被 suppress / override。

其中 `assembly` 日志仍受 `OPENSTAFF_ENABLE_POLICY_ASSEMBLY_LOG=1` feature flag 控制。

## 输出

`PreferenceDriftMonitorReport` 固定输出：

- `profileVersion`
- `activeRuleIds`
- `dataAvailability`
- `ruleStats`
- `findings`

每条 `finding` 都会带：

- `ruleId`
- `kind`
- `severity`
- `summary`
- `rationale`
- `metrics`
- `evidence`

## v0 检测规则

### 1. 长期不命中

触发条件：

- 有可用 `assembly` 日志
- 某条 active rule 最近 `30` 天未进入任何 `appliedRuleIds` 或 `suppressedRuleIds`

说明：

- 如果规则从未再次进入装配，会回退到 `rule.updatedAt` 计算静默天数。
- 这类 finding 表示“该规则可能已脱离当前工作流”，不是直接判定规则错误。

### 2. Override 率升高

触发条件：

- 有可用 `assembly` 日志
- 最近最多 `10` 次相关装配里，这条规则被 `suppressed` 的比例超过 `50%`
- 且相关装配次数至少为 `2`

说明：

- `suppressed` 表示规则仍被考虑，但最终没有被采用。
- 这比“完全没命中”更像“老师还在这个场景里工作，但现在更常走别的策略”。

### 3. 老师明确驳回

触发条件：

- 最近累计至少 `3` 条显式 rejection 信号

第一版把下面两类 audit 视为显式 rejection：

- `ruleRevoked / ruleSuperseded / ruleRolledBack`
- `source.kind=teacherAction` 或 `actor` 带 teacher 语义，且 `note / summary` 包含 `reject / 驳回 / 不再适用 / 风格不对 / 太危险` 等关键词

### 4. 风格偏好变化

适用范围：

- 仅对 `type=style` 的 active rule 生效

触发条件：

- 同一 scope 在最近 `30` 天出现不同 statement 的风格规则
- 或当前 style rule 最近收到了老师显式 rejection

说明：

- 这类 finding 更偏“偏好正在变化”，不是单纯 stale。

### 5. 高风险规则与当前行为不一致

适用范围：

- `riskLevel=high / critical`

触发条件：

- 最近 relevant decisions 中 override rate 超阈值
- 或该规则已收到老师显式 rejection

说明：

- 这类 finding 的优先级高于普通 stale / override，因为它意味着安全边界可能已经和老师当前真实意图脱节。

## 数据不可用时的降级

如果没有任何 `assembly` 日志：

- 不产出 `longTimeNoHit`
- 不产出 `overrideRateElevated`
- 不产出基于 usage 的 `highRiskBehaviorMismatch`
- 但仍允许基于 `audit` 产出：
  - `teacherRejectedRepeatedly`
  - `stylePreferenceChanged`

这样可以避免在未开启装配日志时，把所有规则都误报成 stale。

## CLI 入口

当前通过 `OpenStaffPreferenceProfileCLI` 暴露：

```bash
make preference-profile ARGS="--preferences-root data/preferences --drift-monitor --json"
```

可选参数：

- `--drift-profile-version <id>`：指定历史 snapshot 检查，而不是默认 latest。
- `--timestamp <iso8601>`：固定本次监控的观察时刻，便于回归测试和历史复盘。

## 后续扩展

v1 可继续补：

- 结合 `teacher.feedback.v2` 原始快评记录，区分“行为 override”和“明确 reject”
- 结合 `NextStateEvidence`、benchmark、repair plan，判断 rule drift 是来自 UI 变化还是老师偏好变化
- 将 finding 接到 GUI 审阅台和自动回滚建议入口
