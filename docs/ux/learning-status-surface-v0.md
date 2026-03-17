# Learning Status Surface v0

## 目标

让老师在 `1` 次视线切换内知道 OpenStaff 是否正在学习，并且在 `1` 次点击内完成暂停 / 恢复。

## 本次落地范围

- 菜单栏顶部增加 `Learning Status Surface`
- 桌面悬浮部件增加学习状态卡
- 首页与状态工作台同步显示同一套学习状态卡
- 提供一键 `暂停学习` / `恢复学习`
- 显示：
  - 当前模式
  - 当前 app
  - 当前窗口标题（有权限时）
  - learning `on / paused / excluded / sensitive-muted`
  - 最近一次成功落盘时间
  - 当前采集会话与累计事件数

## v0 状态语义

### `on`

- 当前运行模式具备 `observeTeacherActions`
- 老师没有手动暂停
- 当前 app 不在排除名单
- 当前窗口没有命中敏感场景
- 采集器正在运行

### `paused`

- 当前模式未开启学习采集，或
- 老师手动暂停了学习

### `excluded`

- 当前前台 app 命中排除规则
- v0 内建规则至少包含 `OpenStaff` 自身界面
- 预留 `OPENSTAFF_LEARNING_EXCLUDED_BUNDLE_IDS` 环境变量做临时扩展

### `sensitive-muted`

- 当前窗口命中敏感场景，自动静默学习
- v0 复用现有安全规则中的敏感窗口定义：
  - 支付 / 结账
  - 系统设置 / 隐私授权
  - 密码管理器 / 钥匙串
  - 隐私权限弹窗

## 交互约定

- 菜单栏中始终显示学习状态摘要，并提供独立的 `暂停学习 / 恢复学习` 菜单项
- 悬浮部件中的学习状态卡直接提供按钮，保证一键暂停 / 恢复
- 手动暂停时：
  - 不停止当前模式
  - 仅停止学习采集
  - 保留当前采集会话 ID
  - 保留当前累计事件数
- 恢复时：
  - 继续写入同一采集会话
  - 事件计数按累计值继续增长

## 数据实现

- `core/learning/LearningSessionState.swift`
  - 定义学习状态、前台 app 上下文、规则命中、状态解析器
- `apps/macos/Sources/OpenStaffApp/LearningStatusSupport.swift`
  - 前台 app 快照、最近落盘时间扫描、排除 / 敏感规则匹配
- `apps/macos/Sources/OpenStaffApp/LearningStatusSurface.swift`
  - 统一状态卡 UI

## 当前已知边界

- v0 还没有完整的隐私 / 排除面板，详细配置放到 `TODO 11.0.3`
- 当前排除规则以内建默认值和环境变量扩展为主
- `swift test` 在当前 CLI 环境下受 `XCTest` 模块缺失影响，已用 `swift build` 验证应用可编译

## 验收对照

- 老师可在菜单栏、悬浮部件、首页、状态工作台直接看到学习状态
- 暂停 / 恢复都是单击完成
- 前台切到 OpenStaff 自身界面时显示 `excluded`
- 前台切到敏感窗口时显示 `sensitive-muted`
- 成功采集后会更新最近落盘时间
