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
    @Published var historySeconds = 120 {
        didSet {
            // Clamp to valid range
            historySeconds = max(30, min(600, historySeconds))
        }
    }
}
