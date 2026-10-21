import SwiftUI
import TunnelCore

struct MenuBarView: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.strings) private var strings

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let store = model.store {
                header(store)
                Divider()
                if store.sessions.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(spacing: 2) {
                            ForEach(store.sessions) { session in
                                TunnelRow(session: session) { openSettings(.tunnel(session.id)) }
                            }
                        }
                        .padding(6)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .frame(maxHeight: 460)
                }
                Divider()
                footer(store)
            } else {
                Label(strings.loadError(ConfigStore.defaultURL.path, model.loadError ?? ""), systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .padding()
                Divider()
                Button(strings.quitApp) { NSApp.terminate(nil) }.padding(10)
            }
        }
        .frame(width: 380)
    }

    private func header(_ store: TunnelStore) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "TunnelDeck").font(.headline)
                Text(summary(store)).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Button(strings.settings, systemImage: "gearshape") { openSettings(nil) }
                .buttonStyle(.bordered)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text(strings.noTunnels).foregroundStyle(.secondary)
            Button(strings.addTunnel) { openSettings(nil) }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private func footer(_ store: TunnelStore) -> some View {
        HStack {
            Button(strings.stopAll) { store.stopAll() }
                .disabled(store.aggregate == .idle)
            Spacer()
            Button(strings.quit) { NSApp.terminate(nil) }
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func summary(_ store: TunnelStore) -> String {
        let phases = store.sessions.map(\.status.phase)
        let failed = phases.filter(\.isFailed).count
        let connecting = phases.filter(\.isTransient).count
        let connected = phases.filter { if case .connected = $0 { true } else { false } }.count
        if failed > 0 { return strings.summaryFailed(failed) }
        if connecting > 0 { return strings.summaryConnecting(connecting) }
        return connected > 0 ? strings.summaryConnected(connected) : strings.summaryStopped
    }

    private func openSettings(_ selection: SettingsSelection?) {
        if let selection { model.selection = selection }
        openWindow(id: SettingsWindow.id)
        NSApp.activate()
    }
}

private struct TunnelRow: View {
    let session: TunnelSession
    let onOpen: () -> Void
    @Environment(\.strings) private var strings
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            StatusDot(phase: session.status.phase).padding(.top, 5)
            VStack(alignment: .leading, spacing: 5) {
                Text(session.tunnel.name).font(.body.weight(.medium))
                Text(destination).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                ForEach(session.tunnel.forwards) { forward in
                    HStack(spacing: 6) {
                        PortChip(
                            port: forward.localPort,
                            listening: session.sockets.listeningPorts.contains(forward.localPort),
                            clients: session.sockets.clientCounts[forward.localPort] ?? 0
                        )
                        Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.tertiary)
                        Text(verbatim: "\(forward.remoteHost):\(forward.remotePort)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    statusLine(now: context.date)
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
        .background(hovering ? AnyShapeStyle(.quaternary.opacity(0.6)) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 8))
        .contentShape(.rect)
        .onHover { hovering = $0 }
        .onTapGesture(perform: onOpen)
    }

    private var destination: String {
        let tunnel = session.tunnel
        let user = tunnel.user.map { $0.isEmpty ? "" : "\($0)@" } ?? ""
        let port = tunnel.port.map { $0 == 22 ? "" : ":\($0)" } ?? ""
        return user + tunnel.host + port
    }

    @ViewBuilder
    private func statusLine(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(strings.line(for: session.status, now: now))
                .foregroundStyle(session.status.phase.isFailed ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
            if session.status.reconnectCount > 0, session.status.phase.isRunning {
                Label(strings.reconnectCount(session.status.reconnectCount), systemImage: "arrow.clockwise")
                    .foregroundStyle(.tertiary)
            }
        }
        .font(.caption)
    }
}
