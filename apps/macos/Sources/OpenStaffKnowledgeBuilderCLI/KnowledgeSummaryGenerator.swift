import Foundation

struct KnowledgeSummaryGenerator {
    func generate(from chunk: TaskChunk, steps: [KnowledgeStep]) -> String {
        let appName = chunk.primaryContext.appName
        let windowTitle = chunk.primaryContext.windowTitle ?? "未知窗口"
        let stepChain = buildStepChain(steps)
        let boundary = boundaryText(chunk.boundaryReason)

        return "在\(appName)（\(windowTitle)）中，步骤摘要：\(stepChain)。共 \(chunk.eventCount) 步，任务分段原因：\(boundary)。"
    }

    private func buildStepChain(_ steps: [KnowledgeStep]) -> String {
        guard !steps.isEmpty else {
            return "无可回放步骤"
        }

        return steps.map(actionPhrase(from:)).joined(separator: " -> ")
    }

    private func actionPhrase(from step: KnowledgeStep) -> String {
        let instruction = step.instruction

        if instruction.contains("打开") {
            return "打开"
        }
        if instruction.contains("点击") {
            return "点击"
        }
        if instruction.contains("输入") {
            return "输入"
        }
        if instruction.contains("快捷键") {
            return "快捷键"
        }

        return "执行步骤"
    }

    private func boundaryText(_ reason: TaskBoundaryReason) -> String {
        switch reason {
        case .idleGap:
            return "空闲间隔切分"
        case .contextSwitch:
            return "上下文切换切分"
        case .sessionEnd:
            return "会话结束"
        }
    }
}
