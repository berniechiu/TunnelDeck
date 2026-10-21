import Darwin
import Foundation

public struct SocketSnapshot: Equatable, Sendable {
    public var listeningPorts: Set<Int> = []
    public var clientCounts: [Int: Int] = [:]

    public init(listeningPorts: Set<Int> = [], clientCounts: [Int: Int] = [:]) {
        self.listeningPorts = listeningPorts
        self.clientCounts = clientCounts
    }
}

public struct PortOccupant: Equatable, Sendable {
    /// nil when the port is held by a process this user cannot inspect.
    public var pid: pid_t?
    public var processName: String?
}

public enum SocketInspector {
    public static func snapshot(pid: pid_t) -> SocketSnapshot {
        let sockets = tcpSockets(pid: pid)
        let listening = Set(sockets.filter { $0.state == TSI_S_LISTEN }.map(\.localPort))
        var counts: [Int: Int] = [:]
        for socket in sockets where socket.state == TSI_S_ESTABLISHED && listening.contains(socket.localPort) {
            counts[socket.localPort, default: 0] += 1
        }
        return SocketSnapshot(listeningPorts: listening, clientCounts: counts)
    }

    public static func isPortFree(_ port: Int) -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        // ssh sets SO_REUSEADDR on its listeners, so a port left in TIME_WAIT is still usable for it.
        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = UInt16(port).bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        return withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        } == 0
    }

    public static func occupant(ofLocalPort port: Int) -> PortOccupant? {
        for pid in allPids() where tcpSockets(pid: pid).contains(where: { $0.state == TSI_S_LISTEN && $0.localPort == port }) {
            return PortOccupant(pid: pid, processName: processName(pid))
        }
        return isPortFree(port) ? nil : PortOccupant(pid: nil, processName: nil)
    }

    private struct TCPSocket {
        var localPort: Int
        var state: Int32
    }

    private static func tcpSockets(pid: pid_t) -> [TCPSocket] {
        let stride = MemoryLayout<proc_fdinfo>.stride
        let size = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard size > 0 else { return [] }
        var fds = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(size) / stride)
        let used = fds.withUnsafeMutableBytes { proc_pidinfo(pid, PROC_PIDLISTFDS, 0, $0.baseAddress, Int32($0.count)) }
        guard used > 0 else { return [] }

        return fds.prefix(Int(used) / stride).compactMap { fd in
            guard fd.proc_fdtype == UInt32(PROX_FDTYPE_SOCKET) else { return nil }
            var info = socket_fdinfo()
            let infoSize = Int32(MemoryLayout<socket_fdinfo>.size)
            guard proc_pidfdinfo(pid, fd.proc_fd, PROC_PIDFDSOCKETINFO, &info, infoSize) == infoSize,
                  info.psi.soi_kind == SOCKINFO_TCP else { return nil }
            let tcp = info.psi.soi_proto.pri_tcp
            let port = Int(UInt16(bigEndian: UInt16(truncatingIfNeeded: tcp.tcpsi_ini.insi_lport)))
            return TCPSocket(localPort: port, state: tcp.tcpsi_state)
        }
    }

    private static func allPids() -> [pid_t] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(count) * 2)
        let found = pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, Int32($0.count)) }
        return Array(pids.prefix(Int(max(found, 0))))
    }

    private static func processName(_ pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXCOMLEN) * 2 + 1)
        guard proc_name(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(cString: buffer)
    }
}
