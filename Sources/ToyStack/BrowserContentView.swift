import Combine
import Engine
import SwiftUI

final class ContentLayerView: NSView {
    func apply(_ browser: Browser) {
        wantsLayer = true
        layer?.contents = browser.contentImage
        layer?.contentsScale = browser.displayScale
        print("[view] contents=\(browser.contentImage.map { "\($0.width)x\($0.height)" } ?? "nil") scale=\(browser.displayScale) bounds=\(layer?.bounds ?? .zero)")
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
            cancellable = browser.objectWillChange.sink { [weak browser, weak view] _ in
                guard let browser, let view else { return }
                view.apply(browser)
            }
        }
    }
}
