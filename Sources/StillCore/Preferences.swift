import Foundation
import Observation

public enum CompletedPlacement: String, CaseIterable, Sendable {
    case moveToBottom
    case stayInPosition
}

public enum CompletedRetention: String, CaseIterable, Sendable {
    case untilTomorrow
    case sevenDays
    case forever

    /// Number of days a completed task stays in the active list, or `nil` for forever.
    public var days: Int? {
        switch self {
        case .untilTomorrow: 1
        case .sevenDays: 7
        case .forever: nil
        }
    }
}

public enum RetentionCalculation: String, CaseIterable, Sendable {
    /// Hide at a local midnight boundary.
    case calendar
    /// Hide after an elapsed duration (24 hours per day).
    case relative
}

public enum RetentionReference: String, CaseIterable, Sendable {
    case completion
    case creation
}

public enum AppearancePreference: String, CaseIterable, Sendable {
    case system
    case light
    case dark
}

/// A keyboard shortcut stored as a virtual key code plus Carbon-style modifier flags.
public struct KeyCombo: Equatable, Codable, Sendable {
    public var keyCode: UInt32
    /// Carbon modifier mask (cmdKey, optionKey, controlKey, shiftKey).
    public var modifiers: UInt32

    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    // Carbon constants, duplicated here so the core stays free of Carbon.
    public static let commandMask: UInt32 = 1 << 8
    public static let shiftMask: UInt32 = 1 << 9
    public static let optionMask: UInt32 = 1 << 11
    public static let controlMask: UInt32 = 1 << 12

    /// Control + Option + T
    public static let `default` = KeyCombo(keyCode: 17, modifiers: controlMask | optionMask)
}

/// Settings that are visible to the task logic. Value type so it can be passed
/// into pure functions and tests.
public struct TaskDisplayOptions: Equatable, Sendable {
    public var placement: CompletedPlacement
    public var retention: CompletedRetention
    public var calculation: RetentionCalculation
    public var reference: RetentionReference

    public init(
        placement: CompletedPlacement = .moveToBottom,
        retention: CompletedRetention = .untilTomorrow,
        calculation: RetentionCalculation = .calendar,
        reference: RetentionReference = .completion
    ) {
        self.placement = placement
        self.retention = retention
        self.calculation = calculation
        self.reference = reference
    }
}

/// User preferences, persisted in UserDefaults. Changes apply immediately.
@MainActor
@Observable
public final class Preferences {
    @ObservationIgnored private let defaults: UserDefaults

    private enum Key {
        static let placement = "completedPlacement"
        static let retention = "completedRetention"
        static let calculation = "retentionCalculation"
        static let reference = "retentionReference"
        static let appearance = "appearance"
        static let floating = "keepWindowOnTop"
        static let showMenuBarIcon = "showMenuBarIcon"
        static let hotKey = "globalShortcut"
        static let hotKeyEnabled = "globalShortcutEnabled"
        static let loginItemAsked = "launchAtLoginAsked"
    }

    public var placement: CompletedPlacement {
        didSet { defaults.set(placement.rawValue, forKey: Key.placement) }
    }
    public var retention: CompletedRetention {
        didSet { defaults.set(retention.rawValue, forKey: Key.retention) }
    }
    public var calculation: RetentionCalculation {
        didSet { defaults.set(calculation.rawValue, forKey: Key.calculation) }
    }
    public var reference: RetentionReference {
        didSet { defaults.set(reference.rawValue, forKey: Key.reference) }
    }
    public var appearance: AppearancePreference {
        didSet { defaults.set(appearance.rawValue, forKey: Key.appearance) }
    }
    public var keepWindowOnTop: Bool {
        didSet { defaults.set(keepWindowOnTop, forKey: Key.floating) }
    }
    public var showMenuBarIcon: Bool {
        didSet { defaults.set(showMenuBarIcon, forKey: Key.showMenuBarIcon) }
    }
    public var hotKey: KeyCombo {
        didSet {
            if let data = try? JSONEncoder().encode(hotKey) { defaults.set(data, forKey: Key.hotKey) }
        }
    }
    public var hotKeyEnabled: Bool {
        didSet { defaults.set(hotKeyEnabled, forKey: Key.hotKeyEnabled) }
    }
    /// Whether the one-time "open at login?" question has been answered.
    public var hasAnsweredLoginItemPrompt: Bool {
        didSet { defaults.set(hasAnsweredLoginItemPrompt, forKey: Key.loginItemAsked) }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        func value<T: RawRepresentable>(_ key: String, _ fallback: T) -> T where T.RawValue == String {
            guard let raw = defaults.string(forKey: key) else { return fallback }
            return T(rawValue: raw) ?? fallback
        }
        placement = value(Key.placement, .moveToBottom)
        retention = value(Key.retention, .untilTomorrow)
        calculation = value(Key.calculation, .calendar)
        reference = value(Key.reference, .completion)
        appearance = value(Key.appearance, .system)
        keepWindowOnTop = defaults.bool(forKey: Key.floating)
        // On by default: the icon opens the menu bar dropdown.
        showMenuBarIcon = defaults.object(forKey: Key.showMenuBarIcon) as? Bool ?? true
        hotKey = defaults.data(forKey: Key.hotKey).flatMap { try? JSONDecoder().decode(KeyCombo.self, from: $0) } ?? .default
        hotKeyEnabled = defaults.object(forKey: Key.hotKeyEnabled) as? Bool ?? true
        hasAnsweredLoginItemPrompt = defaults.bool(forKey: Key.loginItemAsked)
    }

    public var displayOptions: TaskDisplayOptions {
        TaskDisplayOptions(placement: placement, retention: retention, calculation: calculation, reference: reference)
    }
}
