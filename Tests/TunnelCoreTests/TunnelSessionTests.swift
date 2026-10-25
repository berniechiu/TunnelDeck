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

    /// Listens on `$PORT` like ssh does, then runs the perl `body` with the listening socket in `$s`.
    static func perlListener(_ body: String) -> String {
        #"exec /usr/bin/perl -MIO::Socket::INET -e '$s = IO::Socket::INET->new(LocalAddr => "127.0.0.1", LocalPort => $ARGV[0], Listen => 5, ReuseAddr => 1) or die; "#
            + body + #"' "$PORT""#
    }

    /// Listens and accepts clients, holding each connection open.
    static let listen = perlListener("my @c; while (my $c = $s->accept) { push @c, $c }")

    /// Like `listen`, but ignores SIGTERM, so only SIGKILL ends it. An ignored signal stays ignored across exec.
    static let listenIgnoringTerminate = "trap '' TERM; " + listen

    static let authFailure = #"echo 'deploy@bastion: Permission denied (publickey).' >&2; exit 255"#

    static let timeout = #"echo 'ssh: connect to host bastion port 22: Operation timed out' >&2; exit 255"#

    /// Listens, then drops the connection after 2.5 seconds on the first launch only.
    static let dropOnce = """
        if [ "$(wc -l < "$MARKER")" -gt 1 ]; then \(listen); fi
        \(perlListener(#"select(undef, undef, undef, 2.5); print STDERR "Connection to bastion closed by remote host.\n"; exit 255"#))
        """
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
        #expect(await eventually { session.status.phase.isConnected })
        #expect(session.sockets.listeningPorts.contains(port))
        let pid = try #require(session.pid)

        session.stop()
        #expect(session.status.phase == .stopped)
        #expect(await eventually { !isAlive(pid) })
    }

    @Test func clientsUsingTheTunnelAreListed() async throws {
        let fake = try FakeSSH(FakeSSH.listen)
        let port = try freePort()
        let session = makeSession(fake, port: port)
        defer { session.stop() }
        session.start()
        #expect(await eventually { session.status.phase.isConnected })

        let client = try connectLoopback(port: port)
        #expect(await eventually { session.clients[port]?.contains { $0.pid == getpid() } == true })

        close(client)
        #expect(await eventually(timeout: .seconds(8)) { session.clients[port] == nil })
    }

    @Test func occupiedPortFailsWithoutLaunching() async throws {
        let fake = try FakeSSH(FakeSSH.listen)
        let listener = try TestListener()
        defer { listener.close() }
        let session = makeSession(fake, port: listener.port)
        session.start()
        guard case .failed(.portInUse(listener.port, let occupant)) = session.status.phase else {
            Issue.record("expected portInUse, got \(session.status.phase)")
            return
        }
        #expect(occupant?.pid == getpid())
        #expect(fake.launches == 0)
    }

    @Test func portTakenAfterLaunchIsReportedWithOccupant() async throws {
        // ssh loses the race for the port: something else grabs it between the pre-check and ssh's bind.
        let fake = try FakeSSH(#"""
        /usr/bin/perl -MIO::Socket::INET -e '$s = IO::Socket::INET->new(LocalAddr => "127.0.0.1", LocalPort => $ARGV[0], Listen => 5) or die; sleep 10' "$PORT" </dev/null >/dev/null 2>&1 &
        echo $! > "$MARKER.squatter"
        sleep 0.5
        echo "bind [127.0.0.1]:$PORT: Address already in use" >&2
        exit 255
        """#)
        let port = try freePort()
        let session = makeSession(fake, port: port)
        session.start()
        defer {
            if let pid = try? String(contentsOf: URL(filePath: fake.marker.path + ".squatter"), encoding: .utf8) {
                kill(pid_t(pid.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0, SIGKILL)
            }
        }
        #expect(await eventually {
            if case .failed(.portInUse(port, let occupant)) = session.status.phase { return occupant?.processName == "perl" }
            return false
        })
    }

    @Test func exitIsNoticedWhileAChildStillHoldsStderr() async throws {
        // Like a ProxyCommand that outlives ssh: the background sleep keeps the stderr pipe open for 30 seconds.
        let fake = try FakeSSH(#"""
        sleep 30 &
        echo $! >> "$MARKER.children"
        echo 'ssh: connect to host bastion port 22: Operation timed out' >&2
        exit 255
        """#)
        let session = makeSession(fake, port: try freePort())
        defer {
            session.stop()
            let children = (try? String(contentsOf: URL(filePath: fake.marker.path + ".children"), encoding: .utf8)) ?? ""
            children.split(separator: "\n").compactMap { pid_t($0) }.forEach { kill($0, SIGKILL) }
        }
        session.start()
        #expect(await eventually(timeout: .seconds(3)) {
            if case .reconnecting(_, _, .timedOut) = session.status.phase { return true }
            return false
        })
    }

    @Test func droppedConnectionReconnects() async throws {
        let fake = try FakeSSH(FakeSSH.dropOnce)
        let session = makeSession(fake, port: try freePort())
        session.start()
        #expect(await eventually(timeout: .seconds(10)) { fake.launches == 2 && session.status.reconnectCount == 1 })
        #expect(session.status.lastDisconnect?.reason == .connectionLost)
        #expect(await eventually { session.status.phase.isConnected })
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
        #expect(await eventually { session.status.phase.isConnected && fake.launches == 2 })
        #expect(session.tunnel.name == "renamed")
        session.stop()
    }
}
