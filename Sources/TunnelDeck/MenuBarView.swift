import SwiftUI
import TunnelCore

struct MenuBarView: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.strings) private var strings
    @State private var listHeight: CGFloat = 0

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
                                TunnelRow(session: session) { openSettings(session.id) }
                            }
                        }
                        .padding(6)
                        .onGeometryChange(for: CGFloat.self, of: \.size.height) { listHeight = $0 }
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    // The menu bar window sizes itself to the content's minimum, which for a ScrollView is
                    // nothing, so give it the list's own height up to a cap.
                    .frame(height: min(listHeight, 460))
                }
                Divider()
                footer(store)
            } else {
                Label(model.loadErrorText(strings), systemImage: "exclamationmark.triangle.fill")
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
        func count(_ matches: (TunnelPhase) -> Bool) -> Int { phases.filter(matches).count }
        return switch store.aggregate {
        case .failed: strings.summaryFailed(count(\.isFailed))
        case .connecting: strings.summaryConnecting(count(\.isTransient))
        case .connected: strings.summaryConnected(count(\.isConnected))
        case .idle: strings.summaryStopped
        }
    }

    private func openSettings(_ selection: Tunnel.ID?) {
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
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            PortChip(
                                port: forward.localPort,
                                listening: session.sockets.isListening(on: forward.localPort),
                                clients: session.sockets.clients(on: forward.localPort)
                            )
                            Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.tertiary)
                            Text(verbatim: "\(forward.remoteHost):\(forward.remotePort)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        ClientList(clients: session.clients[forward.localPort] ?? []).padding(.leading, 8)
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    StatusLine(status: session.status)
                        .lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)
                    if session.status.reconnectCount > 0, session.status.phase.isRunning {
                        Label(strings.reconnectCount(session.status.reconnectCount), systemImage: "arrow.clockwise")
                            .foregroundStyle(.tertiary)
                    }
                }
                .font(.caption)
            }
            Spacer(minLength: 8)
            Toggle(session.tunnel.name, isOn: session.runningBinding)
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
        let user = tunnel.user?.nonEmpty.map { "\($0)@" } ?? ""
        let port = tunnel.port.map { $0 == 22 ? "" : ":\($0)" } ?? ""
        return user + tunnel.host + port
    }
}
