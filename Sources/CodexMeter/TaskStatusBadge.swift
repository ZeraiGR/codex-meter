import SwiftUI

struct TaskStatusBadge:View {
    let status:String
    var interactive=false

    static func color(for status:String)->Color {
        switch status {
        case "active":return MeterTheme.inProgress
        case "completed":return MeterTheme.success
        case "ongoing":return MeterTheme.accent
        case "paused":return MeterTheme.warning
        case "failed":return MeterTheme.danger
        default:return MeterTheme.secondary
        }
    }
    static func background(for status:String)->Color {
        switch status {
        case "active":return MeterTheme.inProgressBackground
        case "completed":return MeterTheme.successBackground
        default:return MeterTheme.background
        }
    }
    private var symbol:String {
        switch status {
        case "active":return "play.circle.fill"
        case "completed":return "checkmark.circle.fill"
        case "ongoing":return "infinity"
        case "paused":return "pause.circle.fill"
        case "cancelled":return "xmark.circle"
        case "failed":return "exclamationmark.circle.fill"
        default:return "questionmark.circle"
        }
    }
    var body:some View {
        HStack(spacing:4) {
            Image(systemName:symbol)
            Text(Format.status(status))
            if interactive {Image(systemName:"chevron.down").font(.system(size:9,weight:.bold))}
        }
            .textSelection(.disabled)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal,7).padding(.vertical,3)
            .foregroundStyle(Self.color(for:status))
            .background(Self.background(for:status),in:Capsule())
            .overlay(Capsule().strokeBorder(Self.color(for:status).opacity(0.5)))
            .fixedSize()
            .accessibilityElement(children:.ignore)
            .accessibilityLabel("Статус задачи: "+Format.status(status))
    }
}
