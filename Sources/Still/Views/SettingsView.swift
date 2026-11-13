import AppKit
import StillCore
import SwiftUI

struct SettingsView: View {
    @Environment(Preferences.self) private var preferences
    @Environment(LoginItemService.self) private var loginItems
    @Environment(HotkeyService.self) private var hotkeys

    var body: some View {
        @Bindable var preferences = preferences
        Form {
            Section("General") {
                Toggle("Open at login", isOn: Binding(
                    get: { loginItems.isEnabled || loginItems.requiresApproval },
                    set: { enabled in
                        loginItems.setEnabled(enabled)
                        preferences.hasAnsweredLoginItemPrompt = true
                    }
                ))
                if loginItems.requiresApproval {
                    note("Allow \(AppInfo.name) in System Settings to finish turning this on.") {
                        Button("Open Login Items…") { loginItems.openSystemSettings() }
                    }
                } else if let error = loginItems.lastError {
                    note(error)
                }

                LabeledContent("Show or hide \(AppInfo.name)") {
                    ShortcutRecorder(combo: preferences.hotKeyEnabled ? preferences.hotKey : nil) { combo in
                        if let combo {
                            preferences.hotKey = combo
                            preferences.hotKeyEnabled = true
                        } else {
                            preferences.hotKeyEnabled = false
                        }
                    }
                }
                if case .unavailable(let combo) = hotkeys.status {
                    note("\(combo.displayString) is in use by another app. Choose a different shortcut.")
                }

                Toggle("Show in menu bar", isOn: $preferences.showMenuBarIcon)
                note("Click the icon to drop down your list. Right-click it for more options.")
            }

            Section("Window") {
                Toggle("Keep window on top", isOn: $preferences.keepWindowOnTop)
                note("Keeps the task window above other app windows.")
            }

            Section("Appearance") {
                Picker("Appearance", selection: $preferences.appearance) {
                    Text("System").tag(AppearancePreference.system)
                    Text("Light").tag(AppearancePreference.light)
                    Text("Dark").tag(AppearancePreference.dark)
                }
                .pickerStyle(.segmented)
            }

            Section("Tasks") {
                Picker("When completed", selection: $preferences.placement) {
                    Text("Move to bottom").tag(CompletedPlacement.moveToBottom)
                    Text("Stay in position").tag(CompletedPlacement.stayInPosition)
                }
                Picker("Show completed tasks", selection: $preferences.retention) {
                    Text("Until tomorrow").tag(CompletedRetention.untilTomorrow)
                    Text("For seven days").tag(CompletedRetention.sevenDays)
                    Text("Forever").tag(CompletedRetention.forever)
                }
                Picker("Measure time in", selection: $preferences.calculation) {
                    Text("Calendar days").tag(RetentionCalculation.calendar)
                    Text("Elapsed hours").tag(RetentionCalculation.relative)
                }
                .disabled(preferences.retention == .forever)
                note(calculationExplanation)
                note("Hidden tasks are never deleted. Find them in History (⇧⌘H).")
            }

            Section("Advanced") {
                Picker("Count time from", selection: $preferences.reference) {
                    Text("Completion").tag(RetentionReference.completion)
                    Text("Creation").tag(RetentionReference.creation)
                }
                .disabled(preferences.retention == .forever)
                if preferences.reference == .creation {
                    note("A task added days ago will leave the list as soon as it’s completed.")
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 470)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var calculationExplanation: String {
        switch (preferences.retention, preferences.calculation) {
        case (.forever, _):
            "Completed tasks stay in the list until you delete them."
        case (.untilTomorrow, .calendar):
            "Completed tasks clear at midnight."
        case (.untilTomorrow, .relative):
            "Completed tasks clear 24 hours after completion."
        case (.sevenDays, .calendar):
            "Completed tasks clear at midnight, seven days later."
        case (.sevenDays, .relative):
            "Completed tasks clear seven days (168 hours) after completion."
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func note(_ text: String, @ViewBuilder action: () -> some View) -> some View {
        HStack {
            note(text)
            Spacer()
            action()
        }
    }
}

/// Click to record a new global shortcut. Escape cancels; Delete clears.
struct ShortcutRecorder: View {
    let combo: KeyCombo?
    let onChange: (KeyCombo?) -> Void

    @State private var isRecording = false
    @State private var monitor: Any?
    @State private var hint: String?

    var body: some View {
        HStack(spacing: 6) {
            Button {
                isRecording ? stop() : start()
            } label: {
                Text(label)
                    .font(.system(size: 12, weight: .medium).monospaced())
                    .foregroundStyle(isRecording ? .secondary : .primary)
                    .frame(minWidth: 96)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Global shortcut")
            .accessibilityValue(isRecording ? "Recording" : (combo?.accessibilityName ?? "None"))
            .accessibilityHint("Press to record a new shortcut.")

            if combo != nil && !isRecording {
                Button {
                    onChange(nil)
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Turn off the shortcut")
                .accessibilityLabel("Clear shortcut")
            }
        }
        .onDisappear(perform: stop)
    }

    private var label: String {
        if isRecording { return hint ?? "Type shortcut…" }
        return combo?.displayString ?? "None"
    }

    private func start() {
        hint = nil
        isRecording = true
        GlobalShortcutPause.isPaused = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            switch Int(event.keyCode) {
            case 53: // Escape
                stop()
            case 51, 117: // Delete, Forward Delete
                onChange(nil)
                stop()
            default:
                if let combo = KeyCombo(event: event) {
                    onChange(combo)
                    stop()
                } else {
                    hint = "Include ⌘ or ⌃"
                    NSSound.beep()
                }
            }
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
        GlobalShortcutPause.isPaused = false
    }
}

/// While recording a shortcut, the existing global shortcut is suspended so pressing
/// it records rather than toggles the window.
@MainActor
enum GlobalShortcutPause {
    static var onChange: ((Bool) -> Void)?
    static var isPaused = false {
        didSet { if isPaused != oldValue { onChange?(isPaused) } }
    }
}
