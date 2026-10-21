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

extension Strings {
    func label(for phase: TunnelPhase) -> String {
        switch phase {
        case .stopped: stopped
        case .connecting(0): connecting
        case .connecting(let attempt): reconnectingAttempt(attempt)
        case .connected: connected
        case .reconnecting: waitingToReconnect
        case .failed: failed
        }
    }

    /// The one-line status, including live elapsed and countdown values relative to `now`.
    func line(for status: TunnelStatus, now: Date) -> String {
        switch status.phase {
        case .connected(let since):
            return connectedFor(duration(now.timeIntervalSince(since)))
        case .reconnecting(let attempt, let retryAt):
            let countdown = retryIn(max(0, Int(retryAt.timeIntervalSince(now).rounded(.up))), attempt)
            return status.lastFailure.map { "\(failure($0)) \(countdown)" } ?? countdown
        case .failed(let reason):
            return failure(reason)
        default:
            return label(for: status.phase)
        }
    }
}

struct StatusDot: View {
    let phase: TunnelPhase
    @Environment(\.strings) private var strings

    var body: some View {
        Circle()
            .fill(phase.tint)
            .frame(width: 9, height: 9)
            .phaseAnimator([1.0, 0.35], trigger: phase.isTransient) { dot, opacity in
                dot.opacity(phase.isTransient ? opacity : 1)
            } animation: { _ in .easeInOut(duration: 0.8) }
            .accessibilityLabel(strings.label(for: phase))
    }
}

/// One forwarded local port; lights up while ssh is listening on it and shows how many clients are using it.
struct PortChip: View {
    let port: Int
    let listening: Bool
    let clients: Int
    @Environment(\.strings) private var strings

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
        .help(listening ? strings.portListening(port, clients) : strings.portNotListening(port))
    }
}
