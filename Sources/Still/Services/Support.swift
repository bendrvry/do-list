import AppKit
import Observation

/// Re-runs `apply` whenever any observable property it reads changes.
@MainActor
func trackChanges(_ apply: @escaping @MainActor () -> Void) {
    withObservationTracking {
        apply()
    } onChange: {
        DispatchQueue.main.async {
            MainActor.assumeIsolated { trackChanges(apply) }
        }
    }
}

/// Presents unexpected failures (for example a disk write error) without crashing or
/// silently losing the change. Ordinary interactions never show dialogs.
@MainActor
enum ErrorPresenter {
    static func present(_ error: Error) {
        NSSound.beep()
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "That change couldn't be saved."
        alert.informativeText = "\(error.localizedDescription)\n\nYour other tasks are unaffected."
        if let window = NSApp.keyWindow ?? NSApp.mainWindow, window.attachedSheet == nil {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }
}

/// Runs a task operation, reporting any error.
@MainActor
func perform(_ body: () throws -> Void) {
    do { try body() } catch { ErrorPresenter.present(error) }
}
