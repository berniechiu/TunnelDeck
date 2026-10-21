import AppKit
import SwiftUI
import TunnelCore

struct LogView: View {
    let lines: [LogLine]
    @Environment(\.strings) private var strings

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(lines) { line in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text(line.date.formatted(date: .omitted, time: .standard)).foregroundStyle(.secondary)
                                Text(verbatim: line.text)
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
                    ContentUnavailableView(strings.noLog, systemImage: "text.alignleft", description: Text(strings.noLogDescription))
                }
            }
            Divider()
            HStack {
                Spacer()
                Button(strings.copyAll, systemImage: "doc.on.doc") {
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
