import NetworkMonitorCore
import SwiftUI

enum GraphType: String {
    case down
    case up
}

enum SystemGraphType: String {
    case cpu
    case gpu
    case memory
}

@MainActor
class AppState: ObservableObject {
    @Published var graphType: GraphType = .down
    @Published var systemGraphType: SystemGraphType = .cpu
    @Published var settingsTab: SettingsTab = .general
    @Published var historySeconds = 120
}
