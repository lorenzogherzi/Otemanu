import Foundation

@MainActor
final class OtemanuSettings: ObservableObject {
    static let shared = OtemanuSettings()

    private enum Key {
        static let openIslandWhenExecutionStarts = "otemanu.openIslandWhenExecutionStarts"
        static let automaticallyHideMonitor = "otemanu.automaticallyHideMonitor"
        static let automaticHideDelay = "otemanu.automaticHideDelay"
    }

    @Published var openIslandWhenExecutionStarts: Bool {
        didSet {
            UserDefaults.standard.set(
                openIslandWhenExecutionStarts,
                forKey: Key.openIslandWhenExecutionStarts
            )
        }
    }

    @Published var automaticallyHideMonitor: Bool {
        didSet {
            UserDefaults.standard.set(automaticallyHideMonitor, forKey: Key.automaticallyHideMonitor)
        }
    }

    @Published var automaticHideDelay: Double {
        didSet {
            UserDefaults.standard.set(automaticHideDelay, forKey: Key.automaticHideDelay)
        }
    }

    private init() {
        openIslandWhenExecutionStarts =
            UserDefaults.standard.object(forKey: Key.openIslandWhenExecutionStarts) as? Bool
            ?? true
        automaticallyHideMonitor = UserDefaults.standard.bool(forKey: Key.automaticallyHideMonitor)

        let storedDelay = UserDefaults.standard.double(forKey: Key.automaticHideDelay)
        automaticHideDelay = storedDelay > 0 ? storedDelay : 2
    }
}
