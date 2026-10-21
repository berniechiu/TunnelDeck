import SwiftUI
import TunnelCore

struct MenuBarView: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let store = model.store {
                header(store)
                Divider()
                if store.tunnels.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(spacing: 2) {
                            ForEach(store.tunnels) { tunnel in
                                TunnelRow(session: store.session(for: tunnel.id))
                            }
                        }
                        .padding(6)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .frame(maxHeight: 420)
                }
                Divider()
                footer(store)
            } else {
                Label(model.loadError ?? "", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .padding()
                Divider()
                Button("結束 TunnelDeck") { NSApp.terminate(nil) }.padding(10)
            }
        }
        .frame(width: 360)
    }

    private func header(_ store: TunnelStore) -> some View {
        HStack {
            Text("TunnelDeck").font(.headline)
            Spacer()
            Text(summary(store)).font(.subheadline).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("還沒有任何 tunnel").foregroundStyle(.secondary)
            Button("新增 tunnel") { openManager() }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private func footer(_ store: TunnelStore) -> some View {
        HStack {
            Button("管理 tunnel…") { openManager() }
            Spacer()
            Button("全部停止") { store.stopAll() }
                .disabled(store.aggregate == .idle)
            Button("結束") { NSApp.terminate(nil) }
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func summary(_ store: TunnelStore) -> String {
        let phases = store.tunnels.map { store.session(for: $0.id).status.phase }
        let failed = phases.filter(\.isFailed).count
        let running = phases.filter(\.isRunning).count
        if failed > 0 { return "\(failed) 條連線失敗" }
        return running > 0 ? "\(running) 條運作中" : "全部停止"
    }

    private func openManager() {
        openWindow(id: ManagerWindow.id)
        NSApp.activate()
    }
}

struct TunnelRow: View {
    let session: TunnelSession

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            StatusDot(phase: session.status.phase).padding(.top, 5)
            VStack(alignment: .leading, spacing: 5) {
                Text(session.tunnel.name).font(.body.weight(.medium))
                HStack(spacing: 4) {
                    ForEach(session.tunnel.forwards) { forward in
                        PortChip(
                            port: forward.localPort,
                            listening: session.sockets.listeningPorts.contains(forward.localPort),
                            clients: session.sockets.clientCounts[forward.localPort] ?? 0
                        )
                    }
                }
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(StatusText.line(for: session.status, now: context.date))
                        .font(.caption)
                        .foregroundStyle(session.status.phase.isFailed ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                        .lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            Toggle(session.tunnel.name, isOn: Binding(
                get: { session.status.phase.isRunning },
                set: { $0 ? session.start() : session.stop() }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .controlSize(.small)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .contentShape(.rect)
    }
}
