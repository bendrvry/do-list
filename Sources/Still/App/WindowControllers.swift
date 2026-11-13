import AppKit
import SwiftUI

/// The compact task window: a real NSWindow with an integrated, transparent title bar
/// and system traffic lights. Size and position are remembered via frame autosave.
@MainActor
final class MainWindowController: NSWindowController, NSWindowDelegate {
    private let sharedUndoManager: UndoManager
    private static let autosaveName = "StillMainWindow"
    var onBecomeKey: ((NSWindow) -> Void)?

    init(rootView: some View, undoManager: UndoManager) {
        self.sharedUndoManager = undoManager
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = AppInfo.name
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 300, height: 240)
        window.backgroundColor = NSColor.still.background
        window.collectionBehavior = [.fullScreenNone]
        window.tabbingMode = .disallowed
        window.setAccessibilityLabel("\(AppInfo.name) tasks")

        let hosting = NSHostingView(rootView: rootView)
        // The window, not SwiftUI content, decides the window size.
        hosting.sizingOptions = []
        window.contentView = hosting

        super.init(window: window)
        window.delegate = self
        if !window.setFrameUsingName(Self.autosaveName) {
            window.center()
        }
        window.setFrameAutosaveName(Self.autosaveName)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? { sharedUndoManager }

    func windowDidBecomeKey(_ notification: Notification) {
        guard let window else { return }
        onBecomeKey?(window)
    }
}

/// History and Settings windows.
@MainActor
final class AuxiliaryWindowController: NSWindowController, NSWindowDelegate {
    private let sharedUndoManager: UndoManager?

    init(
        title: String,
        rootView: some View,
        size: NSSize,
        resizable: Bool,
        integratedTitleBar: Bool,
        autosaveName: String?,
        undoManager: UndoManager? = nil
    ) {
        self.sharedUndoManager = undoManager
        var style: NSWindow.StyleMask = [.titled, .closable]
        if resizable { style.formUnion([.resizable, .miniaturizable]) }
        if integratedTitleBar { style.insert(.fullSizeContentView) }

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: style,
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.collectionBehavior = [.fullScreenNone]
        if integratedTitleBar {
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.backgroundColor = NSColor.still.background
        }

        if resizable {
            let hosting = NSHostingView(rootView: rootView)
            hosting.sizingOptions = []
            window.contentView = hosting
            window.minSize = NSSize(width: 320, height: 300)
        } else {
            // Fixed windows (Settings) size themselves to their content.
            let controller = NSHostingController(rootView: rootView)
            controller.sizingOptions = [.preferredContentSize]
            window.contentViewController = controller
        }

        super.init(window: window)
        window.delegate = self
        if let autosaveName {
            if !window.setFrameUsingName(autosaveName) { window.center() }
            window.setFrameAutosaveName(autosaveName)
        } else {
            window.center()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? { sharedUndoManager }

    func present() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}
