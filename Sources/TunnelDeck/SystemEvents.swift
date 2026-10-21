import AppKit
import Network

/// Reports network recovery and wake from sleep, so tunnels waiting to reconnect retry right away.
@MainActor
final class SystemEvents {
    private let monitor = NWPathMonitor()
    private var wakeObserver: NSObjectProtocol?

    init(onChange: @escaping @MainActor () -> Void) {
        monitor.pathUpdateHandler = { path in
            guard path.status == .satisfied else { return }
            Task { @MainActor in onChange() }
        }
        monitor.start(queue: .global(qos: .utility))
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in onChange() }
        }
    }
}
