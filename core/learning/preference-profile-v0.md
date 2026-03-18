# PreferenceProfile v0

`PreferenceProfile` 表示“当前这一刻真正会被下游消费的偏好快照”，而 `PreferenceProfileSnapshot` 是这个快照的持久化版本。

## 区分

- `PreferenceProfile`
  - 运行时聚合结果。
  - 只回答“现在有哪些规则在生效、会影响哪些模块”。
- `PreferenceProfileSnapshot`
  - 落盘工件。
  - 额外记录 `sourceRuleIds`、`createdAt`、`previousProfileVersion` 和备注，便于审计与回滚。

## 最小字段

### PreferenceProfile

- `profileVersion`
- `activeRuleIds`
- `assistPreferences`
- `skillPreferences`
- `repairPreferences`
- `reviewPreferences`
- `plannerPreferences`
- `generatedAt`

### PreferenceProfileSnapshot

- `profileVersion`
- `profile`
- `sourceRuleIds`
- `createdAt`
- `previousProfileVersion`
- `note`

## 存储

- 快照文件：`data/preferences/profiles/{profileVersion}.json`
- 最新指针：`data/preferences/profiles/latest.json`

## v0 约束

- `PreferenceProfileSnapshot.profileVersion` 必须与内嵌 `PreferenceProfile.profileVersion` 一致。
- `activeRuleIds` 只应包含当前仍为 `active` 的规则。
- 五类 preferences 先都使用统一的 `PreferenceProfileDirective` 结构，具体模块化字段由后续 builder 再展开。
