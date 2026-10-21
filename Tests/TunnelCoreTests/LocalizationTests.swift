import Foundation
import Testing
@testable import TunnelCore

private let allFailures: [TunnelFailure] = [
    .hostKeyChanged, .hostKeyUnknown, .authenticationFailed, .portInUse(3308, nil), .configError("x"),
    .hostNotFound, .connectionRefused, .timedOut, .networkUnreachable, .connectionLost, .unknown("x"),
]

@Test func englishIsTheDefault() {
    #expect(AppLanguage.default == .english)
}

@Test func hostKeyMessagesAreFixedCopy() {
    let en = Strings.for(.english)
    #expect(en.failure(.hostKeyChanged) == "The host key doesn't match known_hosts, which could mean a man-in-the-middle attack. Check whether the server was rebuilt, and only then update known_hosts yourself.")
    #expect(en.failure(.hostKeyUnknown) == "This host isn't trusted yet. Run ssh to it once in Terminal and confirm its fingerprint, then start again.")

    let zh = Strings.for(.traditionalChinese)
    #expect(zh.failure(.hostKeyChanged) == "主機金鑰與 known_hosts 紀錄不符，可能遭到中間人攻擊。請先確認伺服器是否重建過，確認無誤後再自行更新 known_hosts。")
    #expect(zh.failure(.hostKeyUnknown) == "尚未信任這台主機。請先在終端機手動 ssh 連線一次，確認主機指紋後再啟動。")
}

@Test(arguments: AppLanguage.allCases)
func noMessageSuggestsBypassingHostKeyChecks(language: AppLanguage) {
    let strings = Strings.for(language)
    for failure in allFailures {
        let message = strings.failure(failure)
        #expect(!message.contains("StrictHostKeyChecking"))
        #expect(!message.localizedCaseInsensitiveContains("skip"))
        #expect(!message.contains("略過"))
    }
}

@Test(arguments: AppLanguage.allCases)
func messagesCarryDetails(language: AppLanguage) {
    let strings = Strings.for(language)
    #expect(strings.failure(.portInUse(3308, nil)).contains("3308"))
    #expect(strings.failure(.configError("line 12: Bad")).contains("line 12: Bad"))
    #expect(strings.failure(.unknown("weird")).contains("weird"))
}

@Test func portInUseNamesTheOccupantAndHowToFreeIt() {
    let zh = Strings.for(.traditionalChinese)
    #expect(zh.failure(.portInUse(3310, PortOccupant(pid: 4242, processName: "mysqld"))) == "本機 port 3310 已被「mysqld」（PID 4242）占用。請結束該程式，或改用其他本機 port。")
    #expect(zh.failure(.portInUse(3310, PortOccupant(pid: 4242, processName: "ssh"))) == "本機 port 3310 已被「ssh」（PID 4242）占用，通常是其他 tunnel 工具或殘留的 ssh 連線。可在終端機執行 kill 4242 結束它，或改用其他本機 port。")
    #expect(zh.failure(.portInUse(3310, PortOccupant(pid: nil, processName: nil))) == "本機 port 3310 已被其他使用者或系統服務占用。可在終端機執行 sudo lsof -nP -iTCP:3310 -sTCP:LISTEN 查出占用的程式，或改用其他本機 port。")
    #expect(zh.failure(.portInUse(3310, nil)) == "本機 port 3310 已被占用，請改用其他本機 port 或稍後再試。")

    let en = Strings.for(.english)
    #expect(en.failure(.portInUse(3310, PortOccupant(pid: 4242, processName: "mysqld"))) == "Local port 3310 is in use by “mysqld” (PID 4242). Quit that program or use another local port.")
    #expect(en.failure(.portInUse(3310, PortOccupant(pid: 4242, processName: "ssh"))) == "Local port 3310 is in use by “ssh” (PID 4242), usually another tunnel tool or a leftover ssh connection. Run kill 4242 in Terminal to end it, or use another local port.")
    #expect(en.failure(.portInUse(3310, PortOccupant(pid: nil, processName: nil))) == "Local port 3310 is in use by another user or a system service. Run sudo lsof -nP -iTCP:3310 -sTCP:LISTEN in Terminal to find it, or use another local port.")
    #expect(en.failure(.portInUse(3310, nil)) == "Local port 3310 is in use. Use another local port or try again later.")
}

private let sampleDurations: [TimeInterval] = [45, 13 * 60, 2 * 3600 + 13 * 60, 2 * 86400 + 3 * 3600]

@Test func durationsAreCompact() {
    let en = Strings.for(.english)
    #expect(sampleDurations.map(en.duration) == ["45s", "13m", "2h 13m", "2d 3h"])
    let zh = Strings.for(.traditionalChinese)
    #expect(sampleDurations.map(zh.duration) == ["45 秒", "13 分", "2 小時 13 分", "2 天 3 小時"])
}
