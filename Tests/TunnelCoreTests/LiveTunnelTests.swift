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

    private func connected(_ session: TunnelSession) -> Bool {
        if case .connected = session.status.phase { return true }
        return false
    }

    @Test func connectsCountsClientsReconnectsAndStops() async throws {
        let tunnel = try liveTunnel()
        let port = tunnel.forwards[0].localPort
        let session = TunnelSession(tunnel: tunnel, notify: { _, _ in })
        defer { session.stop() }

        session.start()
        #expect(await eventually(timeout: .seconds(30)) { connected(session) }, "log: \(session.log.map(\.text))")
        #expect(session.sockets.listeningPorts.contains(port))

        let client = socket(AF_INET, SOCK_STREAM, 0)
        var addr = sockaddr_in.loopback(port: port)
        let rc = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(client, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        #expect(rc == 0)
        #expect(await eventually { session.sockets.clientCounts[port] == 1 })
        close(client)

        let firstPid = try #require(session.pid)
        kill(firstPid, SIGKILL)
        #expect(await eventually(timeout: .seconds(30)) { session.status.reconnectCount == 1 && connected(session) })
        #expect(session.status.lastDisconnect?.reason == .connectionLost)
        #expect(session.pid != firstPid)

        let secondPid = try #require(session.pid)
        session.stop()
        #expect(await eventually { !isAlive(secondPid) })
        #expect(session.status.phase == .stopped)
    }
}
