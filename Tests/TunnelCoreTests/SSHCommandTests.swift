import Foundation
import Testing
@testable import TunnelCore

private let fixedOptions = [
    "-N", "-T",
    "-o", "BatchMode=yes", "-o", "ExitOnForwardFailure=yes",
    "-o", "ControlMaster=no", "-o", "ControlPath=none", "-o", "ForkAfterAuthentication=no",
    "-o", "ServerAliveInterval=15", "-o", "ServerAliveCountMax=3",
    "-o", "ConnectTimeout=10", "-o", "LogLevel=VERBOSE",
]

@Test func fullArguments() {
    let t = Tunnel(name: "prod", host: "bastion.example.com", user: "deploy", port: 2222,
                   identityFile: "~/.ssh/id_ed25519",
                   forwards: [Forward(localPort: 3308, remoteHost: "db-primary.internal", remotePort: 3306),
                              Forward(localPort: 3309, remoteHost: "db-logs.internal", remotePort: 3306)])
    #expect(SSHCommand.arguments(for: t, homeDirectory: "/Users/me") == fixedOptions + [
        "-l", "deploy", "-p", "2222",
        "-i", "/Users/me/.ssh/id_ed25519", "-o", "IdentitiesOnly=yes",
        "-L", "127.0.0.1:3308:db-primary.internal:3306",
        "-L", "127.0.0.1:3309:db-logs.internal:3306",
        "--", "bastion.example.com",
    ])
}

@Test func minimalArguments() {
    let t = Tunnel(name: "dev", host: "bastion", user: "", identityFile: "",
                   forwards: [Forward(localPort: 3311, remoteHost: "db.internal", remotePort: 3306)])
    #expect(SSHCommand.arguments(for: t, homeDirectory: "/Users/me") == fixedOptions + [
        "-L", "127.0.0.1:3311:db.internal:3306",
        "--", "bastion",
    ])
}

@Test func ipv6RemoteHostIsBracketed() {
    let t = Tunnel(name: "v6", host: "bastion",
                   forwards: [Forward(localPort: 3308, remoteHost: "fd00::1", remotePort: 3306)])
    #expect(SSHCommand.arguments(for: t, homeDirectory: "/Users/me").contains("127.0.0.1:3308:[fd00::1]:3306"))
}

@Test func neverDisablesHostKeyChecking() {
    let t = Tunnel(name: "prod", host: "bastion", user: "deploy", port: 22, identityFile: "/k",
                   forwards: [Forward(localPort: 3308, remoteHost: "db", remotePort: 3306)])
    let joined = SSHCommand.arguments(for: t, homeDirectory: "/Users/me").joined(separator: " ")
    #expect(!joined.contains("StrictHostKeyChecking"))
    #expect(!joined.contains("UserKnownHostsFile"))
}

/// `ssh -G` prints the configuration ssh would use without connecting, so this checks real ssh option precedence.
@Test func sshConfigCannotSendSSHToTheBackground() throws {
    let config = FileManager.default.temporaryDirectory.appending(path: "ssh-config-\(UUID().uuidString)")
    try "Host bastion\n  ForkAfterAuthentication yes\n".write(to: config, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: config) }
    let t = Tunnel(name: "dev", host: "bastion", forwards: [Forward(localPort: 3311, remoteHost: "db", remotePort: 3306)])

    let process = Process()
    process.executableURL = URL(filePath: SSHCommand.executable)
    process.arguments = ["-G", "-F", config.path] + SSHCommand.arguments(for: t, homeDirectory: "/Users/me")
    let output = Pipe()
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    try process.run()
    let resolved = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    process.waitUntilExit()

    #expect(process.terminationStatus == 0)
    #expect(resolved.split(separator: "\n").contains("forkafterauthentication no"))
}

@Test func previewIsPasteableIntoShell() {
    let t = Tunnel(name: "prod", host: "bastion", identityFile: "/Users/me/my keys/id",
                   forwards: [Forward(localPort: 3308, remoteHost: "db", remotePort: 3306)])
    let preview = SSHCommand.preview(for: t, homeDirectory: "/Users/me")
    #expect(preview.hasPrefix("/usr/bin/ssh -N -T -o BatchMode=yes"))
    #expect(preview.contains("-i '/Users/me/my keys/id'"))
    #expect(preview.hasSuffix("-L 127.0.0.1:3308:db:3306 -- bastion"))
}
