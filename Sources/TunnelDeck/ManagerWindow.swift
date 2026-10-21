import SwiftUI
import TunnelCore

struct ManagerWindow: View {
    static let id = "manager"
    let model: AppModel

    var body: some View {
        Group {
            if let store = model.store {
                TunnelManager(store: store)
            } else {
                ContentUnavailableView("無法啟動", systemImage: "exclamationmark.triangle", description: Text(model.loadError ?? ""))
            }
        }
        .frame(minWidth: 820, minHeight: 520)
    }
}

private struct TunnelManager: View {
    let store: TunnelStore
    @State private var selection: Tunnel.ID?
    @State private var draft: Tunnel?
    @State private var confirmingDelete: Tunnel?
    @State private var deleteError: String?

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(store.tunnels) { tunnel in
                    SidebarRow(session: store.session(for: tunnel.id)).tag(tunnel.id)
                        .contextMenu {
                            Button("複製") { duplicate(tunnel.id) }
                            Button("刪除…", role: .destructive) { confirmingDelete = tunnel }
                        }
                }
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 240)
            .toolbar {
                ToolbarItem {
                    Button("新增 tunnel", systemImage: "plus") {
                        selection = nil
                        draft = Tunnel(name: "", host: "", forwards: [Forward(localPort: 0, remoteHost: "", remotePort: 3306)])
                    }
                }
            }
        } detail: {
            if let draft {
                TunnelEditorView(store: store, original: draft, isNew: true) { saved in
                    self.draft = nil
                    if let saved { selection = saved.id }
                }
                .id(draft.id)
            } else if let selection, store.tunnels.contains(where: { $0.id == selection }) {
                TunnelDetailView(store: store, session: store.session(for: selection)) {
                    duplicate(selection)
                } onDelete: {
                    confirmingDelete = store.tunnels.first { $0.id == selection }
                }
                .id(selection)
            } else {
                ContentUnavailableView("選擇一條 tunnel", systemImage: "arrow.left.arrow.right.circle")
            }
        }
        .onChange(of: selection) { _, newValue in
            if newValue != nil { draft = nil }
        }
        .confirmationDialog(
            "要刪除「\(confirmingDelete?.name ?? "")」嗎？",
            isPresented: Binding(get: { confirmingDelete != nil }, set: { if !$0 { confirmingDelete = nil } }),
            presenting: confirmingDelete
        ) { tunnel in
            Button("刪除", role: .destructive) { delete(tunnel.id) }
        } message: { _ in
            Text("執行中的連線會先中斷。")
        }
        .alert("刪除失敗", isPresented: Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })) {
        } message: {
            Text(deleteError ?? "")
        }
    }

    private func duplicate(_ id: Tunnel.ID) {
        selection = nil
        draft = store.duplicate(id)
    }

    private func delete(_ id: Tunnel.ID) {
        do {
            try store.delete(id)
            if selection == id { selection = nil }
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
