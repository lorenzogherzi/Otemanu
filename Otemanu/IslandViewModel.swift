import AppKit
import SwiftUI

@MainActor
final class IslandViewModel: ObservableObject {
    @Published private(set) var state: IslandState = .closed
    @Published private(set) var screen: NSScreen
    @Published private(set) var isExecutionPinned = false
    @Published private(set) var showsCompletionNotice = false
    var onCompletionNoticeDismissed: (() -> Void)?
    private var requiresClickToClose = false
    private var automaticCloseTask: Task<Void, Never>?

    init(screen: NSScreen) {
        self.screen = screen
    }

    func setScreen(_ screen: NSScreen) {
        self.screen = screen
    }

    func open() {
        automaticCloseTask?.cancel()
        requiresClickToClose = false
        state = .open
    }

    func close() {
        guard !isExecutionPinned, !requiresClickToClose else { return }
        automaticCloseTask?.cancel()
        dismissCompletionNotice()
        state = .closed
    }

    func toggle() {
        switch state {
        case .closed:
            open()
        case .minimizedBusy:
            open()
        case .open where isExecutionPinned:
            automaticCloseTask?.cancel()
            state = .minimizedBusy
        case .open:
            closeFromClick()
        }
    }

    func executionDidStart(openAutomatically: Bool = true) {
        automaticCloseTask?.cancel()
        dismissCompletionNotice()
        requiresClickToClose = false
        let wasAlreadyExecuting = isExecutionPinned
        isExecutionPinned = true
        if !wasAlreadyExecuting {
            state = openAutomatically ? .open : .minimizedBusy
        }
    }

    func executionDidFinish(
        showCompletionNotice: Bool,
        automaticallyHide: Bool,
        delay: TimeInterval
    ) {
        isExecutionPinned = false
        state = .open
        automaticCloseTask?.cancel()
        requiresClickToClose = !automaticallyHide
        showsCompletionNotice = showCompletionNotice

        guard automaticallyHide else { return }
        automaticCloseTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(delay, 0.5)))
            guard !Task.isCancelled else { return }
            self?.dismissCompletionNotice()
            self?.state = .closed
        }
    }

    private func closeFromClick() {
        guard !isExecutionPinned else { return }
        automaticCloseTask?.cancel()
        dismissCompletionNotice()
        requiresClickToClose = false
        state = .closed
    }

    private func dismissCompletionNotice() {
        guard showsCompletionNotice else { return }
        showsCompletionNotice = false
        onCompletionNoticeDismissed?()
    }
}
