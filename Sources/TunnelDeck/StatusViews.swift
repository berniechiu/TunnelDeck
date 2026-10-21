import SwiftUI
import TunnelCore

extension TunnelPhase {
    var tint: Color {
        switch self {
        case .stopped: .secondary
        case .connecting, .reconnecting: .orange
        case .connected: .green
        case .failed: .red
        }
    }

    var isFailed: Bool {
        if case .failed = self { true } else { false }
    }

    var isTransient: Bool {
        switch self {
        case .connecting, .reconnecting: true
        default: false
        }
    }
}

struct StatusDot: View {
    let phase: TunnelPhase

    var body: some View {
        Circle()
            .fill(phase.tint)
            .frame(width: 9, height: 9)
            .phaseAnimator([1.0, 0.35], trigger: phase.isTransient) { dot, opacity in
                dot.opacity(phase.isTransient ? opacity : 1)
            } animation: { _ in .easeInOut(duration: 0.8) }
            .accessibilityLabel(StatusText.label(for: phase))
    }
}

/// One forwarded local port; lights up while ssh is listening on it and shows how many clients are using it.
struct PortChip: View {
    let port: Int
    let listening: Bool
    let clients: Int

    var body: some View {
        HStack(spacing: 3) {
            Text(String(port)).monospacedDigit()
            if clients > 0 {
                Image(systemName: "person.fill").imageScale(.small)
                Text(String(clients)).monospacedDigit()
            }
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .foregroundStyle(listening ? Color.green : Color.secondary)
        .background((listening ? Color.green : Color.secondary).opacity(0.14), in: Capsule())
        .help(listening ? "本機 \(port) 已在監聽，\(clients) 個連線使用中" : "本機 \(port) 尚未監聽")
    }
}

enum StatusText {
    static func label(for phase: TunnelPhase) -> String {
        switch phase {
        case .stopped: "已停止"
        case .connecting(0): "連線中…"
        case .connecting(let attempt): "第 \(attempt) 次重新連線中…"
        case .connected: "已連線"
        case .reconnecting: "等待重新連線"
        case .failed: "連線失敗"
        }
    }

    /// The one-line status, including live elapsed and countdown values relative to `now`.
    static func line(for status: TunnelStatus, now: Date) -> String {
        switch status.phase {
        case .connected(let since):
            return "已連線 \(duration(now.timeIntervalSince(since)))"
        case .reconnecting(let attempt, let retryAt):
            let countdown = "\(max(0, Int(retryAt.timeIntervalSince(now).rounded(.up)))) 秒後進行第 \(attempt) 次重新連線"
            return status.lastFailure.map { "\($0.message)\(countdown)" } ?? countdown
        case .failed(let failure):
            return failure.message
        default:
            return label(for: status.phase)
        }
    }

    static func duration(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        let (days, hours, minutes, seconds) = (total / 86400, total % 86400 / 3600, total % 3600 / 60, total % 60)
        if days > 0 { return "\(days) 天 \(hours) 小時" }
        if hours > 0 { return "\(hours) 小時 \(minutes) 分" }
        if minutes > 0 { return "\(minutes) 分" }
        return "\(seconds) 秒"
    }
}
