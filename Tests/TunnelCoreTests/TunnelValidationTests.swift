import Foundation
import Testing
@testable import TunnelCore

private func makeTunnel(
    name: String = "prod",
    host: String = "bastion.example.com",
    user: String? = "deploy",
    port: Int? = 22,
    identityFile: String? = "~/.ssh/id_ed25519",
    forwards: [Forward] = [Forward(id: UUID(), localPort: 3308, remoteHost: "db-primary.internal", remotePort: 3306)]
) -> Tunnel {
    Tunnel(id: UUID(), name: name, host: host, user: user, port: port, identityFile: identityFile, forwards: forwards)
}

@Test func validTunnelHasNoIssues() {
    #expect(validate(makeTunnel(), against: []) == [])
}

@Test func optionalFieldsMayBeEmpty() {
    #expect(validate(makeTunnel(user: nil, port: nil, identityFile: nil), against: []) == [])
    #expect(validate(makeTunnel(user: "", identityFile: ""), against: []) == [])
}

@Test func emptyNameIsRejected() {
    #expect(validate(makeTunnel(name: "  "), against: []) == [.emptyName])
}

@Test(arguments: ["bastion", "bastion.example.com", "10.0.0.1", "fd00::1", "db-1.internal"])
func validHosts(host: String) {
    #expect(validate(makeTunnel(host: host), against: []) == [])
}

@Test(arguments: [
    "", "-oProxyCommand=x", "bastion host", "bastion_1", "a..b", "-x.com", "x-.com",
    String(repeating: "a", count: 64),
    Array(repeating: String(repeating: "a", count: 50), count: 5).joined(separator: ".") + ".abc",
])
func invalidHosts(host: String) {
    #expect(validate(makeTunnel(host: host), against: []) == [.invalidHost])
}

@Test(arguments: ["-l", "root user", "a;b"])
func invalidUsers(user: String) {
    #expect(validate(makeTunnel(user: user), against: []) == [.invalidUser])
}

@Test(arguments: [0, 65536, -1])
func invalidSSHPort(port: Int) {
    #expect(validate(makeTunnel(port: port), against: []) == [.invalidSSHPort])
}

@Test func identityFileMustBeAbsoluteOrHomeRelative() {
    #expect(validate(makeTunnel(identityFile: "id_ed25519"), against: []) == [.invalidIdentityFile])
    #expect(validate(makeTunnel(identityFile: "/Users/me/.ssh/id_ed25519"), against: []) == [])
}

@Test func tunnelNeedsAtLeastOneForward() {
    #expect(validate(makeTunnel(forwards: []), against: []) == [.noForwards])
}

@Test func forwardFieldsAreValidated() {
    let badLocal = Forward(id: UUID(), localPort: 0, remoteHost: "db.internal", remotePort: 3306)
    let badRemoteHost = Forward(id: UUID(), localPort: 3309, remoteHost: "-oX", remotePort: 3306)
    let badRemotePort = Forward(id: UUID(), localPort: 3310, remoteHost: "db.internal", remotePort: 70000)
    let issues = validate(makeTunnel(forwards: [badLocal, badRemoteHost, badRemotePort]), against: [])
    #expect(issues == [
        .invalidLocalPort(badLocal.id),
        .invalidRemoteHost(badRemoteHost.id),
        .invalidRemotePort(badRemotePort.id),
    ])
}

@Test func ipv6RemoteHostIsAllowed() {
    let forward = Forward(id: UUID(), localPort: 3308, remoteHost: "fd00::1", remotePort: 3306)
    #expect(validate(makeTunnel(forwards: [forward]), against: []) == [])
}

@Test func duplicateLocalPortWithinTunnel() {
    let forwards = [
        Forward(id: UUID(), localPort: 3308, remoteHost: "a.internal", remotePort: 3306),
        Forward(id: UUID(), localPort: 3308, remoteHost: "b.internal", remotePort: 3306),
    ]
    #expect(validate(makeTunnel(forwards: forwards), against: []) == [.duplicateLocalPort(3308)])
}

@Test func duplicateLocalPortAcrossTunnels() {
    let other = makeTunnel(name: "other")
    #expect(validate(makeTunnel(), against: [other]) == [.duplicateLocalPort(3308)])
}

@Test func editingSameTunnelIsNotDuplicate() {
    let tunnel = makeTunnel()
    var edited = tunnel
    edited.name = "renamed"
    #expect(validate(edited, against: [tunnel]) == [])
}
