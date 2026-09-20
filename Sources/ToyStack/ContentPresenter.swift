import CoreGraphics
import CoreImage
import QuartzCore
import Engine

final class ContentPresenter: @unchecked Sendable {
    private let queue = DispatchQueue(label: "browser.present", qos: .userInteractive)
    private let measure: MeasureTime
    private let contentLayer: CALayer
    private let scrollbarLayer: CALayer
    private var lastImage: CGImage?
    private var layersByPlacement: [PlacedLayerKey: CALayer] = [:]

    private let lock = NSLock()
    private var latest: (frame: PresentedFrame, viewSize: CGSize)?
    private var presenting = false
    private var dropped = 0

    init(contentLayer: CALayer, scrollbarLayer: CALayer, measure: MeasureTime) {
        self.contentLayer = contentLayer
        self.scrollbarLayer = scrollbarLayer
        self.measure = measure
    }

    func enqueue(_ frame: PresentedFrame, viewSize: CGSize) {
        lock.lock()
        if latest != nil { dropped += 1 }
        latest = (frame, viewSize)
        let kick = !presenting
        if kick { presenting = true }
        lock.unlock()
        if kick { queue.async { self.drain() }}
    }

    private func drain() {
        while true {
            lock.lock()
            guard let next = latest else {
                presenting = false
                lock.unlock()
                return
            }
            latest = nil
            let droppedNow = dropped
            dropped = 0
            lock.unlock()

            present(next.frame, viewSize: next.viewSize)
            measure.counter("present", [
                "dropped": droppedNow
            ])
        }
    }

    private func present(_ frame: PresentedFrame, viewSize: CGSize) {
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
            applySublayers(frame, viewSize: viewSize)
        } else {
            applyImage(frame, viewSize: viewSize)
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

    private func applySublayers(_ frame: PresentedFrame, viewSize: CGSize) {
        if lastImage != nil {
            lastImage = nil
            contentLayer.contents = nil
        }
        contentLayer.backgroundColor = frame.viewport.canvasColor
        contentLayer.frame = CGRect(
            x: 0,
            y: frame.viewport.contentOffset,
            width: viewSize.width,
            height: viewSize.height
        )
        let placements = frame.content.placements
        measure.start("view.updateSublayers")
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
        measure.stop("view.updateSublayers")
        measure.counter("view", [
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
        layer.transform = CATransform3DIdentity
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

    private func applyImage(_ frame: PresentedFrame, viewSize: CGSize) {
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
            width: viewSize.width,
            height: imageHeight
        )
    }
}
