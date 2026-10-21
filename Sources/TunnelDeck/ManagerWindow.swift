import SwiftUI
import TunnelCore

struct ManagerWindow: View {
    static let id = "manager"
    let model: AppModel

    var body: some View {
        Text("管理視窗")
            .frame(minWidth: 760, minHeight: 480)
    }
}
