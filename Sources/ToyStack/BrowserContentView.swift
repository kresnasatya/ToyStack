import CoreImage
import Combine
import Engine
import SwiftUI

final class ContentLayerView: NSView {
    override var isFlipped: Bool { true }
    private let contentLayer = CALayer()
    private let scrollbarLayer = CALayer()
    private var lastImage: CGImage?
    private var lastStructureVersion = -1
    private var layersByKey: [ObjectIdentifier: CALayer] = [:]
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

        browser.measure.start("view.apply")
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { browser.measure.stop("view.apply") }
        defer { CATransaction.commit() }

        if browser.usesSublayers {
            applySublayers(browser)
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

    private func applySublayers(_ browser: Browser) {
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
        let placements = browser.activePlacements
        if browser.structureVersion != lastStructureVersion {
            browser.measure.start("view.rebuild")
            lastStructureVersion = browser.structureVersion
            contentLayer.sublayers?.forEach { $0.removeFromSuperlayer() }
            for placed in browser.activePlacements {
                let layer = CALayer()
                layer.contents = placed.image
                layer.contentsScale = browser.displayScale
                layer.contentsGravity = .resize
                layer.frame = placed.frame
                layer.zPosition = CGFloat(placed.zIndex)
                if let effect = placed.effect {
                    applyEffect(effect, to: layer)
                    applyBlend(effect, to: layer)
                    if let key = effect.key { layersByKey[key] = layer }
                }
                contentLayer.addSublayer(layer)
            }
            browser.measure.stop("view.rebuild")
            browser.measure.counter("view",
                [
                    "rebuild": 1,
                    "placements": placements.count,
                    "sublayers": contentLayer.sublayers?.count ?? 0
                ]
            )
        } else {
            browser.measure.counter("view", [
                "rebuild" : 0,
                "placements": placements.count
            ])
            for placed in placements {
                guard let effect = placed.effect, let key = effect.key, let layer = layersByKey[key] else { continue }
                applyEffect(effect, to: layer)
            }
        }
    }

    private func applyEffect(_ effect: LayerEffect, to layer: CALayer) {
        layer.opacity = Float(effect.opacity)
        layer.transform = CATransform3DMakeTranslation(effect.translation.x, effect.translation.y, 0)
    }

    private func applyBlend(_ effect: LayerEffect, to layer: CALayer) {
        guard let mode = effect.blendMode,
            let name = mode.compositingFilterName,
            let filter = CIFilter(name: name)
            else { return }
        layer.compositingFilter = filter
    }

    private func applyImage(_ browser: Browser) {
        if lastStructureVersion != -1 {
            lastStructureVersion = -1
            contentLayer.sublayers?.forEach { $0.removeFromSuperlayer() }
            layersByKey.removeAll()
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
