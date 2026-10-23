import Foundation

public struct Forward: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var localPort: Int
    public var remoteHost: String
    public var remotePort: Int

    public init(id: UUID = UUID(), localPort: Int, remoteHost: String, remotePort: Int) {
        self.id = id
        self.localPort = localPort
        self.remoteHost = remoteHost
        self.remotePort = remotePort
    }
}

public struct Tunnel: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var host: String
    public var user: String?
    public var port: Int?
    public var identityFile: String?
    public var forwards: [Forward]

    public init(
        id: UUID = UUID(),
        name: String,
        host: String,
        user: String? = nil,
        port: Int? = nil,
        identityFile: String? = nil,
        forwards: [Forward]
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.user = user
        self.port = port
        self.identityFile = identityFile
        self.forwards = forwards
    }
}

public enum ValidationIssue: Equatable, Sendable {
    case emptyName
    case invalidHost
    case invalidUser
    case invalidSSHPort
    case invalidIdentityFile
    case noForwards
    case invalidLocalPort(Forward.ID)
    case invalidRemoteHost(Forward.ID)
    case invalidRemotePort(Forward.ID)
    case duplicateLocalPort(Int)
}

public struct ValidationFailure: Error, Equatable {
    public var issues: [ValidationIssue]
}

public func validate(_ tunnel: Tunnel, against others: [Tunnel]) -> [ValidationIssue] {
    var issues: [ValidationIssue] = []

    if tunnel.name.trimmingCharacters(in: .whitespaces).isEmpty { issues.append(.emptyName) }
    if !isValidHost(tunnel.host) { issues.append(.invalidHost) }
    if let user = tunnel.user?.nonEmpty, user.wholeMatch(of: /[A-Za-z0-9_][A-Za-z0-9._-]*/) == nil {
        issues.append(.invalidUser)
    }
    if let port = tunnel.port, !isValidPort(port) { issues.append(.invalidSSHPort) }
    if let path = tunnel.identityFile?.nonEmpty, !(path.hasPrefix("/") || path.hasPrefix("~/")) {
        issues.append(.invalidIdentityFile)
    }
    if tunnel.forwards.isEmpty { issues.append(.noForwards) }

    for forward in tunnel.forwards {
        if !isValidPort(forward.localPort) { issues.append(.invalidLocalPort(forward.id)) }
        if !isValidHost(forward.remoteHost) { issues.append(.invalidRemoteHost(forward.id)) }
        if !isValidPort(forward.remotePort) { issues.append(.invalidRemotePort(forward.id)) }
    }

    let takenElsewhere = Set(others.filter { $0.id != tunnel.id }.flatMap { $0.forwards.map(\.localPort) })
    var seen = Set<Int>()
    var duplicates: [Int] = []
    for port in tunnel.forwards.map(\.localPort) {
        if (!seen.insert(port).inserted || takenElsewhere.contains(port)) && !duplicates.contains(port) {
            duplicates.append(port)
        }
    }
    issues += duplicates.map(ValidationIssue.duplicateLocalPort)

    return issues
}

func isIPv6Address(_ value: String) -> Bool {
    var address = in6_addr()
    return inet_pton(AF_INET6, value, &address) == 1
}

private func isValidPort(_ port: Int) -> Bool { (1...65535).contains(port) }

private func isValidHost(_ host: String) -> Bool {
    var ipv4 = in_addr()
    if inet_pton(AF_INET, host, &ipv4) == 1 || isIPv6Address(host) { return true }
    guard (1...253).contains(host.count) else { return false }
    return host.split(separator: ".", omittingEmptySubsequences: false).allSatisfy { label in
        label.wholeMatch(of: /[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?/) != nil
    }
}

extension String {
    /// nil for an empty string, since an empty optional field means the same as a missing one.
    public var nonEmpty: String? { isEmpty ? nil : self }
}
