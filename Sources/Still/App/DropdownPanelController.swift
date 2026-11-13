import AppKit
import SwiftUI

/// The task list dropped down from the menu bar icon: a borderless panel that looks
/// like the main window, positioned under the status item.
///
/// It's a non-activating panel (like Spotlight): it takes keyboard input without
/// making the app active, so the app you were using stays in front underneath and
/// simply gets focus back when the dropdown closes. It closes when the icon is clicked
/// again, on Escape, when anything outside it is clicked, or when you switch apps.
@MainActor
final class DropdownPanelController: NSObject, NSWindowDelegate {
    static let size = NSSize(width: 360, height: 480)
    static let cornerRadius: CGFloat = 12

    var onBecomeKey: ((NSWindow) -> Void)?
    var onVisibilityChange: ((Bool) -> Void)?

    private let panel: DropdownPanel
    private let sharedUndoManager: UndoManager
    private var outsideClickMonitor: Any?
    private var appSwitchObserver: NSObjectProtocol?

    init(rootView: some View, undoManager: UndoManager) {
        sharedUndoManager = undoManager
        panel = DropdownPanel(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.title = AppInfo.name
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        // Above normal windows, below menus (so context menus appear over it).
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none

        let hosting = NSHostingView(rootView: DropdownChrome(content: rootView))
        hosting.sizingOptions = []
        panel.contentView = hosting

        super.init()
        panel.delegate = self
    }

    var window: NSWindow { panel }
    var isShown: Bool { panel.isVisible }

    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    func show(below button: NSStatusBarButton) {
        guard !panel.isVisible else { return }
        position(below: button)

        panel.alphaValue = reduceMotion ? 1 : 0
        panel.makeKeyAndOrderFront(nil)
        if !reduceMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                panel.animator().alphaValue = 1
            }
        }
        // The shadow of a transparent window follows its drawn content.
        DispatchQueue.main.async { [panel] in panel.invalidateShadow() }

        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
        // Switching apps (⌘Tab, Dock) dismisses it too.
        appSwitchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard app?.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
            MainActor.assumeIsolated { self?.close() }
        }
        onVisibilityChange?(true)
    }

    func close() {
        guard panel.isVisible else { return }
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        outsideClickMonitor = nil
        if let appSwitchObserver { NSWorkspace.shared.notificationCenter.removeObserver(appSwitchObserver) }
        appSwitchObserver = nil

        let panel = panel
        if reduceMotion {
            panel.orderOut(nil)
        } else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.1
                panel.animator().alphaValue = 0
            } completionHandler: {
                MainActor.assumeIsolated {
                    panel.orderOut(nil)
                    panel.alphaValue = 1
                }
            }
        }
        onVisibilityChange?(false)
    }

    private func position(below button: NSStatusBarButton) {
        let size = Self.size
        guard let buttonWindow = button.window, let screen = buttonWindow.screen ?? NSScreen.main else {
            panel.setContentSize(size)
            panel.center()
            return
        }
        let buttonRect = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let visible = screen.visibleFrame
        let inset: CGFloat = 8
        let height = min(size.height, visible.height - inset * 2)
        var x = buttonRect.midX - size.width / 2
        x = min(max(x, visible.minX + inset), visible.maxX - size.width - inset)
        let top = min(buttonRect.minY, visible.maxY) - 5
        panel.setFrame(NSRect(x: x, y: top - height, width: size.width, height: height), display: true)
    }

    // MARK: NSWindowDelegate

    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? { sharedUndoManager }

    func windowDidBecomeKey(_ notification: Notification) {
        onBecomeKey?(panel)
    }

    func windowDidResignKey(_ notification: Notification) {
        // Another of our windows (main window, Settings, History) took focus.
        DispatchQueue.main.async { [weak self] in
            guard let self, panel.isVisible, !panel.isKeyWindow, NSApp.keyWindow != nil else { return }
            close()
        }
    }
}

private final class DropdownPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Rounded corners and a hairline edge, like a menu, around the task view.
private struct DropdownChrome<Content: View>: View {
    let content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DropdownPanelController.cornerRadius, style: .continuous)
        content
            .clipShape(shape)
            .overlay(shape.strokeBorder(Theme.panelEdge, lineWidth: 0.5))
    }
}
