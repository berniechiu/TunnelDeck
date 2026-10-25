import SwiftUI
import TunnelCore

@main
struct TunnelDeckApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @AppStorage(AppLanguage.storageKey) private var language = AppLanguage.default
    @AppStorage(AppAppearance.storageKey) private var appearance = AppAppearance.default

    var body: some Scene {
        let strings = Strings.for(language)
        MenuBarExtra {
            MenuBarView(model: delegate.model)
                .environment(\.strings, strings)
        } label: {
            MenuBarIcon(store: delegate.model.store)
        }
        .menuBarExtraStyle(.window)
        // Set on the app rather than per view, so alerts and the file picker follow it too. Attached to the
        // menu bar scene because it always exists; the status item keeps the menu bar's own appearance.
        .onChange(of: appearance, initial: true) { NSApp.appearance = appearance.nsAppearance }

        Window("TunnelDeck", id: SettingsWindow.id) {
            SettingsWindow(model: delegate.model)
                .environment(\.strings, strings)
        }
        .defaultLaunchBehavior(.suppressed)
    }
}

extension EnvironmentValues {
    @Entry var strings = Strings.for(.default)
}

extension AppAppearance {
    /// Nil hands the choice back to macOS.
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

@MainActor @Observable
final class AppModel {
    let store: TunnelStore?
    /// Why the settings file could not be read; the store is nil in that case.
    let loadError: String?
    var selection: Tunnel.ID?
    private let notifier = Notifier()
    @ObservationIgnored private var events: SystemEvents?

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
            loadError = error.localizedDescription
        }
        notifier.requestAuthorization()
    }

    func loadErrorText(_ strings: Strings) -> String {
        strings.loadError(ConfigStore.defaultURL.path, loadError ?? "")
    }
}

/// The tunnel symbol plus a colored badge for the most urgent state. With nothing running it is a plain
/// template image like other idle menu bar items.
struct MenuBarIcon: View {
    let store: TunnelStore?
    // Read here rather than from the environment, so a language change redraws the separately hosted status item.
    @AppStorage(AppLanguage.storageKey) private var language = AppLanguage.default

    // Reading `aggregate` here, in a view body, is what lets SwiftUI redraw the icon when a tunnel changes state.
    var body: some View {
        let (image, description) = Self.image(for: store?.aggregate ?? .failed, strings: Strings.for(language))
        Image(nsImage: image).accessibilityLabel(description)
    }

    private static func image(for state: AggregateState, strings: Strings) -> (NSImage, String) {
        let (badge, description): (NSColor?, String) = switch state {
        case .idle: (nil, strings.iconStopped)
        case .connected: (.systemGreen, strings.iconConnected)
        case .connecting: (.systemOrange, strings.iconConnecting)
        case .failed: (.systemRed, strings.iconFailed)
        }
        let symbol = NSImage(systemSymbolName: "arrow.left.arrow.right.circle", accessibilityDescription: description)!
            .withSymbolConfiguration(.init(pointSize: 15, weight: .regular))!
        guard let badge else {
            symbol.isTemplate = true
            return (symbol, description)
        }

        let size = NSSize(width: symbol.size.width + 2, height: symbol.size.height + 1)
        // Drawn on demand, so the glyph follows the menu bar's current text color.
        let image = NSImage(size: size, flipped: false) { rect in
            let glyph = NSRect(origin: NSPoint(x: 0, y: 1), size: symbol.size)
            symbol.draw(in: glyph)
            NSColor.labelColor.set()
            glyph.fill(using: .sourceAtop)

            let diameter = (rect.height * 0.42).rounded()
            let dot = NSRect(x: rect.maxX - diameter, y: rect.minY, width: diameter, height: diameter)
            // Erasing takes the fill's alpha, so it must be opaque to clear the glyph fully around the badge.
            NSColor.black.set()
            NSGraphicsContext.current?.compositingOperation = .destinationOut
            NSBezierPath(ovalIn: dot.insetBy(dx: -1.5, dy: -1.5)).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            badge.set()
            NSBezierPath(ovalIn: dot).fill()
            return true
        }
        image.isTemplate = false
        return (image, description)
    }
}
