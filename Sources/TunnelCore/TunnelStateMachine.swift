import Foundation

public enum TunnelPhase: Equatable, Sendable {
    case stopped
    case connecting(attempt: Int)
    case connected(since: Date)
    case reconnecting(attempt: Int, retryAt: Date, after: TunnelFailure)
    case failed(TunnelFailure)

    public var isRunning: Bool {
        switch self {
        case .connecting, .connected, .reconnecting: true
        case .stopped, .failed: false
        }
    }

    public var isTransient: Bool {
        switch self {
        case .connecting, .reconnecting: true
        default: false
        }
    }

    public var isConnected: Bool {
        if case .connected = self { true } else { false }
    }

    public var isFailed: Bool {
        if case .failed = self { true } else { false }
    }
}

public struct Disconnect: Equatable, Sendable {
    public var at: Date
    public var reason: TunnelFailure
}

public struct TunnelStatus: Equatable, Sendable {
    public var phase: TunnelPhase = .stopped
    public var reconnectCount = 0
    public var lastDisconnect: Disconnect?
    /// Consecutive connections that dropped before becoming stable; drives the backoff for a flapping server.
    public var quickDrops = 0
    /// Whether this outage already produced a notification, so a long outage notifies once.
    public var outageNotified = false

    public init(phase: TunnelPhase = .stopped) {
        self.phase = phase
    }
}

public enum TunnelEvent: Sendable {
    case start
    case stop
    case forwardsListening
    case processExited(TunnelFailure)
    case retryDue
    case networkChanged
}

public enum TunnelEffect: Equatable, Sendable {
    case launch
    case terminate
    case scheduleRetry(after: Duration)
    case cancelRetry
    case notify(TunnelFailure)
}

public enum ReconnectPolicy {
    /// A connection that lasts this long counts as stable, so its drop is retried right away.
    public static let stableAfter: TimeInterval = 30

    public static func delay(forAttempt attempt: Int) -> TimeInterval {
        attempt >= 5 ? 30 : TimeInterval(1 << attempt)
    }
}

public enum TunnelStateMachine {
    public static func reduce(_ status: inout TunnelStatus, _ event: TunnelEvent, now: Date) -> [TunnelEffect] {
        switch (status.phase, event) {
        case (.stopped, .start), (.failed, .start):
            status.quickDrops = 0
            status.outageNotified = false
            status.phase = .connecting(attempt: 0)
            return [.launch]

        case (.connecting, .forwardsListening):
            status.phase = .connected(since: now)
            status.outageNotified = false
            return []

        case (.connecting(let attempt), .processExited(let failure)):
            // A manual start (attempt 0) has the user watching. Automatic reconnects notify once per outage,
            // and again when they give up.
            guard failure.isRetryable else {
                status.phase = .failed(failure)
                return attempt >= 1 ? [.notify(failure)] : []
            }
            let notify: [TunnelEffect] = attempt >= 1 && !status.outageNotified ? [.notify(failure)] : []
            if !notify.isEmpty { status.outageNotified = true }
            return [scheduleReconnect(&status, attempt: attempt + 1, after: failure, now: now)] + notify

        case (.connected(let since), .processExited(let failure)):
            status.reconnectCount += 1
            status.lastDisconnect = Disconnect(at: now, reason: failure)
            guard failure.isRetryable else {
                status.phase = .failed(failure)
                return [.notify(failure)]
            }
            guard now.timeIntervalSince(since) < ReconnectPolicy.stableAfter else {
                status.quickDrops = 0
                status.phase = .connecting(attempt: 1)
                return [.launch]
            }
            status.quickDrops += 1
            return [scheduleReconnect(&status, attempt: status.quickDrops, after: failure, now: now)]

        case (.reconnecting(let attempt, _, _), .retryDue):
            status.phase = .connecting(attempt: attempt)
            return [.launch]

        case (.reconnecting(let attempt, _, _), .networkChanged):
            status.phase = .connecting(attempt: attempt)
            return [.cancelRetry, .launch]

        case (let phase, .stop) where phase.isRunning:
            status.phase = .stopped
            return [.terminate, .cancelRetry]

        case (.failed, .stop):
            status.phase = .stopped
            return []

        default:
            return []
        }
    }

    private static func scheduleReconnect(
        _ status: inout TunnelStatus, attempt: Int, after failure: TunnelFailure, now: Date
    ) -> TunnelEffect {
        let delay = ReconnectPolicy.delay(forAttempt: attempt)
        status.phase = .reconnecting(attempt: attempt, retryAt: now.addingTimeInterval(delay), after: failure)
        return .scheduleRetry(after: .seconds(delay))
    }
}
