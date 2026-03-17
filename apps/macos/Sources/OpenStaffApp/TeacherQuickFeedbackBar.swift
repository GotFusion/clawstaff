import SwiftUI

struct TeacherQuickFeedbackBar: View {
    let actions: [TeacherQuickFeedbackAction]
    @Binding var note: String
    let statusMessage: String?
    let statusSucceeded: Bool
    let disabledReason: (TeacherQuickFeedbackAction) -> String?
    let onSubmit: (TeacherQuickFeedbackAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 112), spacing: 8)], spacing: 8) {
                ForEach(actions) { action in
                    let unavailableReason = disabledReason(action)
                    actionButton(for: action, unavailableReason: unavailableReason)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("短备注（可选）")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField(
                    "失败线索、风险原因、示教意图",
                    text: $note,
                    axis: .vertical
                )
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...3)
            }

            if let statusMessage, !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(statusSucceeded ? .green : .red)
            }
        }
    }

    @ViewBuilder
    private func actionButton(
        for action: TeacherQuickFeedbackAction,
        unavailableReason: String?
    ) -> some View {
        let baseButton = Button {
            onSubmit(action)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(action.displayName)
                    .font(.callout.weight(.semibold))
                Text(action.shortcut.displayLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .tint(TeacherQuickFeedbackPalette.tintColor(for: action))
        .disabled(unavailableReason != nil)
        .help(unavailableReason ?? action.hintText)
        .keyboardShortcut(
            action.shortcut.keyEquivalent,
            modifiers: action.shortcut.eventModifiers
        )

        switch action {
        case .approved, .tooDangerous:
            baseButton.buttonStyle(.borderedProminent)
        case .rejected, .needsRevision, .fixLocator, .reteach, .wrongOrder, .wrongStyle:
            baseButton.buttonStyle(.bordered)
        }
    }
}

private enum TeacherQuickFeedbackPalette {
    static func tintColor(for action: TeacherQuickFeedbackAction) -> Color {
        switch action {
        case .approved:
            return Color(red: 0.16, green: 0.56, blue: 0.28)
        case .rejected:
            return Color(red: 0.47, green: 0.47, blue: 0.50)
        case .needsRevision, .fixLocator, .reteach:
            return Color(red: 0.07, green: 0.40, blue: 0.82)
        case .tooDangerous:
            return Color(red: 0.75, green: 0.15, blue: 0.12)
        case .wrongOrder:
            return Color(red: 0.88, green: 0.47, blue: 0.10)
        case .wrongStyle:
            return Color(red: 0.62, green: 0.35, blue: 0.13)
        }
    }
}

private extension TeacherQuickFeedbackShortcut {
    var keyEquivalent: KeyEquivalent {
        KeyEquivalent(key.first ?? "1")
    }

    var eventModifiers: EventModifiers {
        modifiers.reduce(into: EventModifiers()) { partialResult, modifier in
            switch modifier {
            case .command:
                partialResult.insert(.command)
            case .shift:
                partialResult.insert(.shift)
            case .option:
                partialResult.insert(.option)
            case .control:
                partialResult.insert(.control)
            }
        }
    }
}
