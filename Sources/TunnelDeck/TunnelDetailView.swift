import AppKit
import SwiftUI
import TunnelCore

struct TunnelDetailView: View {
    enum Tab: String, CaseIterable {
        case overview = "概覽"
        case settings = "設定"
        case log = "Log"
    }

    let store: TunnelStore
    let session: TunnelSession
    let onDuplicate: () -> Void
    let onDelete: () -> Void
    @State private var tab = Tab.overview

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            switch tab {
            case .overview: OverviewView(session: session)
            case .settings: TunnelEditorView(store: store, original: session.tunnel, isNew: false) { _ in }
            case .log: LogView(lines: session.log)
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("檢視", selection: $tab) {
                    ForEach(Tab.allCases, id: \.self) { Text($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            ToolbarItem {
                Menu("更多", systemImage: "ellipsis") {
                    Button("複製", action: onDuplicate)
                    Button("刪除…", role: .destructive, action: onDelete)
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            StatusDot(phase: session.status.phase)
            VStack(alignment: .leading, spacing: 3) {
                Text(session.tunnel.name).font(.title2.weight(.semibold))
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(StatusText.line(for: session.status, now: context.date))
                        .foregroundStyle(session.status.phase.isFailed ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                        .textSelection(.enabled)
                }
            }
            Spacer()
            Toggle(session.status.phase.isRunning ? "停止連線" : "啟動連線", isOn: Binding(
                get: { session.status.phase.isRunning },
                set: { $0 ? session.start() : session.stop() }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
}

private struct OverviewView: View {
    let session: TunnelSession

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
                    stat("已連線", connectedFor(now: context.date))
                    stat("累計重連", "\(session.status.reconnectCount) 次")
                    stat("最後斷線", lastDisconnect, detail: lastDisconnectReason)
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
        if case .connected(let since) = session.status.phase { return StatusText.duration(now.timeIntervalSince(since)) }
        return "—"
    }

    private var lastDisconnect: String {
        guard let disconnect = session.status.lastDisconnect else { return "—" }
        return disconnect.at.formatted(date: .omitted, time: .shortened)
    }

    private var lastDisconnectReason: String? {
        session.status.lastDisconnect?.reason.message
    }

    private var forwards: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("轉發").font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 10) {
                GridRow {
                    Text("本機")
                    Text("遠端")
                    Text("狀態")
                    Text("使用中連線")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                Divider().gridCellUnsizedAxes(.horizontal)
                ForEach(session.tunnel.forwards) { forward in
                    let listening = session.sockets.listeningPorts.contains(forward.localPort)
                    GridRow {
                        Text("127.0.0.1:\(String(forward.localPort))").monospacedDigit().textSelection(.enabled)
                        Text("\(forward.remoteHost):\(String(forward.remotePort))").textSelection(.enabled)
                        Label(listening ? "監聽中" : "未監聽", systemImage: listening ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(listening ? Color.green : Color.secondary)
                        Text(String(session.sockets.clientCounts[forward.localPort] ?? 0)).monospacedDigit()
                    }
                }
            }
            if let occupant = session.portOccupant {
                Label(occupantText(occupant), systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .padding(.top, 4)
            }
        }
    }

    private func occupantText(_ occupant: PortOccupant) -> String {
        guard let pid = occupant.pid else { return "占用 port 的程序屬於其他使用者，無法辨識" }
        return "占用 port 的程序：\(occupant.processName ?? "未知")（PID \(pid)）"
    }

    private var command: some View {
        let preview = SSHCommand.preview(for: session.tunnel, homeDirectory: NSHomeDirectory())
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("等效指令").font(.headline)
                Spacer()
                Button("拷貝", systemImage: "doc.on.doc") {
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

struct LogView: View {
    let lines: [LogLine]

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(lines) { line in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text(line.date.formatted(date: .omitted, time: .standard)).foregroundStyle(.secondary)
                                Text(line.text)
                            }
                            .id(line.id)
                        }
                    }
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: lines.last?.id, initial: true) { _, last in
                    if let last { proxy.scrollTo(last, anchor: .bottom) }
                }
            }
            .overlay {
                if lines.isEmpty {
                    ContentUnavailableView("尚無 log", systemImage: "text.alignleft", description: Text("啟動連線後，ssh 的輸出會顯示在這裡。"))
                }
            }
            Divider()
            HStack {
                Spacer()
                Button("拷貝全部", systemImage: "doc.on.doc") {
                    let text = lines.map { "\($0.date.formatted(date: .omitted, time: .standard))  \($0.text)" }.joined(separator: "\n")
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
                .disabled(lines.isEmpty)
            }
            .buttonStyle(.borderless)
            .padding(10)
        }
    }
}
