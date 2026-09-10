import Combine
import Engine
import SwiftUI

final class ContentLayerView: NSView {
    func apply(_ browser: Browser) {
        wantsLayer = true
        layer?.contents = browser.contentImage
        layer?.contentsScale = browser.displayScale
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

struct BrowserContentView: NSViewRepresentable {
    let browser: Browser

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> ContentLayerView {
        let view = ContentLayerView()
        view.apply(browser)
        context.coordinator.observe(browser: browser, view: view)
        return view
    }

    func updateNSView(_ view: ContentLayerView, context: Context) {
        view.apply(browser)
    }

    @MainActor
    final class Coordinator {
        private var cancellable: AnyCancellable?

        func observe(browser: Browser, view: ContentLayerView) {
            browser.onContentImage = { [weak view] image in
                view?.layer?.contents = image
            }
            cancellable = browser.objectWillChange.sink { [weak browser, weak view] _ in
                guard let browser, let view else { return }
                view.apply(browser)
            }
        }
    }
}
