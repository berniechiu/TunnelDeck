import Foundation

public struct ConfigStore: Sendable {
    public struct UnsupportedVersion: Error {
        public var version: Int
    }

    private struct File: Codable {
        var version: Int
        var tunnels: [Tunnel]
    }

    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public static var defaultURL: URL {
        URL.applicationSupportDirectory.appending(path: "TunnelDeck/tunnels.json")
    }

    public func load() throws -> [Tunnel] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let file = try JSONDecoder().decode(File.self, from: Data(contentsOf: fileURL))
        guard file.version == 1 else { throw UnsupportedVersion(version: file.version) }
        return file.tunnels
    }

    public func save(_ tunnels: [Tunnel]) throws {
        let fm = FileManager.default
        let dir = fileURL.deletingLastPathComponent()
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(File(version: 1, tunnels: tunnels)).write(to: fileURL, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }
}
