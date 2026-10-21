import AppKit
import SwiftUI
import TunnelCore

struct TunnelDetailView: View {
    enum Tab: CaseIterable {
        case overview, configuration, log
    }

    let store: TunnelStore
    let session: TunnelSession
    let onDuplicate: () -> Void
    let onDelete: () -> Void
    @Environment(\.strings) private var strings
    @State private var tab = Tab.overview

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            switch tab {
            case .overview: OverviewView(session: session)
            case .configuration: TunnelEditorView(store: store, original: session.tunnel, isNew: false) { _ in }
            case .log: LogView(lines: session.log)
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker(strings.overview, selection: $tab) {
                    ForEach(Tab.allCases, id: \.self) { Text(title(for: $0)) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            ToolbarItem {
                Menu(strings.more, systemImage: "ellipsis") {
                    Button(strings.duplicate, action: onDuplicate)
                    Button(strings.deleteEllipsis, role: .destructive, action: onDelete)
                }
            }
        }
    }

    private func title(for tab: Tab) -> String {
        switch tab {
        case .overview: strings.overview
        case .configuration: strings.configuration
        case .log: strings.log
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            StatusDot(phase: session.status.phase)
            VStack(alignment: .leading, spacing: 3) {
                Text(session.tunnel.name).font(.title2.weight(.semibold))
                StatusLine(status: session.status).textSelection(.enabled)
            }
            Spacer()
            Toggle(session.status.phase.isRunning ? strings.stopConnection : strings.startConnection, isOn: session.runningBinding)
            .toggleStyle(.switch)
            .labelsHidden()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
}

private struct OverviewView: View {
    let session: TunnelSession
    @Environment(\.strings) private var strings

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                stats
                forwards
                command
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var stats: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Grid(alignment: .leading, horizontalSpacing: 32, verticalSpacing: 8) {
                GridRow {
                    stat(strings.uptime, connectedFor(now: context.date))
                    stat(strings.reconnects, String(session.status.reconnectCount))
                    stat(strings.lastDisconnect, lastDisconnect, detail: session.status.lastDisconnect.map { strings.failure($0.reason) })
                }
            }
        }
    }

    private func stat(_ title: String, _ value: String, detail: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.medium)).monospacedDigit()
            if let detail {
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func connectedFor(now: Date) -> String {
        if case .connected(let since) = session.status.phase { return strings.duration(now.timeIntervalSince(since)) }
        return "—"
    }

    private var lastDisconnect: String {
        session.status.lastDisconnect?.at.formatted(date: .omitted, time: .shortened) ?? "—"
    }

    private var forwards: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(strings.forwards).font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 10) {
                GridRow {
                    Text(strings.local)
                    Text(strings.remote)
                    Text(strings.state)
                    Text(strings.clients)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                Divider().gridCellUnsizedAxes(.horizontal)
                ForEach(session.tunnel.forwards) { forward in
                    let listening = session.sockets.isListening(on: forward.localPort)
                    GridRow {
                        Text(verbatim: "127.0.0.1:\(forward.localPort)").monospacedDigit().textSelection(.enabled)
                        Text(verbatim: "\(forward.remoteHost):\(forward.remotePort)").textSelection(.enabled)
                        Label(listening ? strings.listening : strings.notListening, systemImage: listening ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(listening ? Color.green : Color.secondary)
                        Text(String(session.sockets.clients(on: forward.localPort))).monospacedDigit()
                    }
                }
            }
        }
    }

    private var command: some View {
        let preview = SSHCommand.preview(for: session.tunnel, homeDirectory: NSHomeDirectory())
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(strings.equivalentCommand).font(.headline)
                Spacer()
                Button(strings.copy, systemImage: "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(preview, forType: .string)
                }
                .buttonStyle(.borderless)
            }
            Text(preview)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 8))
        }
    }
}
