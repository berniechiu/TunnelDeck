import Foundation
import Observation

public enum AggregateState: Sendable {
    case idle, active, attention
}

@MainActor @Observable
public final class TunnelStore {
    public private(set) var tunnels: [Tunnel]

    private let config: ConfigStore
    private let executable: String
    private let notify: @MainActor (Tunnel, TunnelFailure) -> Void
    private var sessions: [Tunnel.ID: TunnelSession] = [:]

    public init(
        config: ConfigStore,
        executable: String = SSHCommand.executable,
        notify: @escaping @MainActor (Tunnel, TunnelFailure) -> Void
    ) throws {
        self.config = config
        self.executable = executable
        self.notify = notify
        tunnels = try config.load()
    }

    public func session(for id: Tunnel.ID) -> TunnelSession {
        if let session = sessions[id] { return session }
        let tunnel = tunnels.first { $0.id == id }!
        let session = TunnelSession(tunnel: tunnel, executable: executable, notify: notify)
        sessions[id] = session
        return session
    }

    public func upsert(_ tunnel: Tunnel) throws {
        let issues = validate(tunnel, against: tunnels)
        guard issues.isEmpty else { throw ValidationFailure(issues: issues) }
        var updated = tunnels
        if let index = updated.firstIndex(where: { $0.id == tunnel.id }) {
            updated[index] = tunnel
        } else {
            updated.append(tunnel)
        }
        try config.save(updated)
        tunnels = updated
        sessions[tunnel.id]?.update(tunnel)
    }

    public func delete(_ id: Tunnel.ID) throws {
        let remaining = tunnels.filter { $0.id != id }
        try config.save(remaining)
        sessions.removeValue(forKey: id)?.stop()
        tunnels = remaining
    }

    /// An unsaved copy for the editor; its ports still clash with the original until edited.
    public func duplicate(_ id: Tunnel.ID) -> Tunnel? {
        guard var copy = tunnels.first(where: { $0.id == id }) else { return nil }
        copy.id = UUID()
        copy.name += " 副本"
        copy.forwards = copy.forwards.map { Forward(localPort: $0.localPort, remoteHost: $0.remoteHost, remotePort: $0.remotePort) }
        return copy
    }

    public var aggregate: AggregateState {
        // Reading `tunnels` (observed) rather than `sessions` (ignored) keeps views tracking list changes.
        let phases = tunnels.compactMap { sessions[$0.id]?.status.phase }
        if phases.contains(where: {
            switch $0 {
            case .failed, .reconnecting: true
            default: false
            }
        }) { return .attention }
        return phases.contains(where: \.isRunning) ? .active : .idle
    }

    public func stopAll() {
        sessions.values.forEach { $0.stop() }
    }

    public func networkChanged() {
        sessions.values.forEach { $0.networkChanged() }
    }

    /// Stops everything and blocks until the ssh processes are gone, for use while the app quits.
    public func shutdown(timeout: TimeInterval = 3) {
        stopAll()
        let deadline = Date().addingTimeInterval(timeout)
        while sessions.values.contains(where: \.isProcessRunning), Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        sessions.values.forEach { $0.killImmediately() }
    }
}
