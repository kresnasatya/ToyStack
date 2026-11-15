import AppKit

@MainActor
final class AddressFocus {
    weak var field: NSTextField?

    func focus() {
        guard let field: NSTextField = field else { return }
        field.window?.makeFirstResponder(field)
    }

    func blur() {
        guard let field: NSTextField = field, field.currentEditor() != nil else { return }
        field.window?.makeFirstResponder(nil)
    }
}
