import Foundation
import Observation

public enum AggregateState: Sendable {
    case idle, connected, connecting, failed
}

@MainActor @Observable
public final class TunnelStore {
    public private(set) var tunnels: [Tunnel]

    private let config: ConfigStore
    private let executable: String
    private let notify: @MainActor (Tunnel, TunnelFailure) -> Void
    @ObservationIgnored private var sessionsByID: [Tunnel.ID: TunnelSession] = [:]
    /// Deleted sessions whose ssh may not have exited yet, so `shutdown()` still waits for and kills it.
    @ObservationIgnored private var deletedSessions: [TunnelSession] = []

    public init(
        config: ConfigStore,
        executable: String = SSHCommand.executable,
        notify: @escaping @MainActor (Tunnel, TunnelFailure) -> Void
    ) throws {
        self.config = config
        self.executable = executable
        self.notify = notify
        tunnels = try config.load()
        tunnels.forEach(makeSession)
    }

    /// One session per tunnel, in list order. Reads `tunnels`, so views track additions and removals.
    public var sessions: [TunnelSession] {
        tunnels.compactMap { sessionsByID[$0.id] }
    }

    public func session(for id: Tunnel.ID) -> TunnelSession? {
        sessionsByID[id]
    }

    private func makeSession(_ tunnel: Tunnel) {
        sessionsByID[tunnel.id] = TunnelSession(tunnel: tunnel, executable: executable, notify: notify)
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
        if let session = sessionsByID[tunnel.id] {
            session.update(tunnel)
        } else {
            makeSession(tunnel)
        }
    }

    public func delete(_ id: Tunnel.ID) throws {
        let remaining = tunnels.filter { $0.id != id }
        try config.save(remaining)
        tunnels = remaining
        guard let session = sessionsByID.removeValue(forKey: id) else { return }
        session.stop()
        deletedSessions.removeAll { !$0.isProcessRunning }
        if session.isProcessRunning { deletedSessions.append(session) }
    }

    /// An unsaved copy for the editor; its ports still clash with the original until edited.
    public func duplicate(_ id: Tunnel.ID, named name: (String) -> String) -> Tunnel? {
        guard var copy = tunnels.first(where: { $0.id == id }) else { return nil }
        copy.id = UUID()
        copy.name = name(copy.name)
        copy.forwards = copy.forwards.map { Forward(localPort: $0.localPort, remoteHost: $0.remoteHost, remotePort: $0.remotePort) }
        return copy
    }

    /// The most urgent state across all tunnels: failed, then connecting or reconnecting, then connected.
    public var aggregate: AggregateState {
        let phases = sessions.map(\.status.phase)
        if phases.contains(where: \.isFailed) { return .failed }
        if phases.contains(where: \.isTransient) { return .connecting }
        return phases.contains(where: \.isConnected) ? .connected : .idle
    }

    public func stopAll() {
        sessions.forEach { $0.stop() }
    }

    public func networkChanged() {
        sessions.forEach { $0.networkChanged() }
    }

    /// Stops everything and blocks until the ssh processes are gone, for use while the app quits.
    public func shutdown() {
        stopAll()
        let owned = sessions + deletedSessions
        Self.wait(seconds: 3) { !owned.contains(where: \.isProcessRunning) }
        owned.forEach { $0.forceKill() }
        Self.wait(seconds: 0.5) { !owned.contains(where: \.isProcessRunning) }
    }

    private static func wait(seconds: TimeInterval, until done: () -> Bool) {
        let deadline = Date().addingTimeInterval(seconds)
        while !done(), Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
    }
}
