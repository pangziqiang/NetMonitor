import SwiftUI

/// App-level router for opening SwiftUI `Window` scenes from non-View code
/// (e.g. the floating window's double-click handler in `AppDelegate`).
///
/// The `OpenWindowAction` is only available inside SwiftUI views, so every
/// window scene registers it here on first appearance. The stored action stays
/// valid for the app's lifetime, independent of whether the registering window
/// is open or closed.
@MainActor
final class WindowRouter {
    static let shared = WindowRouter()

    private var openWindow: OpenWindowAction?

    private init() {}

    func register(_ action: OpenWindowAction) {
        openWindow = action
    }

    func open(id: String) {
        openWindow?.callAsFunction(id: id)
    }
}
