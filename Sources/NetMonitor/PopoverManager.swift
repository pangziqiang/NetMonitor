import AppKit
import Combine

@MainActor
class PopoverManager: ObservableObject {
    static let shared = PopoverManager()

    private init() {}

    private var moveObserver: NSObjectProtocol?

    weak var panel: NSPanel? {
        didSet {
            if let oldObserver = moveObserver {
                NotificationCenter.default.removeObserver(oldObserver)
                moveObserver = nil
            }
            guard let panel else { return }
            moveObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didMoveNotification,
                object: panel,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.hasMoved = true
                }
            }
        }
    }

    @Published var isPinned = false {
        didSet {
            guard let panel else { return }
            panel.level = isPinned ? .floating : .popUpMenu
            panel.collectionBehavior = isPinned
                ? [.moveToActiveSpace]
                : [.transient, .ignoresCycle, .moveToActiveSpace]
        }
    }

    @Published var hasMoved = false

    @Published var contentSize: CGSize = .zero

    func togglePin() {
        isPinned.toggle()
    }
}
