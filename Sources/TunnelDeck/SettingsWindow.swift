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
                    description: Text(model.loadErrorText(strings))
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
    @State private var showingPreferences = false

    var body: some View {
        NavigationSplitView {
            List(selection: $model.selection) {
                Section(strings.tunnels) {
                    ForEach(store.sessions) { session in
                        SidebarRow(session: session)
                            .contextMenu {
                                Button(strings.duplicate) { duplicate(session.id) }
                                Button(strings.deleteEllipsis, role: .destructive) { confirmingDelete = session.tunnel }
                            }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button(strings.preferences, systemImage: "gearshape") { showingPreferences = true }
                    .buttonStyle(.borderless)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 240)
            .toolbar {
                ToolbarItem {
                    Button(strings.addTunnel, systemImage: "plus") {
                        model.selection = nil
                        draft = Tunnel(name: "", host: "", forwards: [.blank])
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
        .sheet(isPresented: $showingPreferences) { PreferencesView() }
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
                if let saved { model.selection = saved.id }
            }
            .id(draft.id)
        } else if let id = model.selection, let session = store.session(for: id) {
            TunnelDetailView(store: store, session: session) {
                duplicate(id)
            } onDelete: {
                confirmingDelete = session.tunnel
            }
            .id(id)
        } else {
            ContentUnavailableView(strings.selectTunnel, systemImage: "arrow.left.arrow.right.circle")
        }
    }

    private func duplicate(_ id: Tunnel.ID) {
        model.selection = nil
        draft = store.duplicate(id, named: strings.duplicateName)
    }

    private func delete(_ id: Tunnel.ID) {
        do {
            try store.delete(id)
            if model.selection == id { model.selection = nil }
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

private struct PreferencesView: View {
    @AppStorage(AppLanguage.storageKey) private var language = AppLanguage.default
    @AppStorage(AppAppearance.storageKey) private var appearance = AppAppearance.default
    @Environment(\.strings) private var strings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            Form {
                Picker(strings.language, selection: $language) {
                    ForEach(AppLanguage.allCases) { Text(verbatim: $0.displayName).tag($0) }
                }
                Picker(strings.appearance, selection: $appearance) {
                    ForEach(AppAppearance.allCases) { Text(strings.appearanceName($0)).tag($0) }
                }
            }
            .formStyle(.grouped)
            Button(strings.done) { dismiss() }
                .keyboardShortcut(.defaultAction)
                .padding([.horizontal, .bottom], 20)
        }
        .frame(width: 380)
    }
}
