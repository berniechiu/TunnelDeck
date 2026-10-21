import Foundation

public enum TunnelPhase: Equatable, Sendable {
    case stopped
    case connecting(attempt: Int)
    case connected(since: Date)
    case reconnecting(attempt: Int, retryAt: Date)
    case failed(TunnelFailure)

    public var isRunning: Bool {
        switch self {
        case .connecting, .connected, .reconnecting: true
        case .stopped, .failed: false
        }
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
    /// Why the latest run ended, until the tunnel is connected again.
    public var lastFailure: TunnelFailure?

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
    public static func delay(forAttempt attempt: Int) -> Duration {
        attempt >= 5 ? .seconds(30) : .seconds(1 << attempt)
    }
}

public enum TunnelStateMachine {
    public static func reduce(_ status: inout TunnelStatus, _ event: TunnelEvent, now: Date) -> [TunnelEffect] {
        switch (status.phase, event) {
        case (.stopped, .start), (.failed, .start):
            status.phase = .connecting(attempt: 0)
            return [.launch]

        case (.connecting, .forwardsListening):
            status.phase = .connected(since: now)
            status.lastFailure = nil
            return []

        case (.connecting(let attempt), .processExited(let failure)):
            status.lastFailure = failure
            guard failure.isRetryable else {
                status.phase = .failed(failure)
                return attempt >= 1 ? [.notify(failure)] : []
            }
            let next = attempt + 1
            let delay = ReconnectPolicy.delay(forAttempt: next)
            status.phase = .reconnecting(attempt: next, retryAt: now.addingTimeInterval(delay.seconds))
            return [.scheduleRetry(after: delay)] + (attempt == 1 ? [.notify(failure)] : [])

        case (.connected, .processExited(let failure)):
            status.lastFailure = failure
            status.reconnectCount += 1
            status.lastDisconnect = Disconnect(at: now, reason: failure)
            guard failure.isRetryable else {
                status.phase = .failed(failure)
                return [.notify(failure)]
            }
            status.phase = .connecting(attempt: 1)
            return [.launch]

        case (.reconnecting(let attempt, _), .retryDue):
            status.phase = .connecting(attempt: attempt)
            return [.launch]

        case (.reconnecting(let attempt, _), .networkChanged):
            status.phase = .connecting(attempt: attempt)
            return [.cancelRetry, .launch]

        case (let phase, .stop) where phase.isRunning:
            status.phase = .stopped
            return [.terminate, .cancelRetry]

        default:
            return []
        }
    }
}

extension Duration {
    var seconds: TimeInterval {
        let (seconds, attoseconds) = components
        return TimeInterval(seconds) + TimeInterval(attoseconds) / 1e18
    }
}
