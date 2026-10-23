import AppKit
import SwiftUI
import TunnelCore

extension Forward {
    /// A new forward in the editor; local port 0 shows as an empty field.
    static var blank: Forward { Forward(localPort: 0, remoteHost: "", remotePort: 3306) }
}

/// Edits a tunnel as text fields and converts to `Tunnel` on save, so half-typed numbers never reach the store.
struct TunnelEditorView: View {
    private struct ForwardDraft: Identifiable {
        var id: UUID
        var localPort: String
        var remoteHost: String
        var remotePort: String

        init(_ forward: Forward) {
            id = forward.id
            localPort = forward.localPort == 0 ? "" : String(forward.localPort)
            remoteHost = forward.remoteHost
            remotePort = String(forward.remotePort)
        }

        /// What gets saved: trimmed, and 0 for text that isn't a number, which validation rejects.
        var value: Forward {
            Forward(id: id, localPort: Int(trimmed(localPort)) ?? 0, remoteHost: trimmed(remoteHost), remotePort: Int(trimmed(remotePort)) ?? 0)
        }
    }

    let store: TunnelStore
    let original: Tunnel
    let isNew: Bool
    let onFinish: (Tunnel?) -> Void

    @Environment(\.strings) private var strings
    @State private var name = ""
    @State private var host = ""
    @State private var user = ""
    @State private var port = ""
    @State private var identityFile = ""
    @State private var forwards: [ForwardDraft] = []
    @State private var issues: [ValidationIssue] = []
    @State private var saveError: String?

    var body: some View {
        Form {
            Section(strings.connection) {
                TextField(strings.name, text: $name)
                issueText(.emptyName)
                TextField(strings.host, text: $host, prompt: Text(strings.hostPrompt))
                issueText(.invalidHost)
                TextField(strings.user, text: $user, prompt: Text(strings.optional))
                issueText(.invalidUser)
                TextField(strings.sshPort, text: $port, prompt: Text(strings.sshPortPrompt))
                issueText(.invalidSSHPort)
                LabeledContent(strings.identityFile) {
                    HStack {
                        Text(identityFile.isEmpty ? strings.sshDefault : identityFile)
                            .foregroundStyle(identityFile.isEmpty ? .secondary : .primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button(strings.choose, action: chooseIdentityFile)
                        if !identityFile.isEmpty {
                            Button(strings.clear) { identityFile = "" }
                        }
                    }
                }
                issueText(.invalidIdentityFile)
            }

            Section(strings.forwards) {
                ForEach($forwards) { $forward in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            TextField(strings.localPort, text: $forward.localPort, prompt: Text(strings.localPort))
                                .frame(width: 90)
                            Image(systemName: "arrow.right").foregroundStyle(.secondary)
                            TextField(strings.remoteHost, text: $forward.remoteHost, prompt: Text(strings.remoteHost))
                            Text(verbatim: ":").foregroundStyle(.secondary)
                            TextField(strings.remotePort, text: $forward.remotePort, prompt: Text(strings.remotePort))
                                .frame(width: 70)
                            Button(strings.removeForward, systemImage: "minus.circle") {
                                forwards.removeAll { $0.id == forward.id }
                            }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                        }
                        .labelsHidden()
                        forwardIssue(forward).map { Text($0).font(.caption).foregroundStyle(.red) }
                    }
                }
                Button(strings.addForward, systemImage: "plus") {
                    forwards.append(ForwardDraft(.blank))
                }
                .buttonStyle(.borderless)
                issueText(.noForwards)
            }

            if let saveError {
                Text(saveError).foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Spacer()
                if isNew {
                    Button(strings.cancel) { onFinish(nil) }
                }
                Button(saveTitle, action: save)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .onAppear(perform: load)
    }

    private var saveTitle: String {
        if isNew { return strings.add }
        return store.session(for: original.id)?.status.phase.isRunning == true ? strings.saveAndReconnect : strings.save
    }

    @ViewBuilder
    private func issueText(_ issue: ValidationIssue) -> some View {
        if issues.contains(issue) {
            Text(strings.validation(issue)).font(.caption).foregroundStyle(.red)
        }
    }

    private func forwardIssue(_ forward: ForwardDraft) -> String? {
        let candidates: [ValidationIssue] = [
            .invalidLocalPort(forward.id), .invalidRemoteHost(forward.id), .invalidRemotePort(forward.id),
            .duplicateLocalPort(forward.value.localPort),
        ]
        return candidates.first(where: issues.contains).map(strings.validation)
    }

    private func load() {
        name = original.name
        host = original.host
        user = original.user ?? ""
        port = original.port.map(String.init) ?? ""
        identityFile = original.identityFile ?? ""
        forwards = original.forwards.map(ForwardDraft.init)
    }

    private func save() {
        let tunnel = Tunnel(
            id: original.id,
            name: trimmed(name),
            host: trimmed(host),
            user: trimmed(user).nonEmpty,
            port: trimmed(port).nonEmpty.map { Int($0) ?? 0 },
            identityFile: identityFile.nonEmpty,
            forwards: forwards.map(\.value)
        )
        do {
            try store.upsert(tunnel)
            issues = []
            saveError = nil
            onFinish(tunnel)
        } catch let failure as ValidationFailure {
            issues = failure.issues
        } catch {
            saveError = strings.saveFailed(error.localizedDescription)
        }
    }

    private func chooseIdentityFile() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(filePath: NSHomeDirectory()).appending(path: ".ssh")
        panel.showsHiddenFiles = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        identityFile = (url.path as NSString).abbreviatingWithTildeInPath
    }
}

private func trimmed(_ text: String) -> String {
    text.trimmingCharacters(in: .whitespaces)
}
