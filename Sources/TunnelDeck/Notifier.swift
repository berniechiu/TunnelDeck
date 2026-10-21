import Foundation
import TunnelCore
import UserNotifications

@MainActor
final class Notifier {
    // UNUserNotificationCenter aborts outside an app bundle, e.g. under `swift run`.
    private var center: UNUserNotificationCenter? {
        Bundle.main.bundleIdentifier == nil ? nil : .current()
    }

    func requestAuthorization() {
        center?.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func post(tunnel: Tunnel, failure: TunnelFailure) {
        let content = UNMutableNotificationContent()
        content.title = tunnel.name
        content.body = failure.message
        center?.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}
