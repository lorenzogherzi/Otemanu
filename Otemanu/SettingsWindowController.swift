import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()

    private var hasPositionedWindow = false

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)
        configure(window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configure(_ window: NSWindow) {
        window.title = "Otemanu Settings"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.toolbar = nil
        window.tabbingMode = .disallowed
        window.isMovableByWindowBackground = true

        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true

        window.level = .normal
        window.minSize = NSSize(width: 720, height: 500)
        window.collectionBehavior = [.managed, .participatesInCycle]
        window.animationBehavior = .documentWindow
        window.hidesOnDeactivate = false
        window.isExcludedFromWindowsMenu = false
        window.isRestorable = false
        window.isReleasedWhenClosed = false
        window.identifier = NSUserInterfaceItemIdentifier("OtemanuSettingsWindow")
        window.contentView = NSHostingView(rootView: SettingsView())
        window.delegate = self
    }

    func showWindow() {
        guard let window else { return }

        if !hasPositionedWindow {
            window.center()
            hasPositionedWindow = true
        }

        window.level = .normal
        window.collectionBehavior = [.managed, .participatesInCycle]
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func relinquishFocus() {
        window?.orderOut(nil)
        NSApplication.shared.setActivationPolicy(.accessory)
    }
}

extension SettingsWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        relinquishFocus()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
    }
}
