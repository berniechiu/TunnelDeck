import Foundation
import Testing
@testable import TunnelCore

private func temporaryStore() throws -> (ConfigStore, URL) {
    let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let file = dir.appending(path: "nested/tunnels.json")
    return (ConfigStore(fileURL: file), file)
}

private func permissions(_ url: URL) throws -> Int {
    try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as! Int
}

@Test func missingFileLoadsEmpty() throws {
    let (store, _) = try temporaryStore()
    #expect(try store.load() == [])
}

@Test func roundTrips() throws {
    let (store, _) = try temporaryStore()
    let tunnels = [
        Tunnel(name: "prod", host: "bastion", user: "deploy", port: 22, identityFile: "~/.ssh/id",
               forwards: [Forward(localPort: 3308, remoteHost: "db", remotePort: 3306)]),
        Tunnel(name: "dev", host: "10.0.0.1", forwards: [Forward(localPort: 3311, remoteHost: "db", remotePort: 3306)]),
    ]
    try store.save(tunnels)
    #expect(try store.load() == tunnels)
}

@Test func savedFileIsPrivate() throws {
    let (store, file) = try temporaryStore()
    try store.save([])
    #expect(try permissions(file) == 0o600)
    #expect(try permissions(file.deletingLastPathComponent()) == 0o700)
}

@Test func unknownVersionIsRejected() throws {
    let (store, file) = try temporaryStore()
    try store.save([])
    try Data(#"{"version": 2, "tunnels": []}"#.utf8).write(to: file)
    #expect(throws: (any Error).self) { try store.load() }
}

@Test func defaultLocation() {
    #expect(ConfigStore.defaultURL.path.hasSuffix("Library/Application Support/TunnelDeck/tunnels.json"))
}
