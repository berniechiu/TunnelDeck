import Darwin
import Foundation
import Testing
@testable import TunnelCore

/// A stand-in for /usr/bin/ssh: records each launch in a marker file, then runs `body`.
/// `$PORT` holds the local port of the first `-L` argument.
struct FakeSSH {
    let executable: String
    let marker: URL

    init(_ body: String) throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "fake-ssh-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        marker = dir.appending(path: "launches")
        let script = dir.appending(path: "ssh")
        try """
        #!/bin/bash
        MARKER='\(marker.path)'
        echo run >> "$MARKER"
        while [ $# -gt 0 ]; do
          if [ "$1" = "-L" ]; then PORT=$(echo "$2" | cut -d: -f2); fi
          shift
        done
        \(body)
        """.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        executable = script.path
    }

    var launches: Int {
        ((try? String(contentsOf: marker, encoding: .utf8)) ?? "").split(separator: "\n").count
    }

    static let listen = #"exec /usr/bin/perl -MIO::Socket::INET -e '$s = IO::Socket::INET->new(LocalAddr => "127.0.0.1", LocalPort => $ARGV[0], Listen => 5, ReuseAddr => 1) or die; sleep 600' "$PORT""#

    static let authFailure = #"echo 'deploy@bastion: Permission denied (publickey).' >&2; exit 255"#

    static let timeout = #"echo 'ssh: connect to host bastion port 22: Operation timed out' >&2; exit 255"#

    /// Listens, then drops the connection after 2.5 seconds on the first launch only.
    static let dropOnce =
        #"""
        if [ "$(wc -l < "$MARKER")" -gt 1 ]; then \#(listen); fi
        exec /usr/bin/perl -MIO::Socket::INET -e '$s = IO::Socket::INET->new(LocalAddr => "127.0.0.1", LocalPort => $ARGV[0], Listen => 5, ReuseAddr => 1) or die; select(undef, undef, undef, 2.5); print STDERR "Connection to bastion closed by remote host.\n"; exit 255' "$PORT"
        """#
}

func freePort() throws -> Int {
    let listener = try TestListener()
    defer { listener.close() }
    return listener.port
}

@MainActor
func eventually(timeout: Duration = .seconds(5), _ condition: () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(50))
    }
    return condition()
}

func isAlive(_ pid: pid_t) -> Bool { kill(pid, 0) == 0 }

func forwardTunnel(localPort port: Int) -> Tunnel {
    Tunnel(name: "test", host: "bastion", forwards: [Forward(localPort: port, remoteHost: "db", remotePort: 3306)])
}

@MainActor
func makeSession(_ fake: FakeSSH, port: Int) -> TunnelSession {
    TunnelSession(tunnel: forwardTunnel(localPort: port), executable: fake.executable, notify: { _, _ in })
}

@MainActor
@Suite(.serialized) struct TunnelSessionTests {
    @Test func authFailureStopsWithoutRetry() async throws {
        let fake = try FakeSSH(FakeSSH.authFailure)
        let session = makeSession(fake, port: try freePort())
        session.start()
        #expect(await eventually { session.status.phase == .failed(.authenticationFailed) })
        try await Task.sleep(for: .seconds(2.5))
        #expect(fake.launches == 1)
    }

    @Test func listeningProcessBecomesConnectedAndStops() async throws {
        let fake = try FakeSSH(FakeSSH.listen)
        let port = try freePort()
        let session = makeSession(fake, port: port)
        session.start()
        #expect(await eventually {
            if case .connected = session.status.phase { return true }
            return false
        })
        #expect(session.sockets.listeningPorts.contains(port))
        let pid = try #require(session.pid)

        session.stop()
        #expect(session.status.phase == .stopped)
        #expect(await eventually { !isAlive(pid) })
    }

    @Test func occupiedPortFailsWithoutLaunching() async throws {
        let fake = try FakeSSH(FakeSSH.listen)
        let listener = try TestListener()
        defer { listener.close() }
        let session = makeSession(fake, port: listener.port)
        session.start()
        #expect(session.status.phase == .failed(.portInUse(listener.port)))
        #expect(session.portOccupant?.pid == getpid())
        #expect(fake.launches == 0)
    }

    @Test func droppedConnectionReconnects() async throws {
        let fake = try FakeSSH(FakeSSH.dropOnce)
        let session = makeSession(fake, port: try freePort())
        session.start()
        #expect(await eventually(timeout: .seconds(10)) { fake.launches == 2 && session.status.reconnectCount == 1 })
        #expect(session.status.lastDisconnect?.reason == .connectionLost)
        #expect(await eventually {
            if case .connected = session.status.phase { return true }
            return false
        })
        session.stop()
    }

    @Test func stopDuringRetryWaitCancelsRetry() async throws {
        let fake = try FakeSSH(FakeSSH.timeout)
        let session = makeSession(fake, port: try freePort())
        session.start()
        #expect(await eventually {
            if case .reconnecting = session.status.phase { return true }
            return false
        })
        session.stop()
        try await Task.sleep(for: .seconds(3))
        #expect(fake.launches == 1)
        #expect(session.status.phase == .stopped)
    }

    @Test func restartWaitsForPreviousProcessToReleasePorts() async throws {
        let fake = try FakeSSH(FakeSSH.listen)
        let port = try freePort()
        let session = makeSession(fake, port: port)
        session.start()
        #expect(await eventually { session.pid != nil && session.sockets.listeningPorts.contains(port) })

        var edited = session.tunnel
        edited.name = "renamed"
        session.update(edited)
        #expect(await eventually {
            if case .connected = session.status.phase { return fake.launches == 2 }
            return false
        })
        #expect(session.tunnel.name == "renamed")
        session.stop()
    }
}
