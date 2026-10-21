import AppKit
import SwiftUI
import TunnelCore

/// Edits a tunnel as text fields and converts to `Tunnel` on save, so half-typed numbers never reach the store.
struct TunnelEditorView: View {
    private struct ForwardDraft: Identifiable {
        var id: UUID
        var localPort: String
        var remoteHost: String
        var remotePort: String
    }

    let store: TunnelStore
    let original: Tunnel
    let isNew: Bool
    let onFinish: (Tunnel?) -> Void

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
            Section("連線") {
                TextField("名稱", text: $name)
                issueText(issues.contains(.emptyName) ? "請輸入名稱" : nil)
                TextField("主機", text: $host, prompt: Text("bastion.example.com、IP 或 ~/.ssh/config 的 Host"))
                issueText(issues.contains(.invalidHost) ? "請輸入合法的主機名稱或 IP 位址" : nil)
                TextField("使用者", text: $user, prompt: Text("選填"))
                issueText(issues.contains(.invalidUser) ? "只能包含英數與 . _ -，且不能以 - 開頭" : nil)
                TextField("SSH port", text: $port, prompt: Text("選填，預設 22"))
                issueText(issues.contains(.invalidSSHPort) ? "port 須介於 1 到 65535" : nil)
                LabeledContent("金鑰檔") {
                    HStack {
                        Text(identityFile.isEmpty ? "使用 ssh 預設" : identityFile)
                            .foregroundStyle(identityFile.isEmpty ? .secondary : .primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button("選擇…", action: chooseIdentityFile)
                        if !identityFile.isEmpty {
                            Button("清除") { identityFile = "" }
                        }
                    }
                }
                issueText(issues.contains(.invalidIdentityFile) ? "金鑰路徑須以 / 或 ~/ 開頭" : nil)
            }

            Section("轉發") {
                ForEach($forwards) { $forward in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            TextField("本機 port", text: $forward.localPort, prompt: Text("本機 port"))
                                .frame(width: 90)
                            Image(systemName: "arrow.right").foregroundStyle(.secondary)
                            TextField("遠端主機", text: $forward.remoteHost, prompt: Text("遠端主機"))
                            Text(":").foregroundStyle(.secondary)
                            TextField("遠端 port", text: $forward.remotePort, prompt: Text("port"))
                                .frame(width: 70)
                            Button("移除轉發", systemImage: "minus.circle") {
                                forwards.removeAll { $0.id == forward.id }
                            }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                        }
                        .labelsHidden()
                        issueText(forwardIssue(forward))
                    }
                }
                Button("新增轉發", systemImage: "plus") {
                    forwards.append(ForwardDraft(id: UUID(), localPort: "", remoteHost: "", remotePort: "3306"))
                }
                .buttonStyle(.borderless)
                issueText(issues.contains(.noForwards) ? "至少需要一組轉發" : nil)
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
                    Button("取消") { onFinish(nil) }
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
        isNew ? "新增" : (store.session(for: original.id).status.phase.isRunning ? "儲存並重新連線" : "儲存")
    }

    @ViewBuilder
    private func issueText(_ text: String?) -> some View {
        if let text {
            Text(text).font(.caption).foregroundStyle(.red)
        }
    }

    private func forwardIssue(_ forward: ForwardDraft) -> String? {
        if issues.contains(.invalidLocalPort(forward.id)) || issues.contains(.invalidRemotePort(forward.id)) {
            return "port 須介於 1 到 65535"
        }
        if issues.contains(.invalidRemoteHost(forward.id)) { return "請輸入合法的遠端主機名稱或 IP 位址" }
        if let port = Int(forward.localPort), issues.contains(.duplicateLocalPort(port)) {
            return "本機 port \(port) 已被其他轉發使用"
        }
        return nil
    }

    private func load() {
        name = original.name
        host = original.host
        user = original.user ?? ""
        port = original.port.map(String.init) ?? ""
        identityFile = original.identityFile ?? ""
        forwards = original.forwards.map {
            ForwardDraft(
                id: $0.id,
                localPort: $0.localPort == 0 ? "" : String($0.localPort),
                remoteHost: $0.remoteHost,
                remotePort: String($0.remotePort)
            )
        }
    }

    private func save() {
        let trimmed = { (value: String) in value.trimmingCharacters(in: .whitespaces) }
        let tunnel = Tunnel(
            id: original.id,
            name: trimmed(name),
            host: trimmed(host),
            user: trimmed(user).isEmpty ? nil : trimmed(user),
            port: trimmed(port).isEmpty ? nil : Int(trimmed(port)) ?? 0,
            identityFile: identityFile.isEmpty ? nil : identityFile,
            forwards: forwards.map {
                Forward(
                    id: $0.id,
                    localPort: Int(trimmed($0.localPort)) ?? 0,
                    remoteHost: trimmed($0.remoteHost),
                    remotePort: Int(trimmed($0.remotePort)) ?? 0
                )
            }
        )
        do {
            try store.upsert(tunnel)
            issues = []
            saveError = nil
            onFinish(tunnel)
        } catch let failure as ValidationFailure {
            issues = failure.issues
        } catch {
            saveError = "儲存失敗：\(error.localizedDescription)"
        }
    }

    private func chooseIdentityFile() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(filePath: NSHomeDirectory()).appending(path: ".ssh")
        panel.showsHiddenFiles = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let home = NSHomeDirectory()
        identityFile = url.path.hasPrefix(home + "/") ? "~" + url.path.dropFirst(home.count) : url.path
    }
}
