import Darwin
import Foundation
import Synchronization
import Testing
@testable import TunnelCore

@MainActor
private func makeStore(_ fake: FakeSSH, tunnels: [Tunnel] = []) throws -> (TunnelStore, ConfigStore) {
    let config = ConfigStore(fileURL: FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString)/tunnels.json"))
    try config.save(tunnels)
    return (try TunnelStore(config: config, executable: fake.executable, notify: { _, _ in }), config)
}

@MainActor
@Suite(.serialized) struct TunnelStoreTests {
    @Test func loadsSavedTunnels() throws {
        let tunnel = forwardTunnel(localPort: 3308)
        let (store, _) = try makeStore(try FakeSSH(FakeSSH.listen), tunnels: [tunnel])
        #expect(store.tunnels == [tunnel])
    }

    @Test func sessionsFollowTunnelOrderAndUnknownIdsHaveNone() throws {
        let tunnels = [forwardTunnel(localPort: 3308), forwardTunnel(localPort: 3309)]
        let (store, _) = try makeStore(try FakeSSH(FakeSSH.listen), tunnels: tunnels)
        #expect(store.sessions.map(\.tunnel.id) == tunnels.map(\.id))
        #expect(store.session(for: UUID()) == nil)
    }

    @Test func upsertPersists() throws {
        let (store, config) = try makeStore(try FakeSSH(FakeSSH.listen))
        var tunnel = forwardTunnel(localPort: 3308)
        try store.upsert(tunnel)
        tunnel.name = "renamed"
        try store.upsert(tunnel)
        #expect(try config.load() == [tunnel])
    }

    @Test func upsertRejectsDuplicatePortAndKeepsFile() throws {
        let existing = forwardTunnel(localPort: 3308)
        let (store, config) = try makeStore(try FakeSSH(FakeSSH.listen), tunnels: [existing])
        #expect(throws: ValidationFailure(issues: [.duplicateLocalPort(3308)])) {
            try store.upsert(forwardTunnel(localPort: 3308))
        }
        #expect(try config.load() == [existing])
    }

    @Test func deleteStopsAndPersists() async throws {
        let fake = try FakeSSH(FakeSSH.listen)
        let tunnel = forwardTunnel(localPort: try freePort())
        let (store, config) = try makeStore(fake, tunnels: [tunnel])
        store.session(for: tunnel.id)!.start()
        #expect(await eventually { store.session(for: tunnel.id)!.pid != nil })
        let pid = try #require(store.session(for: tunnel.id)!.pid)

        try store.delete(tunnel.id)
        #expect(try config.load() == [])
        #expect(await eventually { !isAlive(pid) })
    }

    @Test func duplicateMakesUnsavedDraftWithNewIdentity() throws {
        let tunnel = forwardTunnel(localPort: 3308)
        let (store, _) = try makeStore(try FakeSSH(FakeSSH.listen), tunnels: [tunnel])
        let draft = store.duplicate(tunnel.id, named: Strings.for(.traditionalChinese).duplicateName)
        #expect(draft?.id != tunnel.id)
        #expect(draft?.forwards.first?.id != tunnel.forwards.first?.id)
        #expect(draft?.name == "test 副本")
        #expect(store.tunnels == [tunnel])
    }

    @Test func aggregateReflectsSessions() async throws {
        let tunnel = forwardTunnel(localPort: try freePort())
        let failing = Tunnel(name: "bad", host: "bastion", forwards: [Forward(localPort: try freePort(), remoteHost: "db", remotePort: 3306)])
        let (store, _) = try makeStore(try FakeSSH(FakeSSH.listen), tunnels: [tunnel, failing])
        #expect(store.aggregate == .idle)
        store.session(for: tunnel.id)!.start()
        #expect(store.aggregate == .connecting)
        #expect(await eventually { store.aggregate == .connected })

        let listener = try TestListener()
        defer { listener.close() }
        var occupied = failing
        occupied.forwards[0].localPort = listener.port
        try store.upsert(occupied)
        store.session(for: failing.id)!.start()
        #expect(store.aggregate == .failed)
        store.stopAll()
    }

    @Test func reconnectingCountsAsConnecting() async throws {
        let tunnel = forwardTunnel(localPort: try freePort())
        let (store, _) = try makeStore(try FakeSSH(FakeSSH.timeout), tunnels: [tunnel])
        store.session(for: tunnel.id)!.start()
        #expect(await eventually {
            if case .reconnecting = store.session(for: tunnel.id)!.status.phase { return true }
            return false
        })
        #expect(store.aggregate == .connecting)
        store.stopAll()
    }

    @Test func aggregateIsObservedThroughTunnelListChanges() throws {
        let (store, _) = try makeStore(try FakeSSH(FakeSSH.listen))
        let changed = Mutex(false)
        withObservationTracking { _ = store.aggregate } onChange: { changed.withLock { $0 = true } }
        try store.upsert(forwardTunnel(localPort: 3308))
        #expect(changed.withLock { $0 })
    }

    @Test func stopAllEndsEveryProcess() async throws {
        let fake = try FakeSSH(FakeSSH.listen)
        let tunnels = [forwardTunnel(localPort: try freePort()), forwardTunnel(localPort: try freePort())]
        let (store, _) = try makeStore(fake, tunnels: tunnels)
        tunnels.forEach { store.session(for: $0.id)!.start() }
        #expect(await eventually { tunnels.allSatisfy { store.session(for: $0.id)!.pid != nil } })
        let pids = tunnels.compactMap { store.session(for: $0.id)!.pid }

        store.stopAll()
        #expect(await eventually { pids.allSatisfy { !isAlive($0) } })
    }

    @Test func shutdownBlocksUntilProcessesExit() async throws {
        let fake = try FakeSSH(FakeSSH.listen)
        let tunnel = forwardTunnel(localPort: try freePort())
        let (store, _) = try makeStore(fake, tunnels: [tunnel])
        store.session(for: tunnel.id)!.start()
        #expect(await eventually { store.session(for: tunnel.id)!.pid != nil })
        let pid = try #require(store.session(for: tunnel.id)!.pid)

        store.shutdown()
        #expect(!isAlive(pid))
    }
}
