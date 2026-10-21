import SwiftUI
import TunnelCore

struct SettingsWindow: View {
    static let id = "settings"
    let model: AppModel
    @Environment(\.strings) private var strings

    var body: some View {
        Group {
            if let store = model.store {
                SettingsContent(model: model, store: store)
            } else {
                ContentUnavailableView(
                    strings.cannotStart,
                    systemImage: "exclamationmark.triangle",
                    description: Text(strings.loadError(ConfigStore.defaultURL.path, model.loadError ?? ""))
                )
            }
        }
        .frame(minWidth: 820, minHeight: 540)
    }
}

private struct SettingsContent: View {
    @Bindable var model: AppModel
    let store: TunnelStore
    @Environment(\.strings) private var strings
    @State private var draft: Tunnel?
    @State private var confirmingDelete: Tunnel?
    @State private var deleteError: String?

    var body: some View {
        NavigationSplitView {
            List(selection: $model.selection) {
                Section(strings.tunnels) {
                    ForEach(store.sessions) { session in
                        SidebarRow(session: session).tag(SettingsSelection.tunnel(session.id))
                            .contextMenu {
                                Button(strings.duplicate) { duplicate(session.id) }
                                Button(strings.deleteEllipsis, role: .destructive) { confirmingDelete = session.tunnel }
                            }
                    }
                }
                Section {
                    Label(strings.general, systemImage: "gearshape").tag(SettingsSelection.general)
                }
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 240)
            .toolbar {
                ToolbarItem {
                    Button(strings.addTunnel, systemImage: "plus") {
                        model.selection = nil
                        draft = Tunnel(name: "", host: "", forwards: [Forward(localPort: 0, remoteHost: "", remotePort: 3306)])
                    }
                }
            }
        } detail: {
            detail
        }
        .onChange(of: model.selection) { _, newValue in
            if newValue != nil { draft = nil }
        }
        .confirmationDialog(
            strings.deleteConfirm(confirmingDelete?.name ?? ""),
            isPresented: Binding(get: { confirmingDelete != nil }, set: { if !$0 { confirmingDelete = nil } }),
            presenting: confirmingDelete
        ) { tunnel in
            Button(strings.delete, role: .destructive) { delete(tunnel.id) }
        } message: { _ in
            Text(strings.deleteMessage)
        }
        .alert(strings.deleteFailed, isPresented: Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })) {
        } message: {
            Text(deleteError ?? "")
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let draft {
            TunnelEditorView(store: store, original: draft, isNew: true) { saved in
                self.draft = nil
                if let saved { model.selection = .tunnel(saved.id) }
            }
            .id(draft.id)
        } else {
            switch model.selection {
            case .general:
                GeneralSettingsView()
            case .tunnel(let id):
                if let session = store.session(for: id) {
                    TunnelDetailView(store: store, session: session) {
                        duplicate(id)
                    } onDelete: {
                        confirmingDelete = session.tunnel
                    }
                    .id(id)
                } else {
                    placeholder
                }
            case nil:
                placeholder
            }
        }
    }

    private var placeholder: some View {
        ContentUnavailableView(strings.selectTunnel, systemImage: "arrow.left.arrow.right.circle")
    }

    private func duplicate(_ id: Tunnel.ID) {
        model.selection = nil
        draft = store.duplicate(id, named: strings.duplicateName)
    }

    private func delete(_ id: Tunnel.ID) {
        do {
            try store.delete(id)
            if model.selection == .tunnel(id) { model.selection = nil }
        } catch {
            deleteError = error.localizedDescription
        }
    }
}

private struct SidebarRow: View {
    let session: TunnelSession

    var body: some View {
        HStack(spacing: 8) {
            StatusDot(phase: session.status.phase)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.tunnel.name).lineLimit(1)
                Text(session.tunnel.forwards.map { String($0.localPort) }.joined(separator: ", "))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct GeneralSettingsView: View {
    @AppStorage(AppLanguage.storageKey) private var language = AppLanguage.default
    @Environment(\.strings) private var strings

    var body: some View {
        Form {
            Picker(strings.language, selection: $language) {
                ForEach(AppLanguage.allCases) { Text(verbatim: $0.displayName).tag($0) }
            }
        }
        .formStyle(.grouped)
    }
}
