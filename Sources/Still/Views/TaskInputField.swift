import AppKit
import SwiftUI

/// Lets the app move keyboard focus into the "Add a task…" field from anywhere
/// (global shortcut, ⌘N, Escape from the list).
@MainActor
@Observable
final class InputFocus {
    private(set) var isFocused = false

    /// Whether the field (including any text still being typed) is empty.
    var isEmpty: Bool {
        guard let field else { return true }
        return (field.currentEditor()?.string ?? field.stringValue).isEmpty
    }
    @ObservationIgnored fileprivate weak var field: NSTextField?
    @ObservationIgnored private var pending = false

    func focus() {
        guard let field, let window = field.window else {
            pending = true
            return
        }
        pending = false
        if window.firstResponder !== field.currentEditor() {
            window.makeFirstResponder(field)
            // Place the caret at the end rather than selecting a half-typed task, so
            // further typing adds to it instead of replacing it.
            if let editor = field.currentEditor() {
                editor.selectedRange = NSRange(location: (editor.string as NSString).length, length: 0)
            }
        }
    }

    fileprivate func attach(_ field: NSTextField) {
        self.field = field
        if pending {
            DispatchQueue.main.async { MainActor.assumeIsolated { self.focus() } }
        }
    }

    fileprivate func setFocused(_ focused: Bool) {
        if isFocused != focused { isFocused = focused }
    }
}

/// The task-entry field. An AppKit text field gives precise control over focus,
/// Return/Escape/arrow handling and undo, which matters for rapid entry.
struct TaskInputField: NSViewRepresentable {
    @Binding var text: String
    let focus: InputFocus
    let onSubmit: (String) -> Void
    let onMoveDown: () -> Void

    func makeNSView(context: Context) -> InputTextField {
        let field = InputTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = Theme.taskNSFont
        field.textColor = NSColor.still.primaryText
        field.usesSingleLineMode = true
        field.lineBreakMode = .byTruncatingTail
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.placeholderAttributedString = NSAttributedString(
            string: "Add a task…",
            attributes: [.foregroundColor: NSColor.still.placeholder, .font: Theme.taskNSFont]
        )
        field.setAccessibilityLabel("New task")
        field.setAccessibilityHelp("Type a task and press Return to add it.")
        field.delegate = context.coordinator
        field.onFocusChange = { [focus] in focus.setFocused($0) }
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        focus.attach(field)
        return field
    }

    func updateNSView(_ field: InputTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: TaskInputField
        init(parent: TaskInputField) { self.parent = parent }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            (notification.object as? InputTextField)?.onFocusChange?(false)
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                submit(control as! NSTextField)
                return true
            case #selector(NSResponder.moveDown(_:)):
                parent.onMoveDown()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                if !textView.string.isEmpty {
                    textView.string = ""
                    parent.text = ""
                    return true
                }
                return false
            default:
                return false
            }
        }

        private func submit(_ field: NSTextField) {
            let value = field.stringValue
            guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            // End and restart editing so the field's typing history is discarded and
            // ⌘Z undoes "Add Task" rather than the keystrokes that formed it.
            let window = field.window
            window?.makeFirstResponder(nil)
            field.stringValue = ""
            parent.text = ""
            parent.onSubmit(value)
            window?.makeFirstResponder(field)
        }
    }
}

final class InputTextField: NSTextField {
    var onFocusChange: ((Bool) -> Void)?

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { onFocusChange?(true) }
        return accepted
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: super.intrinsicContentSize.height)
    }
}
