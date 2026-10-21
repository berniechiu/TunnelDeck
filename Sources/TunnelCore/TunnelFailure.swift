import Foundation

public enum TunnelFailure: Equatable, Sendable {
    case hostKeyChanged
    case hostKeyUnknown
    case authenticationFailed
    case portInUse(Int, PortOccupant?)
    case configError(String)
    case hostNotFound
    case connectionRefused
    case timedOut
    case networkUnreachable
    case connectionLost
    case unknown(String)

    public var isRetryable: Bool {
        switch self {
        case .hostKeyChanged, .hostKeyUnknown, .authenticationFailed, .portInUse, .configError: false
        case .hostNotFound, .connectionRefused, .timedOut, .networkUnreachable, .connectionLost, .unknown: true
        }
    }
}

public enum SSHFailureClassifier {
    /// Classifies what ended an ssh run. Output from before authentication succeeded and per-connection
    /// channel failures are ignored, since neither is why an established tunnel went away.
    public static func classify(stderr: String) -> TunnelFailure {
        var lines = stderr.split(whereSeparator: \.isNewline).map(String.init)
        let authenticated = lines.lastIndex { $0.hasPrefix("Authenticated to ") }
        if let authenticated { lines.removeSubrange(...authenticated) }
        lines.removeAll { $0.wholeMatch(of: /channel \d+: open failed: .*/) != nil }
        let text = lines.joined(separator: "\n")
        func has(_ needles: String...) -> Bool { needles.contains { text.contains($0) } }

        if has("REMOTE HOST IDENTIFICATION HAS CHANGED") { return .hostKeyChanged }
        if has("Host key verification failed") { return .hostKeyUnknown }
        if has("Permission denied (") { return .authenticationFailed }
        if let match = text.firstMatch(of: /bind \[127\.0\.0\.1\]:(\d+): Address already in use/), let port = Int(match.1) {
            return .portInUse(port, nil)
        }
        if has("bad configuration options") {
            return .configError(lines.first { $0.contains(/\sline \d+:\s/) } ?? lines[0])
        }
        if let line = lines.first(where: { $0.contains("Can't open user config file") || $0.hasPrefix("Bad owner or permissions on") }) {
            return .configError(line)
        }
        if has("Could not resolve hostname") { return .hostNotFound }
        if has("Connection refused") { return .connectionRefused }
        if has("Operation timed out", "Connection timed out", "not responding") { return .timedOut }
        if has("Network is unreachable", "No route to host") { return .networkUnreachable }
        if has("closed by remote host", "Connection reset", "Broken pipe", "Connection closed by") { return .connectionLost }

        let last = lines.last { !$0.trimmingCharacters(in: .whitespaces).isEmpty && !$0.hasPrefix("debug") }
        if last == nil, authenticated != nil { return .connectionLost }
        return .unknown(last ?? "")
    }
}
