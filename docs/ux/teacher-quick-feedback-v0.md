# Teacher Quick Feedback Bar v0

## 目标

让老师在审阅执行日志时，优先通过固定 quick actions 完成反馈，而不是依赖长文本备注。

## 本次落地范围

- 首页增加一块轻量 `Quick Feedback Bar`
- “状态工作台 -> 审阅与反馈” 中的日志详情改为统一 quick feedback 组件
- 第一版固定只支持 7 个动作：
  - `通过`
  - `驳回`
  - `修 locator`
  - `重示教`
  - `太危险`
  - `顺序不对`
  - `风格不对`
- 备注改为“可选短备注”，仅做失败线索、风险原因、示教意图补充
- 为所有动作保留统一快捷键定义：
  - `Cmd+1` `通过`
  - `Cmd+2` `驳回`
  - `Cmd+3` `修 locator`
  - `Cmd+4` `重示教`
  - `Cmd+5` `太危险`
  - `Cmd+6` `顺序不对`
  - `Cmd+7` `风格不对`

## 动作语义

### `通过`

- 表示老师认为当前执行结果可接受
- 落正向 `teacherReview` evidence

### `驳回`

- 表示结果不可接受，但暂不直接指定修复路径
- 落负向 `teacherReview` evidence

### `修 locator`

- 表示失败更像定位问题
- 会同时写入老师反馈和 repair request

### `重示教`

- 表示当前步骤本身应该重新示教
- 会同时写入老师反馈和 repair request

### `太危险`

- 表示当前执行触碰了老师的风险阈值
- 第一版只记录风险负反馈，不自动触发额外执行动作

### `顺序不对`

- 表示步骤顺序不符合老师习惯或任务要求

### `风格不对`

- 表示动作风格、交互节奏、话术或软件使用习惯不符合老师偏好

## 数据实现

- 契约：`core/contracts/TeacherQuickFeedbackContracts.swift`
- UI：`apps/macos/Sources/OpenStaffApp/TeacherQuickFeedbackBar.swift`
- 存储：`data/feedback/{yyyy-mm-dd}/{sessionId}-{taskId}-teacher-feedback.jsonl`

每条反馈继续保留原有老师反馈字段，同时新增标准化 `teacherReview` evidence：

- `source = teacherReview`
- `action`
- `evidenceType = evaluative | directive`
- `category`
- `polarity`
- `summary`
- `note`
- `shortcut`
- `shortcutId`
- `repairActionType`

当前反馈记录 schema 升级为 `teacher.feedback.v2`，向后兼容旧版 `teacher.feedback.v1` 读取。

## 交互约定

- 默认针对当前选中的执行日志
- 若未关联可修复 skill，则 `修 locator` / `重示教` 自动禁用
- 备注不再要求长段说明，短句即可
- 按钮 hover 时显示动作说明或禁用原因

## 当前已知边界

- quick feedback 运行时仍先以内嵌 `teacherReview` evidence 的 `teacher.feedback.v2` 为主；Phase 11 已补齐独立 `NextStateEvidence` schema 与离线回填，可把已关联的 turn 写到 `data/learning/evidence/*`
- `太危险` 目前只记录负反馈，不会自动联动 `紧急停止`
- 首页默认绑定当前选中的最新日志；批量审阅仍建议在“状态工作台”完成

## 验收对照

- 7 个固定 quick actions 已落地
- 所有 quick actions 都会生成标准化 `teacherReview` evidence
- 快评只要求可选短备注
- 快捷键定义已统一，可被后续更多表面复用
