import Foundation
import Testing
@testable import TunnelCore

@Test(arguments: [
    ("""
    @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
    @    WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!     @
    @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
    IT IS POSSIBLE THAT SOMEONE IS DOING SOMETHING NASTY!
    Host key verification failed.
    """, TunnelFailure.hostKeyChanged),
    ("No ED25519 host key is known for bastion and you have requested strict checking.\nHost key verification failed.\n", .hostKeyUnknown),
    ("deploy@bastion.example.com: Permission denied (publickey).\n", .authenticationFailed),
    ("bind [127.0.0.1]:3308: Address already in use\nchannel_setup_fwd_listener_tcpip: cannot listen to port: 3308\nCould not request local forwarding.\n", .portInUse(3308)),
    ("/Users/me/.ssh/config: line 12: Bad configuration option: foo\n/Users/me/.ssh/config: terminating, 1 bad configuration options\n",
     .configError("/Users/me/.ssh/config: line 12: Bad configuration option: foo")),
    ("Can't open user config file /Users/me/.ssh/config: Permission denied\n", .configError("Can't open user config file /Users/me/.ssh/config: Permission denied")),
    ("ssh: Could not resolve hostname bastion.example.com: nodename nor servname provided, or not known\n", .hostNotFound),
    ("ssh: connect to host bastion.example.com port 22: Connection refused\n", .connectionRefused),
    ("ssh: connect to host bastion.example.com port 22: Operation timed out\n", .timedOut),
    ("Timeout, server bastion.example.com not responding.\n", .timedOut),
    ("ssh: connect to host 10.0.0.1 port 22: Network is unreachable\n", .networkUnreachable),
    ("ssh: connect to host 10.0.0.1 port 22: No route to host\n", .networkUnreachable),
    ("Connection to bastion.example.com closed by remote host.\n", .connectionLost),
    ("client_loop: send disconnect: Broken pipe\n", .connectionLost),
    ("Read from remote host bastion: Connection reset by peer\n", .connectionLost),
    ("debug1: something\nweird failure here\ndebug1: Exit status 255\n", .unknown("weird failure here")),
])
func classifies(stderr: String, expected: TunnelFailure) {
    #expect(SSHFailureClassifier.classify(stderr: stderr) == expected)
}

@Test(arguments: [
    ("""
    /Users/me/.ssh/config line 2: Unsupported option "rsaauthentication"
    Authenticated to bastion ([10.0.0.1]:22) using "publickey".
    Connection to bastion closed by remote host.
    """, TunnelFailure.connectionLost),
    ("""
    /Users/me/.ssh/config line 2: Unsupported option "rsaauthentication"
    ssh: connect to host bastion port 22: Operation timed out
    """, .timedOut),
    ("""
    /Users/me/.ssh/conf.d/work line 2: no argument after keyword "port"
    /Users/me/.ssh/conf.d/work: terminating, 1 bad configuration options
    """, .configError(#"/Users/me/.ssh/conf.d/work line 2: no argument after keyword "port""#)),
    ("Bad owner or permissions on /Users/me/.ssh/config\n", .configError("Bad owner or permissions on /Users/me/.ssh/config")),
    ("""
    Authenticated to bastion ([10.0.0.1]:22) using "publickey".
    channel 3: open failed: connect failed: Connection refused
    Connection to bastion closed by remote host.
    """, .connectionLost),
    ("""
    Authenticated to bastion ([10.0.0.1]:22) using "publickey".
    channel 3: open failed: connect failed: Connection refused
    """, .connectionLost),
])
func classifiesOnlyWhatEndedTheRun(stderr: String, expected: TunnelFailure) {
    #expect(SSHFailureClassifier.classify(stderr: stderr) == expected)
}

@Test func nonRetryableFailures() {
    let nonRetryable: [TunnelFailure] = [.hostKeyChanged, .hostKeyUnknown, .authenticationFailed, .portInUse(1), .configError("x")]
    #expect(nonRetryable.allSatisfy { !$0.isRetryable })
    let retryable: [TunnelFailure] = [.hostNotFound, .connectionRefused, .timedOut, .networkUnreachable, .connectionLost, .unknown("x")]
    #expect(retryable.allSatisfy { $0.isRetryable })
}

@Test func hostKeyMessagesAreFixedCopy() {
    #expect(TunnelFailure.hostKeyChanged.message == "主機金鑰與 known_hosts 紀錄不符，可能遭到中間人攻擊。請先確認伺服器是否重建過，確認無誤後再自行更新 known_hosts。")
    #expect(TunnelFailure.hostKeyUnknown.message == "尚未信任這台主機。請先在終端機手動 ssh 連線一次，確認主機指紋後再啟動。")
}

@Test func noMessageSuggestsBypassingHostKeyChecks() {
    let all: [TunnelFailure] = [.hostKeyChanged, .hostKeyUnknown, .authenticationFailed, .portInUse(3308), .configError("x"),
                                .hostNotFound, .connectionRefused, .timedOut, .networkUnreachable, .connectionLost, .unknown("x")]
    for failure in all {
        #expect(!failure.message.contains("StrictHostKeyChecking"))
        #expect(!failure.message.contains("known_hosts 刪除"))
        #expect(!failure.message.contains("略過"))
    }
}

@Test func messagesCarryDetails() {
    #expect(TunnelFailure.portInUse(3308).message.contains("3308"))
    #expect(TunnelFailure.configError("line 12: Bad").message.contains("line 12: Bad"))
    #expect(TunnelFailure.unknown("weird").message.contains("weird"))
}
