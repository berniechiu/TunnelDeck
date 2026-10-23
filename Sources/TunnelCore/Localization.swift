import Foundation

/// Interface language. To add one, add a case here and a complete `Strings` value in `Strings.for(_:)`.
public enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case english = "en"
    case traditionalChinese = "zh-Hant"

    public static let `default` = AppLanguage.english
    public static let storageKey = "language"

    public var id: String { rawValue }

    /// Written in the language itself, so someone who can't read the current language can still find theirs.
    public var displayName: String {
        switch self {
        case .english: "English"
        case .traditionalChinese: "繁體中文"
        }
    }

    /// The language saved in user defaults, for code outside SwiftUI views.
    public static var current: AppLanguage {
        UserDefaults.standard.string(forKey: storageKey).flatMap(AppLanguage.init(rawValue:)) ?? .default
    }
}

/// Every user-visible string. Each field is required, so a language with a missing string fails to compile.
public struct Strings: Sendable {
    // Menu bar
    public let settings: String
    public let stopAll: String
    public let quit: String
    public let quitApp: String
    public let noTunnels: String
    public let addTunnel: String
    public let summaryFailed: @Sendable (Int) -> String
    public let summaryConnecting: @Sendable (Int) -> String
    public let summaryConnected: @Sendable (Int) -> String
    public let summaryStopped: String
    public let iconStopped: String
    public let iconConnected: String
    public let iconConnecting: String
    public let iconFailed: String

    // Status
    public let stopped: String
    public let connecting: String
    public let reconnectingAttempt: @Sendable (Int) -> String
    public let connected: String
    public let waitingToReconnect: String
    public let failed: String
    public let connectedFor: @Sendable (String) -> String
    public let retryIn: @Sendable (_ seconds: Int, _ attempt: Int) -> String
    public let reconnectCount: @Sendable (Int) -> String
    public let duration: @Sendable (TimeInterval) -> String
    public let portListening: @Sendable (_ port: Int, _ clients: Int) -> String
    public let portNotListening: @Sendable (Int) -> String
    public let clientProcess: @Sendable (_ name: String, _ pid: Int32) -> String
    public let moreClients: @Sendable (Int) -> String
    public let failure: @Sendable (TunnelFailure) -> String
    public let loadError: @Sendable (_ path: String, _ error: String) -> String

    // Settings window
    public let tunnels: String
    public let preferences: String
    public let done: String
    public let language: String
    public let selectTunnel: String
    public let cannotStart: String
    public let duplicate: String
    public let duplicateName: @Sendable (String) -> String
    public let delete: String
    public let deleteEllipsis: String
    public let deleteConfirm: @Sendable (String) -> String
    public let deleteMessage: String
    public let deleteFailed: String
    public let more: String
    public let overview: String
    public let configuration: String
    public let log: String
    public let startConnection: String
    public let stopConnection: String
    public let uptime: String
    public let reconnects: String
    public let lastDisconnect: String
    public let forwards: String
    public let local: String
    public let remote: String
    public let state: String
    public let clients: String
    public let listening: String
    public let notListening: String
    public let equivalentCommand: String
    public let copy: String
    public let copyAll: String
    public let noLog: String
    public let noLogDescription: String

    // Editor
    public let connection: String
    public let name: String
    public let host: String
    public let hostPrompt: String
    public let user: String
    public let optional: String
    public let sshPort: String
    public let sshPortPrompt: String
    public let identityFile: String
    public let sshDefault: String
    public let choose: String
    public let clear: String
    public let localPort: String
    public let remoteHost: String
    public let remotePort: String
    public let removeForward: String
    public let addForward: String
    public let cancel: String
    public let add: String
    public let save: String
    public let saveAndReconnect: String
    public let saveFailed: @Sendable (String) -> String
    public let validation: @Sendable (ValidationIssue) -> String

    public static func `for`(_ language: AppLanguage) -> Strings {
        switch language {
        case .english: .english
        case .traditionalChinese: .traditionalChinese
        }
    }

    public func label(for phase: TunnelPhase) -> String {
        switch phase {
        case .stopped: stopped
        case .connecting(0): connecting
        case .connecting(let attempt): reconnectingAttempt(attempt)
        case .connected: connected
        case .reconnecting: waitingToReconnect
        case .failed: failed
        }
    }

    /// The one-line status, including live elapsed and countdown values relative to `now`.
    public func line(for status: TunnelStatus, now: Date) -> String {
        switch status.phase {
        case .connected(let since):
            connectedFor(duration(now.timeIntervalSince(since)))
        case .reconnecting(let attempt, let retryAt, let reason):
            "\(failure(reason)) \(retryIn(max(0, Int(retryAt.timeIntervalSince(now).rounded(.up))), attempt))"
        case .failed(let reason):
            failure(reason)
        default:
            label(for: status.phase)
        }
    }

    static let english = Strings(
        settings: "Settings",
        stopAll: "Stop All",
        quit: "Quit",
        quitApp: "Quit TunnelDeck",
        noTunnels: "No tunnels yet",
        addTunnel: "Add Tunnel",
        summaryFailed: { "\($0) failed" },
        summaryConnecting: { "\($0) connecting" },
        summaryConnected: { "\($0) connected" },
        summaryStopped: "All stopped",
        iconStopped: "TunnelDeck: all stopped",
        iconConnected: "TunnelDeck: connected",
        iconConnecting: "TunnelDeck: connecting",
        iconFailed: "TunnelDeck: connection failed",
        stopped: "Stopped",
        connecting: "Connecting…",
        reconnectingAttempt: { "Reconnecting, attempt \($0)…" },
        connected: "Connected",
        waitingToReconnect: "Waiting to reconnect",
        failed: "Failed",
        connectedFor: { "Connected for \($0)" },
        retryIn: { seconds, attempt in "Reconnect attempt \(attempt) in \(seconds)s" },
        reconnectCount: { $0 == 1 ? "Reconnected once" : "Reconnected \($0) times" },
        duration: { compactDuration($0, units: ("d", "h", "m", "s")) },
        portListening: { port, clients in "Local port \(port) is listening, \(clients) client\(clients == 1 ? "" : "s") connected" },
        portNotListening: { "Local port \($0) is not listening" },
        clientProcess: { name, pid in "\(name) (PID \(pid))" },
        moreClients: { "\($0) more" },
        failure: englishFailure,
        loadError: { path, error in "Couldn't read the settings file \(path): \(error)" },
        tunnels: "Tunnels",
        preferences: "Preferences…",
        done: "Done",
        language: "Language",
        selectTunnel: "Select a tunnel",
        cannotStart: "Can't start",
        duplicate: "Duplicate",
        duplicateName: { "\($0) copy" },
        delete: "Delete",
        deleteEllipsis: "Delete…",
        deleteConfirm: { "Delete “\($0)”?" },
        deleteMessage: "A running connection is stopped first.",
        deleteFailed: "Couldn't delete",
        more: "More",
        overview: "Overview",
        configuration: "Configuration",
        log: "Log",
        startConnection: "Start connection",
        stopConnection: "Stop connection",
        uptime: "Uptime",
        reconnects: "Reconnects",
        lastDisconnect: "Last disconnect",
        forwards: "Forwards",
        local: "Local",
        remote: "Remote",
        state: "Status",
        clients: "Clients",
        listening: "Listening",
        notListening: "Not listening",
        equivalentCommand: "Equivalent command",
        copy: "Copy",
        copyAll: "Copy All",
        noLog: "No log yet",
        noLogDescription: "ssh output appears here once the tunnel starts.",
        connection: "Connection",
        name: "Name",
        host: "Host",
        hostPrompt: "bastion.example.com, an IP, or a Host from ~/.ssh/config",
        user: "User",
        optional: "Optional",
        sshPort: "SSH port",
        sshPortPrompt: "Optional, defaults to 22",
        identityFile: "Identity file",
        sshDefault: "ssh default",
        choose: "Choose…",
        clear: "Clear",
        localPort: "Local port",
        remoteHost: "Remote host",
        remotePort: "Port",
        removeForward: "Remove forward",
        addForward: "Add Forward",
        cancel: "Cancel",
        add: "Add",
        save: "Save",
        saveAndReconnect: "Save and Reconnect",
        saveFailed: { "Couldn't save: \($0)" },
        validation: englishValidation
    )

    static let traditionalChinese = Strings(
        settings: "設定",
        stopAll: "全部停止",
        quit: "結束",
        quitApp: "結束 TunnelDeck",
        noTunnels: "還沒有任何 tunnel",
        addTunnel: "新增 tunnel",
        summaryFailed: { "\($0) 條連線失敗" },
        summaryConnecting: { "\($0) 條連線中" },
        summaryConnected: { "\($0) 條已連線" },
        summaryStopped: "全部已停止",
        iconStopped: "TunnelDeck：全部已停止",
        iconConnected: "TunnelDeck：已連線",
        iconConnecting: "TunnelDeck：連線中",
        iconFailed: "TunnelDeck：連線失敗",
        stopped: "已停止",
        connecting: "連線中…",
        reconnectingAttempt: { "第 \($0) 次重新連線中…" },
        connected: "已連線",
        waitingToReconnect: "等待重新連線",
        failed: "連線失敗",
        connectedFor: { "已連線 \($0)" },
        retryIn: { seconds, attempt in "\(seconds) 秒後進行第 \(attempt) 次重新連線" },
        reconnectCount: { "重連過 \($0) 次" },
        duration: { compactDuration($0, units: (" 天", " 小時", " 分", " 秒")) },
        portListening: { port, clients in "本機 port \(port) 已在監聽，\(clients) 個連線使用中" },
        portNotListening: { "本機 port \($0) 尚未監聽" },
        clientProcess: { name, pid in "\(name)（PID \(pid)）" },
        moreClients: { "還有 \($0) 個" },
        failure: chineseFailure,
        loadError: { path, error in "無法讀取設定檔 \(path)：\(error)" },
        tunnels: "Tunnel",
        preferences: "偏好設定…",
        done: "完成",
        language: "語言",
        selectTunnel: "選擇一條 tunnel",
        cannotStart: "無法啟動",
        duplicate: "複製",
        duplicateName: { "\($0) 副本" },
        delete: "刪除",
        deleteEllipsis: "刪除…",
        deleteConfirm: { "要刪除「\($0)」嗎？" },
        deleteMessage: "執行中的連線會先中斷。",
        deleteFailed: "刪除失敗",
        more: "更多",
        overview: "概覽",
        configuration: "連線設定",
        log: "Log",
        startConnection: "啟動連線",
        stopConnection: "停止連線",
        uptime: "已連線",
        reconnects: "累計重連",
        lastDisconnect: "最後斷線",
        forwards: "轉發",
        local: "本機",
        remote: "遠端",
        state: "狀態",
        clients: "使用中連線",
        listening: "監聽中",
        notListening: "未監聽",
        equivalentCommand: "等效指令",
        copy: "拷貝",
        copyAll: "拷貝全部",
        noLog: "尚無 log",
        noLogDescription: "啟動連線後，ssh 的輸出會顯示在這裡。",
        connection: "連線",
        name: "名稱",
        host: "主機",
        hostPrompt: "bastion.example.com、IP 或 ~/.ssh/config 的 Host",
        user: "使用者",
        optional: "選填",
        sshPort: "SSH port",
        sshPortPrompt: "選填，預設 22",
        identityFile: "金鑰檔",
        sshDefault: "使用 ssh 預設",
        choose: "選擇…",
        clear: "清除",
        localPort: "本機 port",
        remoteHost: "遠端主機",
        remotePort: "port",
        removeForward: "移除轉發",
        addForward: "新增轉發",
        cancel: "取消",
        add: "新增",
        save: "儲存",
        saveAndReconnect: "儲存並重新連線",
        saveFailed: { "儲存失敗：\($0)" },
        validation: chineseValidation
    )
}

private func compactDuration(_ interval: TimeInterval, units: (day: String, hour: String, minute: String, second: String)) -> String {
    let total = max(0, Int(interval))
    let (days, hours, minutes, seconds) = (total / 86400, total % 86400 / 3600, total % 3600 / 60, total % 60)
    if days > 0 { return "\(days)\(units.day) \(hours)\(units.hour)" }
    if hours > 0 { return "\(hours)\(units.hour) \(minutes)\(units.minute)" }
    if minutes > 0 { return "\(minutes)\(units.minute)" }
    return "\(seconds)\(units.second)"
}

private func englishFailure(_ failure: TunnelFailure) -> String {
    switch failure {
    case .hostKeyChanged:
        "The host key doesn't match known_hosts, which could mean a man-in-the-middle attack. Check whether the server was rebuilt, and only then update known_hosts yourself."
    case .hostKeyUnknown:
        "This host isn't trusted yet. Run ssh to it once in Terminal and confirm its fingerprint, then start again."
    case .authenticationFailed:
        "Key authentication failed. Check the identity file, and add keys with a passphrase to ssh-agent."
    case .portInUse(let port, nil):
        "Local port \(port) is in use. Use another local port or try again later."
    case .portInUse(let port, let occupant?):
        if let pid = occupant.pid {
            if occupant.processName == "ssh" {
                "Local port \(port) is in use by “ssh” (PID \(pid)), usually another tunnel tool or a leftover ssh connection. Run kill \(pid) in Terminal to end it, or use another local port."
            } else {
                "Local port \(port) is in use by “\(occupant.processName ?? "an unknown program")” (PID \(pid)). Quit that program or use another local port."
            }
        } else {
            "Local port \(port) is in use by another user or a system service. Run sudo lsof -nP -iTCP:\(port) -sTCP:LISTEN in Terminal to find it, or use another local port."
        }
    case .configError(let line):
        "Your SSH configuration has an error: \(line)"
    case .hostNotFound:
        "Host not found. Check the host name and your network connection."
    case .connectionRefused:
        "The host refused the connection."
    case .timedOut:
        "The connection timed out."
    case .networkUnreachable:
        "The host can't be reached from this network."
    case .connectionLost:
        "The connection was lost."
    case .unknown(let line):
        "ssh exited: \(line)"
    }
}

private func chineseFailure(_ failure: TunnelFailure) -> String {
    switch failure {
    case .hostKeyChanged:
        "主機金鑰與 known_hosts 紀錄不符，可能遭到中間人攻擊。請先確認伺服器是否重建過，確認無誤後再自行更新 known_hosts。"
    case .hostKeyUnknown:
        "尚未信任這台主機。請先在終端機手動 ssh 連線一次，確認主機指紋後再啟動。"
    case .authenticationFailed:
        "金鑰驗證失敗。請確認金鑰檔正確，且有 passphrase 的金鑰已加入 ssh-agent。"
    case .portInUse(let port, nil):
        "本機 port \(port) 已被占用，請改用其他本機 port 或稍後再試。"
    case .portInUse(let port, let occupant?):
        if let pid = occupant.pid {
            if occupant.processName == "ssh" {
                "本機 port \(port) 已被「ssh」（PID \(pid)）占用，通常是其他 tunnel 工具或殘留的 ssh 連線。可在終端機執行 kill \(pid) 結束它，或改用其他本機 port。"
            } else {
                "本機 port \(port) 已被「\(occupant.processName ?? "未知程式")」（PID \(pid)）占用。請結束該程式，或改用其他本機 port。"
            }
        } else {
            "本機 port \(port) 已被其他使用者或系統服務占用。可在終端機執行 sudo lsof -nP -iTCP:\(port) -sTCP:LISTEN 查出占用的程式，或改用其他本機 port。"
        }
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

private func englishValidation(_ issue: ValidationIssue) -> String {
    switch issue {
    case .emptyName: "Enter a name."
    case .invalidHost: "Enter a valid host name or IP address."
    case .invalidUser: "Use letters, digits, . _ or -, and don't start with -."
    case .invalidSSHPort, .invalidLocalPort, .invalidRemotePort: "Use a port from 1 to 65535."
    case .invalidIdentityFile: "The identity file path must start with / or ~/."
    case .noForwards: "Add at least one forward."
    case .invalidRemoteHost: "Enter a valid remote host name or IP address."
    case .duplicateLocalPort(let port): "Local port \(port) is already used by another forward."
    }
}

private func chineseValidation(_ issue: ValidationIssue) -> String {
    switch issue {
    case .emptyName: "請輸入名稱。"
    case .invalidHost: "請輸入合法的主機名稱或 IP 位址。"
    case .invalidUser: "只能包含英數與 . _ -，且不能以 - 開頭。"
    case .invalidSSHPort, .invalidLocalPort, .invalidRemotePort: "port 須介於 1 到 65535。"
    case .invalidIdentityFile: "金鑰路徑須以 / 或 ~/ 開頭。"
    case .noForwards: "至少需要一組轉發。"
    case .invalidRemoteHost: "請輸入合法的遠端主機名稱或 IP 位址。"
    case .duplicateLocalPort(let port): "本機 port \(port) 已被其他轉發使用。"
    }
}
