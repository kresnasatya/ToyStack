import Engine
import SwiftUI

struct AddressBar: NSViewRepresentable {
    let address: String
    let browser: Browser
    let focus: AddressFocus

    func makeCoordinator() -> Coordinator { Coordinator(browser: browser) }

    func makeNSView(context: Context) -> AddressTextField {
        let field: AddressTextField = AddressTextField()
        field.placeholderString = "Search or enter address"
        field.bezelStyle = .roundedBezel
        field.usesSingleLineMode = true
        field.lineBreakMode = .byTruncatingTail
        field.cell?.isScrollable = true
        field.delegate = context.coordinator
        field.onFocus = { [weak browser] in browser?.activeTab?.blur() }
        focus.field = field
        return field
    }

    func updateNSView(_ field: AddressTextField, context: Context) {
        context.coordinator.browser = browser
        context.coordinator.address = address
        focus.field = field
        if field.currentEditor() == nil {
            field.stringValue = address
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        weak var browser: Browser?
        var address: String = ""

        init(browser: Browser) {
            self.browser = browser
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard commandSelector == #selector(NSResponder.insertNewline(_:)) else { return false }
            let typed: String = textView.string
            control.window?.makeFirstResponder(nil)
            if let address: TypedAddress = AddressInput.address(for: typed) {
                browser?.activeTab?.load(address.url)
            }
            return true
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            guard let field: NSTextField = notification.object as? NSTextField else { return }
            field.stringValue = address
        }
    }
}

// MARK: - AddressTextField

final class AddressTextField: NSTextField {
    var onFocus: (() -> Void)?

    // Safari, Chrome and Firefox select the whole address when it gains focus
    // so typing replaces it. A mouse click would leave a caret where it landed,
    // so the selection waits until AppKit has finished tracking that click.
    override func becomeFirstResponder() -> Bool {
        let accepted: Bool = super.becomeFirstResponder()
        if accepted {
            onFocus?()
            perform(#selector(selectWholeAddress), with: nil, afterDelay: 0)
        }
        return accepted
    }

    @objc private func selectWholeAddress() {
        currentEditor()?.selectAll(nil)
    }
}
