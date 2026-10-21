import Foundation

public enum TunnelFailure: Equatable, Sendable {
    case hostKeyChanged
    case hostKeyUnknown
    case authenticationFailed
    case portInUse(Int)
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

    public var message: String {
        switch self {
        case .hostKeyChanged:
            "主機金鑰與 known_hosts 紀錄不符，可能遭到中間人攻擊。請先確認伺服器是否重建過，確認無誤後再自行更新 known_hosts。"
        case .hostKeyUnknown:
            "尚未信任這台主機。請先在終端機手動 ssh 連線一次，確認主機指紋後再啟動。"
        case .authenticationFailed:
            "金鑰驗證失敗。請確認金鑰檔正確，且有 passphrase 的金鑰已加入 ssh-agent。"
        case .portInUse(let port):
            "本機 port \(port) 已被其他程式占用。"
        case .configError(let line):
            "SSH 設定檔有誤：\(line)"
        case .hostNotFound:
            "找不到主機，請確認主機名稱或網路連線。"
        case .connectionRefused:
            "主機拒絕連線。"
        case .timedOut:
            "連線逾時。"
        case .networkUnreachable:
            "網路無法連到主機。"
        case .connectionLost:
            "連線中斷。"
        case .unknown(let line):
            "ssh 結束：\(line)"
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
            return .portInUse(port)
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
