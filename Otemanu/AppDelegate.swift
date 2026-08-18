import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: IslandWindow?
    private var viewModel: IslandViewModel?
    private var monitorCancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        createIslandWindow()
        _ = JupyterMonitor.shared

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenConfigurationDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        NotificationCenter.default.publisher(for: .jupyterExecutionDidStart)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.viewModel?.executionDidStart(
                    openAutomatically: OtemanuSettings.shared.openIslandWhenExecutionStarts
                )
            }
            .store(in: &monitorCancellables)

        NotificationCenter.default.publisher(for: .jupyterExecutionDidFinish)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                guard JupyterMonitor.shared.busyKernelCount == 0 else { return }
                let settings = OtemanuSettings.shared
                self?.viewModel?.executionDidFinish(
                    showCompletionNotice: notification.userInfo?["showCompletion"] as? Bool
                        ?? true,
                    automaticallyHide: settings.automaticallyHideMonitor,
                    delay: settings.automaticHideDelay
                )
            }
            .store(in: &monitorCancellables)
    }

    func applicationWillTerminate(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func screenConfigurationDidChange() {
        refreshWindowGeometry()
    }

    private func createIslandWindow() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }

        let viewModel = IslandViewModel(screen: screen)
        viewModel.onCompletionNoticeDismissed = {
            JupyterMonitor.shared.discardCompletedExecution()
        }
        self.viewModel = viewModel

        let size = windowSize(for: screen)
        let window = IslandWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.animationBehavior = .none
        window.contentView = FirstMouseHostingView(rootView: IslandView(viewModel: viewModel))
        self.window = window

        positionWindow(window, on: screen)
        window.orderFrontRegardless()
    }

    private func refreshWindowGeometry() {
        guard let window else { return }
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }

        viewModel?.setScreen(screen)
        let size = windowSize(for: screen)
        window.setContentSize(size)
        positionWindow(window, on: screen)
    }

    private func windowSize(for screen: NSScreen) -> CGSize {
        let maximum = openIslandSize(screen: screen)

        let pillInsets = usesPillLayout(on: screen) ? pillShadowInset * 2 : 0
        let verticalInset =
            usesPillLayout(on: screen)
            ? pillTopOffset + pillShadowInset
            : topScreenBleed

        return CGSize(
            width: maximum.width + pillInsets + 24,
            height: maximum.height + verticalInset + islandShadowPadding + 12
        )
    }

    private func positionWindow(_ window: NSWindow, on screen: NSScreen) {
        let screenFrame = screen.frame
        let centerX = screenFrame.origin.x + screenFrame.width / 2
        let width = window.frame.width.rounded()
        let height = window.frame.height.rounded()
        let x = (centerX - width / 2).rounded()
        let topBleed = usesPillLayout(on: screen) ? 0 : topScreenBleed
        let y = (screenFrame.maxY + topBleed - height).rounded()

        window.setFrame(
            NSRect(x: x, y: y, width: width, height: height),
            display: false
        )
    }
}

final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
