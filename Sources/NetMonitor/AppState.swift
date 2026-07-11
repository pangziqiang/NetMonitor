import NetMonitorCore
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
    private let defaults = UserDefaults.standard

    @Published var graphType: GraphType = .down
    @Published var systemGraphType: SystemGraphType = .cpu
    @Published var settingsTab: SettingsTab = .general

    @Published var historySeconds: Int = 120 {
        didSet { defaults.set(historySeconds, forKey: "historySeconds") }
    }

    init() {
        let saved = defaults.integer(forKey: "historySeconds")
        historySeconds = saved > 0 ? saved : 120
    }
}
