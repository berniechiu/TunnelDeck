import SwiftUI
import TunnelCore

@main
struct TunnelDeckApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(model: delegate.model)
        } label: {
            MenuBarIcon(store: delegate.model.store)
        }
        .menuBarExtraStyle(.window)

        Window("TunnelDeck", id: ManagerWindow.id) {
            ManagerWindow(model: delegate.model)
        }
        .defaultLaunchBehavior(.suppressed)
    }
}

@MainActor
final class AppModel {
    let store: TunnelStore?
    let loadError: String?
    private let notifier = Notifier()
    private var events: SystemEvents?

    init() {
        let notifier = notifier
        do {
            let store = try TunnelStore(config: ConfigStore(fileURL: ConfigStore.defaultURL)) { tunnel, failure in
                notifier.post(tunnel: tunnel, failure: failure)
            }
            self.store = store
            loadError = nil
            events = SystemEvents { store.networkChanged() }
        } catch {
            store = nil
            loadError = "無法讀取設定檔 \(ConfigStore.defaultURL.path)：\(error.localizedDescription)"
        }
        notifier.requestAuthorization()
    }
}

/// Colored by the most urgent tunnel state; the symbol shape changes too, so the state reads without color.
struct MenuBarIcon: View {
    let store: TunnelStore?

    var body: some View {
        Image(nsImage: Self.image(for: store?.aggregate ?? .failed))
    }

    private static func image(for state: AggregateState) -> NSImage {
        let (symbol, color, label): (String, NSColor?, String) = switch state {
        case .idle: ("arrow.left.arrow.right.circle", nil, "全部停止")
        case .connected: ("arrow.left.arrow.right.circle.fill", .systemGreen, "已連線")
        case .connecting: ("arrow.triangle.2.circlepath.circle.fill", .systemOrange, "連線中")
        case .failed: ("exclamationmark.triangle.fill", .systemRed, "連線失敗")
        }
        var configuration = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        if let color { configuration = configuration.applying(.init(paletteColors: [color])) }
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "TunnelDeck：\(label)")!
            .withSymbolConfiguration(configuration)!
        // Template images are tinted to the menu bar's own color, which would drop the state color.
        image.isTemplate = color == nil
        return image
    }
}
