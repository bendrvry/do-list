import AppKit

enum AppInfo {
    /// Display name. Change here (and in scripts/build-app.sh) to rename the app.
    static let name = "Do List"
    static var bundleIdentifier: String { Bundle.main.bundleIdentifier ?? "app.dolist.mac" }
}

/// Menu actions implemented by the app delegate.
@MainActor
@objc protocol StillActions {
    func showAbout(_ sender: Any?)
    func showSettings(_ sender: Any?)
    func newTask(_ sender: Any?)
    func showTasks(_ sender: Any?)
    func showHistory(_ sender: Any?)
    func toggleKeepOnTop(_ sender: Any?)
    func quit(_ sender: Any?)
}

@MainActor
enum MenuBuilder {
    static func mainMenu(target: StillActions) -> NSMenu {
        let main = NSMenu()
        let name = AppInfo.name

        // App menu
        let app = submenu(in: main, title: name)
        app.addItem(item("About \(name)", #selector(StillActions.showAbout), target: target))
        app.addItem(.separator())
        app.addItem(item("Settings…", #selector(StillActions.showSettings), ",", target: target))
        app.addItem(.separator())
        let services = NSMenu(title: "Services")
        let servicesItem = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        servicesItem.submenu = services
        app.addItem(servicesItem)
        NSApp.servicesMenu = services
        app.addItem(.separator())
        app.addItem(item("Hide \(name)", #selector(NSApplication.hide(_:)), "h"))
        app.addItem(item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]))
        app.addItem(item("Show All", #selector(NSApplication.unhideAllApplications(_:))))
        app.addItem(.separator())
        app.addItem(item("Quit \(name)", #selector(StillActions.quit), "q", target: target))

        // File
        let file = submenu(in: main, title: "File")
        file.addItem(item("New Task", #selector(StillActions.newTask), "n", target: target))
        file.addItem(.separator())
        file.addItem(item("Close Window", #selector(NSWindow.performClose(_:)), "w"))

        // Edit
        let edit = submenu(in: main, title: "Edit")
        edit.addItem(item("Undo", Selector(("undo:")), "z"))
        edit.addItem(item("Redo", Selector(("redo:")), "z", [.command, .shift]))
        edit.addItem(.separator())
        edit.addItem(item("Cut", #selector(NSText.cut(_:)), "x"))
        edit.addItem(item("Copy", #selector(NSText.copy(_:)), "c"))
        edit.addItem(item("Paste", #selector(NSText.paste(_:)), "v"))
        edit.addItem(item("Paste and Match Style", #selector(NSTextView.pasteAsPlainText(_:)), "v", [.command, .option, .shift]))
        edit.addItem(item("Delete", #selector(NSText.delete(_:))))
        edit.addItem(item("Select All", #selector(NSText.selectAll(_:)), "a"))

        // View
        let view = submenu(in: main, title: "View")
        view.addItem(item("Show Tasks", #selector(StillActions.showTasks), "0", target: target))
        view.addItem(item("History", #selector(StillActions.showHistory), "h", [.command, .shift], target: target))
        view.addItem(.separator())
        view.addItem(item("Keep Window on Top", #selector(StillActions.toggleKeepOnTop), "t", [.command, .option], target: target))

        // Window
        let window = submenu(in: main, title: "Window")
        window.addItem(item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"))
        window.addItem(item("Zoom", #selector(NSWindow.performZoom(_:))))
        window.addItem(.separator())
        window.addItem(item("Bring All to Front", #selector(NSApplication.arrangeInFront(_:))))
        NSApp.windowsMenu = window

        return main
    }

    static func statusMenu(target: StillActions) -> NSMenu {
        let menu = NSMenu()
        menu.addItem(item("Open Window", #selector(StillActions.showTasks), target: target))
        menu.addItem(item("History", #selector(StillActions.showHistory), target: target))
        menu.addItem(.separator())
        menu.addItem(item("Keep Window on Top", #selector(StillActions.toggleKeepOnTop), target: target))
        menu.addItem(.separator())
        menu.addItem(item("Settings…", #selector(StillActions.showSettings), target: target))
        menu.addItem(item("Quit \(AppInfo.name)", #selector(StillActions.quit), target: target))
        return menu
    }

    private static func submenu(in menu: NSMenu, title: String) -> NSMenu {
        let submenu = NSMenu(title: title)
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        menu.addItem(item)
        return submenu
    }

    private static func item(
        _ title: String,
        _ action: Selector,
        _ key: String = "",
        _ modifiers: NSEvent.ModifierFlags = .command,
        target: AnyObject? = nil
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = key.isEmpty ? [] : modifiers
        item.target = target
        return item
    }
}
