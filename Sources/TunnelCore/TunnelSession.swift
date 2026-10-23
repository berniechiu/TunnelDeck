import Darwin
import Foundation
import Observation

public struct LogLine: Identifiable, Sendable {
    public var id: Int
    public var date: Date
    public var text: String
}

/// Runs one tunnel's ssh process and feeds its lifecycle through `TunnelStateMachine`.
@MainActor @Observable
public final class TunnelSession: Identifiable {
    public nonisolated let id: Tunnel.ID
    public private(set) var tunnel: Tunnel
    public private(set) var status = TunnelStatus()
    public private(set) var log: [LogLine] = []
    public private(set) var sockets = SocketSnapshot()
    /// Local processes connected to each forwarded port, refreshed when the connection count changes.
    public private(set) var clients: [Int: [PortClient]] = [:]
    public var pid: pid_t? { process?.processIdentifier }

    private let executable: String
    private let notify: @MainActor (Tunnel, TunnelFailure) -> Void

    private var process: Process?
    private var runID = 0
    private var runStderr: [String] = []
    private var startWhenExited = false
    private var retryTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?

    private static let logLimit = 1000
    private static let stderrLimit = 200

    public init(
        tunnel: Tunnel,
        executable: String = SSHCommand.executable,
        notify: @escaping @MainActor (Tunnel, TunnelFailure) -> Void
    ) {
        id = tunnel.id
        self.tunnel = tunnel
        self.executable = executable
        self.notify = notify
    }

    var isProcessRunning: Bool { process?.isRunning == true }

    func forceKill() {
        guard let process, process.isRunning else { return }
        kill(process.processIdentifier, SIGKILL)
    }

    public func start() {
        guard !status.phase.isRunning else { return }
        // The previous ssh still holds the ports; start once it is gone.
        guard process == nil else {
            startWhenExited = true
            return
        }
        send(.start)
    }

    public func stop() {
        startWhenExited = false
        send(.stop)
    }

    public func networkChanged() {
        send(.networkChanged)
    }

    public func update(_ tunnel: Tunnel) {
        let wasRunning = status.phase.isRunning
        if wasRunning { stop() }
        self.tunnel = tunnel
        if wasRunning { start() }
    }

    private func send(_ event: TunnelEvent) {
        var next = status
        let effects = TunnelStateMachine.reduce(&next, event, now: Date())
        // Writing through `&status` would invalidate every view that reads it, even for an ignored event.
        if next != status { status = next }
        for effect in effects {
            switch effect {
            case .launch: launch()
            case .terminate: terminate()
            case .scheduleRetry(let delay): scheduleRetry(after: delay)
            case .cancelRetry: retryTask?.cancel()
            case .notify(let failure): notify(tunnel, failure)
            }
        }
    }

    private func launch() {
        // Fail before starting ssh, so the failure can name the occupant instead of ssh's bare bind error.
        if let busy = tunnel.forwards.first(where: { !SocketInspector.isPortFree($0.localPort) }) {
            send(.processExited(withOccupant(.portInUse(busy.localPort, nil))))
            return
        }
        let process = Process()
        process.executableURL = URL(filePath: executable)
        process.arguments = SSHCommand.arguments(for: tunnel, homeDirectory: NSHomeDirectory())
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardError = pipe

        runID += 1
        let run = runID
        runStderr = []
        do {
            try process.run()
        } catch {
            send(.processExited(.unknown(error.localizedDescription)))
            return
        }
        self.process = process

        let handle = pipe.fileHandleForReading
        Task.detached { [weak self] in
            do {
                for try await line in handle.bytes.lines {
                    await self?.append(line, run: run)
                }
            } catch {}
            process.waitUntilExit()
            await self?.processEnded(run: run)
        }
        startPolling(run: run)
    }

    private func append(_ text: String, run: Int) {
        let id = (log.last?.id ?? 0) + 1
        log.append(LogLine(id: id, date: Date(), text: text))
        if log.count > Self.logLimit { log.removeFirst(log.count - Self.logLimit) }
        guard run == runID else { return }
        runStderr.append(text)
        if runStderr.count > Self.stderrLimit { runStderr.removeFirst() }
    }

    private func processEnded(run: Int) {
        guard run == runID else { return }
        process = nil
        pollTask?.cancel()
        sockets = SocketSnapshot()
        clients = [:]
        send(.processExited(withOccupant(SSHFailureClassifier.classify(stderr: runStderr.joined(separator: "\n")))))
        if startWhenExited {
            startWhenExited = false
            start()
        }
    }

    private func withOccupant(_ failure: TunnelFailure) -> TunnelFailure {
        guard case .portInUse(let port, nil) = failure else { return failure }
        return .portInUse(port, SocketInspector.occupant(ofLocalPort: port))
    }

    private func terminate() {
        guard let process else { return }
        process.terminate()
        let pid = process.processIdentifier
        Task {
            try? await Task.sleep(for: .seconds(3))
            if process.isRunning { kill(pid, SIGKILL) }
        }
    }

    private func scheduleRetry(after delay: Duration) {
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.send(.retryDue)
        }
    }

    private func startPolling(run: Int) {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, run == self.runID, let pid = self.pid else { return }
                let snapshot = SocketInspector.snapshot(pid: pid)
                let clientsChanged = snapshot.clientCounts != self.sockets.clientCounts
                // Assigning an equal value would still invalidate every view that reads `sockets`.
                if snapshot != self.sockets { self.sockets = snapshot }
                if case .connecting = self.status.phase,
                   self.tunnel.forwards.allSatisfy({ snapshot.isListening(on: $0.localPort) }) {
                    self.send(.forwardsListening)
                }
                if clientsChanged {
                    let ports = Set(snapshot.clientCounts.keys)
                    // A scan of every process, so it stays off the main actor.
                    let clients = ports.isEmpty
                        ? [:]
                        : await Task.detached { SocketInspector.clientProcesses(connectedTo: ports, excluding: pid) }.value
                    guard !Task.isCancelled else { return }
                    self.clients = clients
                }
                // Connecting needs a quick answer; once connected this only refreshes client counts.
                try? await Task.sleep(for: .seconds(self.status.phase.isConnected ? 3 : 1))
            }
        }
    }
}
