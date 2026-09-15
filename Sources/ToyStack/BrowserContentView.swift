import CoreImage
import Combine
import Engine
import SwiftUI

final class ContentLayerView: NSView {
    override var isFlipped: Bool { true }
    private let contentLayer = CALayer()
    private let scrollbarLayer = CALayer()
    private var presenter: ContentPresenter?
    private weak var browser: Browser?
    private weak var measure: MeasureTime?

    private func ensureLayers() {
        guard contentLayer.superlayer == nil else { return }
        wantsLayer = true
        layer?.masksToBounds = true
        contentLayer.contentsGravity = .topLeft
        scrollbarLayer.cornerRadius = 4
        layer?.addSublayer(contentLayer)
        layer?.addSublayer(scrollbarLayer)
    }

    func attach(_ browser: Browser) {
        self.browser = browser
        ensureLayers()
        if presenter == nil {
            presenter = ContentPresenter(
                contentLayer: contentLayer,
                scrollbarLayer: scrollbarLayer,
                measure: browser.measure
            )
        }
    }

    func detach() {
        browser?.onPresent = nil
        presenter = nil
    }

    func present(_ frame: PresentedFrame) {
        presenter?.enqueue(frame, viewSize: bounds.size)
    }

    func apply(_ browser: Browser) {
        self.browser = browser
        ensureLayers()
        measure?.start("present.main")
        presenter?.enqueue(browser.presentedFrame, viewSize: bounds.size)
        measure?.stop("present.main")
    }

    override func layout() {
        super.layout()
        if let browser { apply(browser) }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

struct BrowserContentView: NSViewRepresentable {
    let browser: Browser

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> ContentLayerView {
        let view = ContentLayerView()
        view.attach(browser)
        view.apply(browser)
        context.coordinator.observe(browser: browser, view: view)
        return view
    }

    func updateNSView(_ view: ContentLayerView, context: Context) {
        view.apply(browser)
    }

    static func dismantleNSView(_ view: ContentLayerView, coordinator: Coordinator) {
        view.detach()
    }

    @MainActor
    final class Coordinator {
        private var cancellable: AnyCancellable?

        func observe(browser: Browser, view: ContentLayerView) {
            browser.onPresent = { [weak view] frame in
                guard let view else { return }
                view.present(frame)
            }
            cancellable = browser.objectWillChange.sink { [weak browser, weak view] _ in
                guard let browser, let view else { return }
                view.apply(browser)
            }
        }
    }
}
