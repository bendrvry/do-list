import AppKit

/// The menu bar icon. Click for the task dropdown; right-click (or Control-click)
/// for the options menu.
@MainActor
final class StatusItemController: NSObject {
    var onClick: ((NSStatusBarButton) -> Void)?

    private let item: NSStatusItem
    private let menu: NSMenu

    init(menu: NSMenu) {
        self.menu = menu
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        if let button = item.button {
            button.image = Self.icon(filled: false)
            button.target = self
            button.action = #selector(clicked(_:))
            button.sendAction(on: [.leftMouseDown, .rightMouseDown])
            button.setAccessibilityLabel(AppInfo.name)
            button.setAccessibilityHelp("Shows your list. Right-click for options.")
        }
    }

    var button: NSStatusBarButton? { item.button }

    /// Shows the filled icon while the dropdown is open. (A status item's pressed
    /// highlight only appears for real menus, so this is the visible "open" state.)
    func setHighlighted(_ highlighted: Bool) {
        item.button?.image = Self.icon(filled: highlighted)
    }

    func showMenu() {
        // Attaching the menu only for this click keeps left-click free for the dropdown
        // while giving the menu the system's native placement and highlight.
        item.menu = menu
        item.button?.performClick(nil)
        item.menu = nil
    }

    func remove() {
        NSStatusBar.system.removeStatusItem(item)
    }

    private static func icon(filled: Bool) -> NSImage? {
        let name = filled ? "checkmark.circle.fill" : "checkmark.circle"
        let image = NSImage(systemSymbolName: name, accessibilityDescription: AppInfo.name)
        image?.isTemplate = true
        return image
    }

    @objc private func clicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseDown || event?.modifierFlags.contains(.control) == true {
            showMenu()
        } else {
            onClick?(sender)
        }
    }
}
