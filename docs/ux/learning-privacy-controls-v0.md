# Learning Privacy Controls v0

## 目标

让老师在不退出当前工作流的前提下，直接控制 learning capture 的隐私边界，并且让这些规则真正作用到落盘链路。

## 本次落地范围

- 状态工作台新增 `Privacy / Exclusion Panel`
- 支持：
  - app 排除名单
  - 窗口标题排除规则
  - `15` 分钟临时暂停
  - 敏感场景自动静默
- 敏感场景第一版覆盖：
  - 密码输入 / 登录验证
  - 支付 / 付款
  - 隐私授权 / 系统权限
  - 医疗 / 健康信息
  - 金融 / 账单信息

## 面板交互

### App 排除名单

- 支持一键把当前前台 app 加入排除
- 支持手动录入 `bundle id` 与 `appName`
- OpenStaff 自身界面始终自动排除，不需要额外配置

### 窗口标题排除规则

- 支持 `contains` 与 `regex` 两种匹配方式
- 支持直接用当前窗口标题生成规则
- 命中窗口标题规则后，learning 状态显示为 `excluded`

### 15 分钟临时暂停

- 点击后立即停止 learning capture
- 计时结束后自动恢复 capture
- 手动点击 `恢复学习` 或面板中的 `立即恢复` 可提前解除
- 保留原采集会话 ID，不创建新的 session

### 敏感场景自动静默

- 默认开启
- 可整体关闭，也可按敏感类别逐项关闭
- 命中后 learning 状态显示为 `sensitive-muted`
- 命中期间不会继续生成 raw event learning 工件

## 数据与配置

- 示例配置文件：
  - `config/learning-privacy.example.yaml`
- 运行时默认持久化路径：
  - `data/runtime/learning-privacy.json`
- 若存在 `config/learning-privacy.yaml`，桌面 App 优先读写该文件
- 可用 `OPENSTAFF_LEARNING_PRIVACY_PATH` 覆盖配置路径
- 文件继续使用 JSON-compatible YAML，方便 Swift 侧直接 `Codable` 读写

## 生效优先级

从高到低：

1. 当前模式未开启学习采集
2. 老师手动暂停
3. `15` 分钟临时暂停
4. app / 窗口标题排除
5. 敏感场景自动静默
6. learning `on`

## 代码落点

- `apps/macos/Sources/OpenStaffApp/LearningPrivacyPanel.swift`
- `apps/macos/Sources/OpenStaffApp/LearningPrivacySupport.swift`
- `apps/macos/Sources/OpenStaffApp/LearningStatusSupport.swift`
- `core/learning/SensitiveScenePolicy.swift`
- `core/learning/LearningSessionState.swift`

## 验收对照

- app 排除命中后 capture 停止，学习状态切到 `excluded`
- 窗口标题排除命中后 capture 停止，学习状态切到 `excluded`
- 临时暂停开始后 capture 停止，到期自动恢复
- 敏感场景命中后 capture 停止，学习状态切到 `sensitive-muted`
- `LearningStatusSurfaceTests` 已覆盖：
  - 手动暂停 / 恢复
  - OpenStaff 自排除
  - 窗口标题排除
  - 敏感场景静默
  - 敏感场景关闭后恢复采集
  - `15` 分钟临时暂停自动恢复

## 当前边界

- v0 仍以窗口标题 / app bundle 级规则为主，尚未接入 DOM、OCR 字段级脱敏
- `capture-policy-violation-count = 0` 目前由自动化回归样本保证，真实试点仍需继续观测
