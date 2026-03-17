import SwiftUI

struct LearningStatusSurfaceCard: View {
    let state: LearningSessionState
    let modeDisplayName: String
    let actionTitle: String
    let actionEnabled: Bool
    let onAction: () -> Void
    var showsActionButton = true
    var showsBackground = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                LearningStatusBadge(status: state.status)
                VStack(alignment: .leading, spacing: 3) {
                    Text(modeDisplayName)
                        .font(.headline)
                    Text(state.statusReason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 8) {
                LearningStatusDetailRow(
                    title: "当前 app",
                    value: currentAppText
                )

                if let windowTitle = state.currentApp.windowTitle,
                   !windowTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    LearningStatusDetailRow(
                        title: "当前窗口",
                        value: windowTitle
                    )
                }

                LearningStatusDetailRow(
                    title: "最近落盘",
                    value: lastWriteText
                )

                LearningStatusDetailRow(
                    title: "会话 / 事件",
                    value: sessionAndEventText
                )
            }

            if showsActionButton {
                Button(actionTitle, action: onAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!actionEnabled)
                    .tint(LearningStatusPalette.accentColor(for: state.status))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(backgroundView)
    }

    private var currentAppText: String {
        let bundleId = state.currentApp.appBundleId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !bundleId.isEmpty, bundleId != "unknown.bundle.id" else {
            return state.currentApp.appName
        }
        return "\(state.currentApp.appName) (\(bundleId))"
    }

    private var lastWriteText: String {
        guard let lastWriteAt = state.lastSuccessfulWriteAt else {
            return "暂无成功落盘"
        }
        return OpenStaffDateFormatter.displayString(from: lastWriteAt)
    }

    private var sessionAndEventText: String {
        let sessionId = state.activeSessionId ?? "未运行"
        return "\(sessionId) · \(state.capturedEventCount)"
    }

    @ViewBuilder
    private var backgroundView: some View {
        if showsBackground {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(LearningStatusPalette.backgroundFill(for: state.status))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(LearningStatusPalette.borderColor(for: state.status), lineWidth: 1)
                )
        } else {
            Color.clear
        }
    }
}

private struct LearningStatusDetailRow: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct LearningStatusBadge: View {
    let status: LearningActivityStatus

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(LearningStatusPalette.badgeFill(for: status))
            )
            .foregroundStyle(LearningStatusPalette.badgeText(for: status))
    }

    private var title: String {
        switch status {
        case .on:
            return "learning on"
        case .paused:
            return "paused"
        case .excluded:
            return "excluded"
        case .sensitiveMuted:
            return "sensitive-muted"
        }
    }
}

private enum LearningStatusPalette {
    static func accentColor(for status: LearningActivityStatus) -> Color {
        switch status {
        case .on:
            return Color(red: 0.17, green: 0.56, blue: 0.31)
        case .paused:
            return Color(red: 0.77, green: 0.52, blue: 0.08)
        case .excluded:
            return Color(red: 0.34, green: 0.39, blue: 0.47)
        case .sensitiveMuted:
            return Color(red: 0.70, green: 0.14, blue: 0.14)
        }
    }

    static func badgeFill(for status: LearningActivityStatus) -> Color {
        accentColor(for: status).opacity(0.18)
    }

    static func badgeText(for status: LearningActivityStatus) -> Color {
        accentColor(for: status)
    }

    static func backgroundFill(for status: LearningActivityStatus) -> Color {
        accentColor(for: status).opacity(0.08)
    }

    static func borderColor(for status: LearningActivityStatus) -> Color {
        accentColor(for: status).opacity(0.22)
    }
}
