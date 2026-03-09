# OpenStaff 目标 UI 设计图（v1）

本目录是基于当前文档与已实现 SwiftUI 功能整理的目标界面设计稿。

## 设计稿清单

- `01-overview-dashboard.svg`：系统总览控制台（模式、权限、安全、最近任务、学习记录入口）
- `02-teaching-mode-workbench.svg`：教学模式工作台（事件采集、上下文、任务切片、知识草稿）
- `03-assist-mode-confirmation.svg`：辅助模式确认台（下一步预测、守卫检查、老师确认、执行审计）
- `04-student-mode-review.svg`：学生模式执行与审阅台（自动规划、执行日志、审阅报告、反馈入口）

## 对齐依据

- 产品三模式与闭环流程：`docs/project-plan-and-progress.md`
- GUI 阶段目标：`docs/implementation-todo-checklist.md`（阶段 5/6）
- 用户说明中的操作链路：`docs/user-manual.md`
- 当前实现代码：`apps/macos/Sources/OpenStaffApp/OpenStaffApp.swift`

## 说明

- 设计稿为 `SVG`，可直接在浏览器或设计工具中打开。
- 视觉方向采用“控制台 + 任务流”风格，强调三模式切换、执行安全、日志可审阅。
- 后续若要直接实现 SwiftUI，可按卡片分区逐块映射到现有 `GroupBox` 结构。
