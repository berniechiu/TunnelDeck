import Darwin
import Foundation
import Testing
@testable import TunnelCore

/// A loopback listener owned by the test process, on a port the kernel picks.
final class TestListener {
    let fd: Int32
    let port: Int
    private var extra: [Int32] = []

    init() throws {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        var addr = sockaddr_in.loopback(port: 0)
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard bound == 0, listen(fd, 8) == 0 else { throw POSIXError(.EADDRINUSE) }
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &len) }
        }
        self.fd = fd
        port = Int(UInt16(bigEndian: addr.sin_port))
    }

    /// Connects a client and accepts it, leaving one established socket on `port` owned by this process.
    func connectClient() {
        let client = socket(AF_INET, SOCK_STREAM, 0)
        var addr = sockaddr_in.loopback(port: port)
        _ = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(client, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        extra += [client, accept(fd, nil, nil)]
    }

    func close() {
        (extra + [fd]).forEach { _ = Darwin.close($0) }
    }

    func closeAcceptedFirst() {
        _ = Darwin.close(extra[1])
        usleep(100_000)
        _ = Darwin.close(extra[0])
        _ = Darwin.close(fd)
        usleep(100_000)
    }
}

extension sockaddr_in {
    static func loopback(port: Int) -> sockaddr_in {
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = UInt16(port).bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        return addr
    }
}

@Test func snapshotSeesListenerAndClients() throws {
    let listener = try TestListener()
    defer { listener.close() }

    #expect(SocketInspector.snapshot(pid: getpid()).listeningPorts.contains(listener.port))
    #expect(SocketInspector.snapshot(pid: getpid()).clientCounts[listener.port, default: 0] == 0)

    listener.connectClient()
    #expect(SocketInspector.snapshot(pid: getpid()).clientCounts[listener.port] == 1)
}

@Test func portInTimeWaitIsFree() throws {
    let listener = try TestListener()
    listener.connectClient()
    // Closing the accepted (server) side first leaves that side in TIME_WAIT on the listening port.
    listener.closeAcceptedFirst()
    #expect(SocketInspector.isPortFree(listener.port))
}

@Test func occupiedPortIsReportedWithOwner() throws {
    let listener = try TestListener()
    #expect(!SocketInspector.isPortFree(listener.port))
    #expect(SocketInspector.occupant(ofLocalPort: listener.port)?.pid == getpid())

    listener.close()
    #expect(SocketInspector.isPortFree(listener.port))
}

@Test func clientProcessesAreFoundByTheirRemotePort() throws {
    let listener = try TestListener()
    defer { listener.close() }
    listener.connectClient()

    let clients = SocketInspector.clientProcesses(connectedTo: [listener.port], excluding: -1)
    let mine = try #require(clients[listener.port]?.first { $0.pid == getpid() })
    #expect(mine.connections == 1)
    #expect(mine.processName != nil)
}

@Test func theExcludedProcessIsNotItsOwnClient() throws {
    let listener = try TestListener()
    defer { listener.close() }
    listener.connectClient()
    #expect(SocketInspector.clientProcesses(connectedTo: [listener.port], excluding: getpid())[listener.port] == nil)
}
