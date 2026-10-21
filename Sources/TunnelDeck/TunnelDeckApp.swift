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

struct MenuBarIcon: View {
    let store: TunnelStore?

    var body: some View {
        switch store?.aggregate ?? .attention {
        case .idle: Image(systemName: "arrow.left.arrow.right.circle")
        case .active: Image(systemName: "arrow.left.arrow.right.circle.fill")
        case .attention: Image(systemName: "exclamationmark.triangle.fill")
        }
    }
}
