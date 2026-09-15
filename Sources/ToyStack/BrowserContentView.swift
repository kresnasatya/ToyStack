import CoreImage
import Combine
import Engine
import SwiftUI

final class ContentLayerView: NSView {
    override var isFlipped: Bool { true }
    private let contentLayer = CALayer()
    private let scrollbarLayer = CALayer()
    private var lastImage: CGImage?
    private var layersByPlacement: [PlacedLayerKey: CALayer] = [:]
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

    func apply(_ browser: Browser) {
        self.browser = browser
        apply(browser.presentedFrame, measure: browser.measure)
    }

    func apply(_ frame: PresentedFrame, measure: MeasureTime) {
        self.measure = measure
        ensureLayers()

        measure.start("view.apply")
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { measure.stop("view.apply") }
        defer {
            measure.start("view.commit")
            CATransaction.commit()
            measure.stop("view.commit")
        }

        if frame.content.usesSublayers {
            applySublayers(frame)
        } else {
            applyImage(frame)
        }

        applyScrollbar(frame.viewport.scrollbar)
    }

    private func applyScrollbar(_ scrollbar: (frame: CGRect, color: CGColor)?) {
        if let scrollbar {
            scrollbarLayer.isHidden = false
            scrollbarLayer.backgroundColor = scrollbar.color
            scrollbarLayer.frame = scrollbar.frame
        } else {
            scrollbarLayer.isHidden = true
        }
    }

    private func applySublayers(_ frame: PresentedFrame) {
        if lastImage != nil {
            lastImage = nil
            contentLayer.contents = nil
        }
        contentLayer.backgroundColor = frame.viewport.canvasColor
        contentLayer.frame = CGRect(
            x: 0,
            y: frame.viewport.contentOffset,
            width: bounds.width,
            height: bounds.height
        )
        let placements = frame.content.placements
        measure?.start("view.updateSublayers")
        var seen: Set<PlacedLayerKey> = []
        seen.reserveCapacity(placements.count)
        var added = 0
        for placed in placements {
            seen.insert(placed.key)
            let layer: CALayer
            if let existing = layersByPlacement[placed.key] {
                layer = existing
            } else {
                layer = makeSublayer(scale: frame.viewport.displayScale)
                layersByPlacement[placed.key] = layer
                added += 1
            }
            updateSublayer(layer, with: placed)
        }
        let stale = layersByPlacement.keys.filter { !seen.contains($0) }
        for key in stale {
            layersByPlacement[key]?.removeFromSuperlayer()
            layersByPlacement.removeValue(forKey: key)
        }
        measure?.stop("view.updateSublayers")
        measure?.counter("view", [
            "placements": placements.count,
            "added": added,
            "removed": stale.count,
            "sublayers": contentLayer.sublayers?.count ?? 0
        ])
    }

    private func makeSublayer(scale: CGFloat) -> CALayer {
        let layer = CALayer()
        layer.contentsGravity = .resize
        layer.contentsScale = scale
        contentLayer.addSublayer(layer)
        return layer
    }

    private func updateSublayer(_ layer: CALayer, with placed: PlacedLayer) {
        if (layer.contents as AnyObject?) !== placed.image {
            layer.contents = placed.image
        }
        if layer.frame != placed.frame {
            layer.frame = placed.frame
        }
        let z = CGFloat(placed.zIndex)
        if layer.zPosition != z {
            layer.zPosition = z
        }
        guard let effect = placed.effect else { return }
        applyEffect(effect, to: layer)
        if layer.compositingFilter == nil {
            applyBlend(effect, to: layer)
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

    private func applyImage(_ frame: PresentedFrame) {
        if !layersByPlacement.isEmpty {
            contentLayer.sublayers?.forEach { $0.removeFromSuperlayer() }
            layersByPlacement.removeAll()
        }

        if let image = frame.content.image, image !== lastImage {
            lastImage = image
            contentLayer.contents = image
            contentLayer.contentsScale = frame.viewport.displayScale
        }
        guard let image = lastImage else { return }

        let imageHeight = CGFloat(image.height) / frame.viewport.displayScale
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
            browser.onPresent = { [weak browser, weak view] frame in
                guard let browser, let view else { return }
                view.apply(frame, measure: browser.measure)
            }
            cancellable = browser.objectWillChange.sink { [weak browser, weak view] _ in
                guard let browser, let view else { return }
                view.apply(browser)
            }
        }
    }
}
