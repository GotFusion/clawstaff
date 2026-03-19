# core/repair/

执行后 / 回放时的 skill 漂移检测与修复建议层。

## 当前实现
- `SkillDriftDetector.swift`
  - 对 `SkillBundlePayload` + 当前 `ReplayEnvironmentSnapshot` 做 dry-run 漂移检测。
  - 识别 `uiTextChanged / elementPositionChanged / windowStructureChanged / appVersionChanged` 等类型。
- `SkillRepairPlanner.swift`
  - 把漂移报告转换为 `updateSkillLocator / relocalize / reteachCurrentStep` 修复动作。
  - 输出建议的 `repairVersion`。
- `PreferenceAwareSkillRepairPlanner.swift`
  - 在默认 repair heuristics 之上装配 `PreferenceProfile.repairPreferences`。
  - 支持按“先修 locator / 先 replay / 重新示教”重排修复建议。
  - 输出 `appliedRuleIds`、动作级 `preferenceReason` 与 plan 级 `preferenceDecision`。

## 当前接入点
- `OpenStaffReplayVerifyCLI --skill-dir`
- `OpenStaffApp` 技能详情页中的“检测漂移”与修复动作按钮
