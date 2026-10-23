import Darwin
import Foundation
import Testing
@testable import TunnelCore

/// Runs against a real bastion only when configured, e.g.
/// `TUNNELDECK_LIVE_HOST=bastion.example.com TUNNELDECK_LIVE_USER=deploy TUNNELDECK_LIVE_FORWARD=3310:db.internal:3306 swift test --filter LiveTunnelTests`
@MainActor
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["TUNNELDECK_LIVE_HOST"] != nil))
struct LiveTunnelTests {
    private func liveTunnel() throws -> Tunnel {
        let env = ProcessInfo.processInfo.environment
        let parts = try #require(env["TUNNELDECK_LIVE_FORWARD"]).split(separator: ":").map(String.init)
        try #require(parts.count == 3)
        return Tunnel(
            name: "live",
            host: try #require(env["TUNNELDECK_LIVE_HOST"]),
            user: env["TUNNELDECK_LIVE_USER"],
            port: env["TUNNELDECK_LIVE_PORT"].flatMap(Int.init),
            forwards: [Forward(localPort: try #require(Int(parts[0])), remoteHost: parts[1], remotePort: try #require(Int(parts[2])))]
        )
    }

    @Test func connectsCountsClientsReconnectsAndStops() async throws {
        let tunnel = try liveTunnel()
        let port = tunnel.forwards[0].localPort
        let session = TunnelSession(tunnel: tunnel, notify: { _, _ in })
        defer { session.stop() }

        session.start()
        #expect(await eventually(timeout: .seconds(30)) { session.status.phase.isConnected }, "log: \(session.log.map(\.text))")
        #expect(session.sockets.listeningPorts.contains(port))

        let client = try connectLoopback(port: port)
        #expect(await eventually { session.sockets.clientCounts[port] == 1 })
        #expect(await eventually { session.clients[port]?.contains { $0.pid == getpid() } == true })
        close(client)

        let firstPid = try #require(session.pid)
        kill(firstPid, SIGKILL)
        #expect(await eventually(timeout: .seconds(30)) { session.status.reconnectCount == 1 && session.status.phase.isConnected })
        #expect(session.status.lastDisconnect?.reason == .connectionLost)
        #expect(session.pid != firstPid)

        let secondPid = try #require(session.pid)
        session.stop()
        #expect(await eventually { !isAlive(secondPid) })
        #expect(session.status.phase == .stopped)
    }
}
