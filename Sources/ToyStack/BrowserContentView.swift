import Combine
import Engine
import SwiftUI

final class ContentLayerView: NSView {
    override var isFlipped: Bool { true }
    private let contentLayer = CALayer()
    private let scrollbarLayer = CALayer()
    private var lastImage: CGImage?
    private var lastTilesVersion = -1
    private weak var browser: Browser?

    private func ensureLayers() {
        guard contentLayer.superlayer == nil else { return }
        wantsLayer = true
        layer?.masksToBounds = true
        contentLayer.contentsGravity = .topLeft
        scrollbarLayer.cornerRadius = 4
        layer?.addSublayer(contentLayer)
        layer?.addSublayer(scrollbarLayer)
    }

    func apply(_ browser: Browser) {
        self.browser = browser
        ensureLayers()

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        if browser.usesTiles {
            applyTiles(browser)
        } else {
            applyImage(browser)
        }



        if let bar = browser.activeSidebar {
            scrollbarLayer.isHidden = false
            scrollbarLayer.backgroundColor = bar.color
            scrollbarLayer.frame = bar.frame
        } else {
            scrollbarLayer.isHidden = true
        }
    }

    private func applyTiles(_ browser: Browser) {
        if lastImage != nil {
            lastImage = nil
            contentLayer.contents = nil
        }
        contentLayer.backgroundColor = browser.canvasColor
        contentLayer.frame = CGRect(
            x: 0,
            y: browser.topInset - browser.activeTabScroll,
            width: bounds.width,
            height: bounds.height
        )
        guard browser.tilesVersion != lastTilesVersion else { return }
        lastTilesVersion = browser.tilesVersion
        contentLayer.sublayers?.forEach { $0.removeFromSuperlayer() }
        for tile in browser.activeTiles {
            let layer = CALayer()
            layer.contents = tile.image
            layer.contentsScale = browser.displayScale
            layer.contentsGravity = .resize
            layer.frame = tile.frame
            layer.zPosition = CGFloat(tile.zIndex)
            contentLayer.addSublayer(layer)
        }
    }

    private func applyImage(_ browser: Browser) {
        if lastTilesVersion != -1 {
            lastTilesVersion = -1
            contentLayer.sublayers?.forEach { $0.removeFromSuperlayer() }
        }

        if let image = browser.contentImage, image !== lastImage {
            lastImage = image
            contentLayer.contents = image
            contentLayer.contentsScale = browser.displayScale
        }
        guard let image = lastImage else { return }

        let imageHeight = CGFloat(image.height) / browser.displayScale
        contentLayer.frame = CGRect(
            x: 0,
            y: 0,
            width: bounds.width,
            height: imageHeight
        )
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
            browser.onContentImage = { [weak browser, weak view] in
                guard let browser, let view else { return }
                view.apply(browser)
            }
            browser.onScroll = { [weak browser, weak view] in
                guard let browser, let view else { return }
                view.apply(browser)
            }
            cancellable = browser.objectWillChange.sink { [weak browser, weak view] _ in
                guard let browser, let view else { return }
                view.apply(browser)
            }
        }
    }
}
