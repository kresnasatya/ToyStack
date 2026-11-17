import Engine
import SwiftUI

struct AddressBar: NSViewRepresentable {
    let url: WebURL?
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
        let coordinator: Coordinator = context.coordinator
        field.onFocus = { [weak browser, weak field] in
            browser?.activeTab?.blur()
            field?.showWhileEditing(coordinator.fullAddress)
        }
        focus.field = field
        return field
    }

    func updateNSView(_ field: AddressTextField, context: Context) {
        context.coordinator.browser = browser
        context.coordinator.url = url
        focus.field = field
        if field.currentEditor() == nil {
            field.stringValue = context.coordinator.shownAddress
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        weak var browser: Browser?
        var url: WebURL? = nil
        var fullAddress: String { url?.toString() ?? "" }
        var shownAddress: String { url.map({ (url: WebURL) -> String in AddressDisplay.text(for: url) }) ?? "" }

        init(browser: Browser) {
            self.browser = browser
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard commandSelector == #selector(NSResponder.insertNewline(_:)) else { return false }
            let typed: String = textView.string
            control.window?.makeFirstResponder(nil)
            if let address: TypedAddress = AddressInput.address(for: typed) {
                browser?.activeTab?.open(address)
            }
            return true
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            guard let field: NSTextField = notification.object as? NSTextField else { return }
            field.stringValue = shownAddress
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

    /// Editing starts from the real address: the shortened one drops parts
    /// such as "www." that pressing Enter would otherwise lose.
    func showWhileEditing(_ fullAddress: String) {
        stringValue = fullAddress
        currentEditor()?.string = fullAddress
    }

    @objc private func selectWholeAddress() {
        currentEditor()?.selectAll(nil)
    }
}
