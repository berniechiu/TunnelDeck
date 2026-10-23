import Foundation

public enum SSHCommand {
    public static let executable = "/usr/bin/ssh"

    private static let fixedOptions = [
        "-N", "-T",
        "-o", "BatchMode=yes", "-o", "ExitOnForwardFailure=yes",
        "-o", "ControlMaster=no", "-o", "ControlPath=none",
        "-o", "ServerAliveInterval=15", "-o", "ServerAliveCountMax=3",
        "-o", "ConnectTimeout=10", "-o", "LogLevel=VERBOSE",
    ]

    public static func arguments(for tunnel: Tunnel, homeDirectory: String) -> [String] {
        var args = fixedOptions
        if let user = tunnel.user?.nonEmpty { args += ["-l", user] }
        if let port = tunnel.port { args += ["-p", String(port)] }
        if let path = tunnel.identityFile?.nonEmpty {
            let expanded = path.hasPrefix("~/") ? homeDirectory + path.dropFirst() : path
            args += ["-i", expanded, "-o", "IdentitiesOnly=yes"]
        }
        for forward in tunnel.forwards {
            let host = isIPv6Address(forward.remoteHost) ? "[\(forward.remoteHost)]" : forward.remoteHost
            args += ["-L", "127.0.0.1:\(forward.localPort):\(host):\(forward.remotePort)"]
        }
        return args + ["--", tunnel.host]
    }

    public static func preview(for tunnel: Tunnel, homeDirectory: String) -> String {
        ([executable] + arguments(for: tunnel, homeDirectory: homeDirectory)).map(shellQuoted).joined(separator: " ")
    }

    private static func shellQuoted(_ value: String) -> String {
        if value.wholeMatch(of: /[A-Za-z0-9_.,:\/=@%+-]+/) != nil { return value }
        return "'" + value.replacing("'", with: #"'\''"#) + "'"
    }
}
