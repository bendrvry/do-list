import AppKit
import Carbon.HIToolbox
import StillCore
import SwiftUI

/// Owns the app's long-lived objects and wires AppKit (windows, menus, global
/// shortcut, menu bar item) to the task store and preferences.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation, StillActions {
    private var preferences: Preferences!
    private var store: TaskStore!
    private var listModel: MainListModel!
    private var mainWindow: MainWindowController!
    private var historyWindow: AuxiliaryWindowController?
    private var settingsWindow: AuxiliaryWindowController?
    private var statusItem: StatusItemController?
    private var keyMonitor: Any?

    /// The menu bar dropdown has its own UI state (selection, editing) over the same
    /// shared task store, so it always matches the main window.
    private var dropdownModel: MainListModel!
    private var dropdown: DropdownPanelController!

    private let clock = DayClock()
    private let hotkeys = HotkeyService()
    private let loginItems = LoginItemService()
    private let inputFocus = InputFocus()
    private let dropdownInputFocus = InputFocus()

    // MARK: Launch

    func applicationDidFinishLaunching(_ notification: Notification) {
        let (dataDirectory, defaults) = Self.storageLocations()
        preferences = Preferences(defaults: defaults)
        NSApp.mainMenu = MenuBuilder.mainMenu(target: self)

        do {
            let repository = try TaskRepository.openDefault(directory: dataDirectory)
            store = try TaskStore(repository: repository, options: preferences.displayOptions)
        } catch {
            presentDatabaseFailure(error, directory: dataDirectory)
            return
        }
        store.onError = { ErrorPresenter.present($0) }
        clock.nextBoundary = { [unowned self] now in store.nextVisibilityChange(after: now) }

        listModel = MainListModel(store: store, clock: clock, inputFocus: inputFocus)
        mainWindow = MainWindowController(
            rootView: withEnvironment(MainTaskView(model: listModel)),
            undoManager: store.undoManager
        )

        hotkeys.onPress = { [weak self] in self?.toggleMainWindow() }
        GlobalShortcutPause.onChange = { [weak self] paused in
            guard let self else { return }
            paused ? hotkeys.unregister() : registerHotkey()
        }

        dropdownModel = MainListModel(store: store, clock: clock, inputFocus: dropdownInputFocus)
        let commands = DropdownCommands(
            openWindow: { [weak self] in self?.showTasks(nil) },
            showHistory: { [weak self] in self?.showHistory(nil) },
            showSettings: { [weak self] in self?.showSettings(nil) },
            quit: { [weak self] in self?.quit(nil) }
        )
        dropdown = DropdownPanelController(
            rootView: withEnvironment(MainTaskView(model: dropdownModel, presentation: .dropdown(commands))),
            undoManager: store.undoManager
        )
        dropdown.onVisibilityChange = { [weak self] visible in
            self?.statusItem?.setHighlighted(visible)
            if !visible { self?.dropdownModel.clearSelection() }
        }

        // Whenever the window or dropdown comes forward, it's ready for typing — unless
        // a task is being edited there.
        mainWindow.onBecomeKey = { [weak self] window in self?.focusInputIfIdle(in: window) }
        dropdown.onBecomeKey = { [weak self] window in self?.focusInputIfIdle(in: window) }

        bindPreferences()
        installKeyboardNavigation()
        clock.tick()
        showMainWindow(focusInput: true)
    }

    private func bindPreferences() {
        trackChanges { [unowned self] in
            let options = preferences.displayOptions
            if store.options != options { store.options = options }
        }
        trackChanges { [unowned self] in
            NSApp.appearance = switch preferences.appearance {
            case .system: nil
            case .light: NSAppearance(named: .aqua)
            case .dark: NSAppearance(named: .darkAqua)
            }
        }
        trackChanges { [unowned self] in
            mainWindow.window?.level = preferences.keepWindowOnTop ? .floating : .normal
        }
        trackChanges { [unowned self] in
            setStatusItemVisible(preferences.showMenuBarIcon)
        }
        trackChanges { [unowned self] in
            _ = preferences.hotKey
            _ = preferences.hotKeyEnabled
            registerHotkey()
        }
        trackChanges { [unowned self] in
            // Tasks or retention changed: the next visibility boundary may have moved.
            _ = store.revision
            clock.reschedule()
        }
    }

    private func focusInputIfIdle(in window: NSWindow) {
        guard let model = model(for: window), !(window.firstResponder is NSText), model.editingID == nil else { return }
        model.inputFocus.focus()
    }

    /// The list model behind a task surface (main window or dropdown).
    private func model(for window: NSWindow?) -> MainListModel? {
        guard let window else { return nil }
        if window === mainWindow?.window { return listModel }
        if window === dropdown?.window { return dropdownModel }
        return nil
    }

    private func withEnvironment(_ view: some View) -> some View {
        view
            .environment(store)
            .environment(preferences)
            .environment(clock)
            .environment(loginItems)
            .environment(hotkeys)
    }

    /// Standard Application Support location. `STILL_DATA_DIR` points development
    /// builds at a separate database and preferences domain.
    private static func storageLocations() -> (URL, UserDefaults) {
        if let override = ProcessInfo.processInfo.environment["STILL_DATA_DIR"], !override.isEmpty {
            let defaults = UserDefaults(suiteName: "\(AppInfo.bundleIdentifier).development") ?? .standard
            return (URL(fileURLWithPath: override, isDirectory: true), defaults)
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return (support.appendingPathComponent(AppInfo.bundleIdentifier, isDirectory: true), .standard)
    }

    private func presentDatabaseFailure(_ error: Error, directory: URL) {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "\(AppInfo.name) couldn’t open your tasks."
        alert.informativeText = """
            \(error.localizedDescription)

            Nothing has been changed or deleted. Your task database is in:
            \(directory.path)
            """
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Show in Finder")
        if alert.runModal() == .alertSecondButtonReturn {
            NSWorkspace.shared.activateFileViewerSelecting([directory])
        }
        NSApp.terminate(nil)
    }

    // MARK: App lifecycle

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !(mainWindow?.window?.isVisible ?? true) { showMainWindow(focusInput: true) }
        return true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        loginItems.refresh()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    // MARK: Window management

    /// Global shortcut: bring the task window forward with the input focused, or hide
    /// the app if the window is already frontmost.
    func toggleMainWindow() {
        guard let window = mainWindow?.window else { return }
        if NSApp.isActive && window.isVisible && window.isKeyWindow {
            NSApp.hide(nil)
        } else {
            showMainWindow(focusInput: true)
        }
    }

    func showMainWindow(focusInput: Bool) {
        guard let window = mainWindow?.window else { return }
        if window.isMiniaturized { window.deminiaturize(nil) }
        mainWindow.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        if focusInput { inputFocus.focus() }
    }

    private func registerHotkey() {
        hotkeys.register(preferences.hotKeyEnabled ? preferences.hotKey : nil)
    }

    private func setStatusItemVisible(_ visible: Bool) {
        if visible, statusItem == nil {
            let item = StatusItemController(menu: MenuBuilder.statusMenu(target: self))
            item.onClick = { [weak self] button in self?.toggleDropdown(from: button) }
            statusItem = item
        } else if !visible, let item = statusItem {
            dropdown?.close()
            item.remove()
            statusItem = nil
        }
    }

    /// Clicking the menu bar icon drops the list down (or closes it again).
    private func toggleDropdown(from button: NSStatusBarButton) {
        if dropdown.isShown {
            dropdown.close()
        } else {
            dropdownModel.clearSelection()
            dropdown.show(below: button)
            focusInputIfIdle(in: dropdown.window)
        }
    }

    /// Closes the dropdown before another window takes over.
    private func dismissDropdown() {
        dropdown?.close()
    }

    /// Arrow keys, Space, Return and Delete act on tasks when no text field is
    /// being edited.
    private func installKeyboardNavigation() {
        // Local monitors are called on the main thread.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, let window = event.window, let model = self.model(for: window) else { return event }
            let isDropdown = window === self.dropdown.window
            let isSecondaryClick = event.type == .rightMouseDown
                || (event.type == .leftMouseDown && event.modifierFlags.contains(.control))
            if isSecondaryClick {
                // Right-click on a checkbox marks the task in progress instead of
                // opening the row's context menu.
                guard let task = self.checkboxTask(at: event, in: window, model: model) else { return event }
                model.toggleInProgress(task)
                return nil
            }
            if event.type == .leftMouseDown {
                if model.selectedID != nil { model.clearSelection() }
                return self.detectClickToEdit(event, in: window, model: model) ? nil : event
            }
            let flags = event.modifierFlags.intersection([.command, .option, .control])

            // Escape closes the dropdown when there's nothing else for it to cancel.
            if isDropdown, Int(event.keyCode) == kVK_Escape, flags.isEmpty,
               model.editingID == nil, model.selectedID == nil,
               !(window.firstResponder is NSText) || (model.inputFocus.isFocused && model.inputFocus.isEmpty) {
                self.dropdown.close()
                return nil
            }

            if window.firstResponder is NSText { return event }
            let isArrow = [kVK_UpArrow, kVK_DownArrow].contains(Int(event.keyCode))
            if flags.isEmpty || (flags == .command && isArrow), model.handleKey(event) {
                return nil
            }
            // Type to add: ordinary typing anywhere in the window goes to the input.
            if !flags.contains(.command), !flags.contains(.control), Self.producesText(event) {
                model.clearSelection()
                model.inputFocus.focus()
                if let editor = window.firstResponder as? NSTextView {
                    editor.keyDown(with: event)
                    return nil
                }
            }
            return event
        }
    }

    /// Whether a key event types visible text (letters, digits, punctuation, space),
    /// as opposed to arrows, function keys, Return, Tab, Escape or Delete.
    private static func producesText(_ event: NSEvent) -> Bool {
        guard let characters = event.characters, !characters.isEmpty else { return false }
        return characters.unicodeScalars.allSatisfy { scalar in
            !CharacterSet.controlCharacters.contains(scalar)
                && !(0xF700...0xF8FF).contains(scalar.value) // AppKit function-key range
        }
    }

    /// The task whose checkbox is under the pointer, if any.
    private func checkboxTask(at event: NSEvent, in window: NSWindow, model: MainListModel) -> TaskItem? {
        guard let content = window.contentView else { return nil }
        let point = event.locationInWindow
        let checkboxColumn = (Theme.margin - 4)...(Theme.margin + Theme.checkboxSize + 4)
        guard checkboxColumn.contains(point.x) else { return nil }
        var view = content.hitTest(point)
        while let current = view, !(current is NSTableView) { view = current.superview }
        guard let table = view as? NSTableView else { return nil }
        return model.task(atRow: table.row(at: table.convert(point, from: nil)))
    }

    /// A plain click on a task's text starts inline editing.
    ///
    /// SwiftUI tap gestures (or any view that accepts the mouse) inside a `List` row
    /// stop the list's native drag-to-reorder from starting, so the click is detected
    /// here instead: the list handles the mouse-down as normal, and afterwards a press
    /// that didn't move the pointer counts as a click on that row's text.
    ///
    /// A double-click on the text starts editing straight away and is consumed, so
    /// the list's own double-click handling can't pull focus back out of the editor.
    /// Returns whether the event was consumed.
    private func detectClickToEdit(_ event: NSEvent, in window: NSWindow, model: MainListModel) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .shift, .control, .option])
        guard event.clickCount <= 2, modifiers.isEmpty, let content = window.contentView else { return false }
        let start = event.locationInWindow
        // Only the text column (right of the checkbox) edits.
        let textColumn = Theme.margin + Theme.checkboxSize + Theme.checkboxGap - 2
        guard start.x >= textColumn, start.x <= content.bounds.width - Theme.margin + Theme.rowBleed else { return false }

        // hitTest takes a point in the superview's (window) coordinates.
        let hit = content.hitTest(start)
        // Clicks inside an open editor belong to it (a double-click there selects a word).
        if hit is NSText { return false }
        var view = hit
        while let current = view, !(current is NSTableView) { view = current.superview }
        guard let table = view as? NSTableView else { return false }
        let row = table.row(at: table.convert(start, from: nil))
        guard let task = model.task(atRow: row) else { return false }

        if event.clickCount == 2 {
            if model.editingID != task.id { model.beginEditing(task) }
            return true
        }
        guard model.editingID != task.id else { return false }

        // Runs once the list has finished with the mouse-down (and any drag).
        DispatchQueue.main.async {
            guard NSEvent.pressedMouseButtons & 1 == 0 else { return }
            let end = window.mouseLocationOutsideOfEventStream
            if hypot(end.x - start.x, end.y - start.y) < 4 {
                model.beginEditing(task)
            }
        }
        return false
    }

    // MARK: Actions

    @objc func showAbout(_ sender: Any?) {
        dismissDropdown()
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: NSAttributedString(
                string: "A quiet place for the things you need to do.",
                attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]
            ),
        ])
    }

    @objc func showSettings(_ sender: Any?) {
        dismissDropdown()
        if settingsWindow == nil {
            settingsWindow = AuxiliaryWindowController(
                title: "Settings",
                rootView: withEnvironment(SettingsView()),
                size: NSSize(width: 470, height: 560),
                resizable: false,
                integratedTitleBar: false,
                autosaveName: nil
            )
        }
        settingsWindow?.present()
    }

    @objc func newTask(_ sender: Any?) {
        dismissDropdown()
        listModel?.clearSelection()
        showMainWindow(focusInput: true)
    }

    @objc func showTasks(_ sender: Any?) {
        dismissDropdown()
        showMainWindow(focusInput: true)
    }

    @objc func showHistory(_ sender: Any?) {
        guard store != nil else { return }
        dismissDropdown()
        if historyWindow == nil {
            historyWindow = AuxiliaryWindowController(
                title: "History",
                rootView: withEnvironment(HistoryView()),
                size: NSSize(width: 400, height: 560),
                resizable: true,
                integratedTitleBar: true,
                autosaveName: "StillHistoryWindow",
                undoManager: store.undoManager
            )
        }
        historyWindow?.present()
    }

    @objc func toggleKeepOnTop(_ sender: Any?) {
        preferences.keepWindowOnTop.toggle()
    }

    @objc func quit(_ sender: Any?) {
        NSApp.terminate(sender)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleKeepOnTop(_:)) {
            menuItem.state = preferences?.keepWindowOnTop == true ? .on : .off
        }
        if menuItem.action == #selector(showHistory(_:)) || menuItem.action == #selector(newTask(_:)) {
            return store != nil
        }
        return true
    }
}
