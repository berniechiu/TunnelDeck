import AppKit
import SwiftUI
import TunnelCore

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
