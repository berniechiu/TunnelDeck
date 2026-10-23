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
    ("bind [127.0.0.1]:3308: Address already in use\nchannel_setup_fwd_listener_tcpip: cannot listen to port: 3308\nCould not request local forwarding.\n", .portInUse(3308, nil)),
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

let nonRetryableFailures: [TunnelFailure] = [.hostKeyChanged, .hostKeyUnknown, .authenticationFailed, .portInUse(3308, nil), .configError("x")]
let retryableFailures: [TunnelFailure] = [.hostNotFound, .connectionRefused, .timedOut, .networkUnreachable, .connectionLost, .unknown("x")]

@Test func retryability() {
    #expect(nonRetryableFailures.allSatisfy { !$0.isRetryable })
    #expect(retryableFailures.allSatisfy { $0.isRetryable })
}
