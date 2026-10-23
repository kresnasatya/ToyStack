import CoreGraphics
import CoreImage
import QuartzCore
import Engine

final class ContentPresenter: @unchecked Sendable {

    private struct Slot {
        let layer: CALayer
        var lastSeen: Int
        var hidden: Bool
    }

    private let queue = DispatchQueue(label: "browser.present", qos: .userInteractive)
    private let measure: MeasureTime
    private let contentLayer: CALayer
    private let scrollbarLayer: CALayer
    private var lastImage: CGImage?
    private var layersByPlacement: [LayerPlacementKey: Slot] = [:]
    private var frameNumber: Int = 0
    private var lastUsesSublayers: Bool?
    private let graceFrames: Int = 10
    private let lock = NSLock()
    private var latest: (frame: PresentedFrame, viewSize: CGSize)?
    private var applied: (revision: Int, size: CGSize)?
    private var presenting = false
    private var coalesced = 0

    init(contentLayer: CALayer, scrollbarLayer: CALayer, measure: MeasureTime) {
        self.contentLayer = contentLayer
        self.scrollbarLayer = scrollbarLayer
        self.measure = measure
    }

    func enqueue(_ frame: PresentedFrame, viewSize: CGSize) {
        lock.lock()
        if applied?.revision == frame.revision, applied?.size == viewSize {
            lock.unlock()
            return
        }
        if latest?.frame.revision == frame.revision, latest?.viewSize == viewSize {
            lock.unlock()
            return
        }
        if latest != nil { coalesced += 1 }
        latest = (frame, viewSize)
        let kick = !presenting
        if kick { presenting = true }
        lock.unlock()
        if kick { queue.async { self.drain() }}
    }

    private func drain() {
        measure.noteStream("browser.present")
        while true {
            lock.lock()
            guard let next = latest else {
                presenting = false
                lock.unlock()
                return
            }
            latest = nil
            let coalescedNow = coalesced
            coalesced = 0
            lock.unlock()

            present(next.frame, viewSize: next.viewSize)
            measure.counter("present", [
                "coalesced": coalescedNow
            ], frame: next.frame.frameID)
        }
    }

    private func present(_ frame: PresentedFrame, viewSize: CGSize) {
        frameNumber += 1
        let usesSublayers: Bool = frame.content.usesSublayers
        let flipped: Bool = lastUsesSublayers.map({ $0 != usesSublayers }) ?? false
        measure.counter("view.usesSublayersFlips", [
            "flip" : flipped ? 1 : 0,
            "sublayers": usesSublayers ? 1 : 0
        ], frame: frame.frameID)
        lastUsesSublayers = usesSublayers
        lock.lock()
        applied = (frame.revision, viewSize)
        lock.unlock()
        measure.start("view.apply", category: .present, frame: frame.frameID)
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        if frame.content.usesSublayers {
            applySublayers(frame, viewSize: viewSize)
        } else {
            applyImage(frame, viewSize: viewSize)
        }
        applyScrollbar(frame.viewport.scrollbar)
        measure.stop("view.apply")

        measure.start("view.commit", category: .present, frame: frame.frameID)
        CATransaction.commit()
        measure.stop("view.commit")
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
        measure.start("view.updateSublayers", category: .present, frame: frame.frameID)
        let previous: Set<LayerPlacementKey> = Set(layersByPlacement.keys)
        let diff: PlacementDiff = PlacementDiff(
            previous: previous,
            current: placements.map(\.key)
        )
        var added = 0
        var unhidden = 0
        var removedNow = 0
        var purged = 0
        for placed in placements {
            let layer: CALayer
            if var slot = layersByPlacement[placed.key] {
                layer = slot.layer
                slot.lastSeen = frameNumber
                if slot.hidden {
                    slot.hidden = false
                    layer.isHidden = false
                    unhidden += 1
                }
                layersByPlacement[placed.key] = slot
            } else {
                layer = makeSublayer(scale: frame.viewport.displayScale)
                layersByPlacement[placed.key] = Slot(
                    layer: layer,
                    lastSeen: frameNumber,
                    hidden: false
                )
                added += 1
            }
            updateSublayer(layer, with: placed)
        }
        for key in diff.removed {
            guard var slot = layersByPlacement[key] else { continue }
            if !slot.hidden {
                slot.hidden = true
                slot.layer.isHidden = true
                removedNow += 1
            }
            layersByPlacement[key] = slot
        }
        for key in Array(layersByPlacement.keys) {
            guard let slot = layersByPlacement[key] else { continue }
            guard frameNumber - slot.lastSeen > graceFrames else { continue }
            slot.layer.removeFromSuperlayer()
            layersByPlacement.removeValue(forKey: key)
            purged += 1
        }
        measure.stop("view.updateSublayers")
        measure.counter("view", [
            "placements": placements.count,
            "added": added,
            "removed": removedNow,
            "kept": diff.kept,
            "hidden": layersByPlacement.values.filter(\.hidden).count,
            "unhidden": unhidden,
            "purged": purged,
            "pool": layersByPlacement.count,
            "sublayers": contentLayer.sublayers?.count ?? 0
        ], frame: frame.frameID)
    }

    private func makeSublayer(scale: CGFloat) -> CALayer {
        let layer = CALayer()
        layer.contentsGravity = .resize
        layer.contentsScale = scale
        contentLayer.addSublayer(layer)
        return layer
    }

    private func updateSublayer(_ layer: CALayer, with placed: LayerPlacement) {
        if (layer.contents as AnyObject?) !== placed.image {
            layer.contents = placed.image
        }
        layer.transform = CATransform3DIdentity
        let frame: CGRect = clipFrame(for: placed, on: layer)
        if layer.frame != frame {
            layer.frame = frame
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

    private func clipFrame(for placed: LayerPlacement, on layer: CALayer) -> CGRect {
        guard let clip = placed.effect?.clipRect else {
            layer.contentsRect = CGRect(x: 0, y: 0, width: 1, height: 1)
            layer.masksToBounds = false
            return placed.frame
        }
        guard !clip.isEmpty else {
            layer.contentsRect = CGRect(x: 0, y: 0, width: 1, height: 1)
            layer.masksToBounds = false
            return .zero
        }
        let bounds: CGRect = placed.frame
        let visible: CGRect = bounds.intersection(clip.cgRect)
        guard bounds.width > 0, bounds.height > 0,
            visible.width > 0, visible.height > 0
        else { return .zero }
        layer.contentsRect = CGRect(
            x: (visible.minX - bounds.minX) / bounds.width,
            y: (visible.minY - bounds.minY) / bounds.height,
            width: visible.width / bounds.width,
            height: visible.height / bounds.height
        )
        layer.masksToBounds = true
        return visible
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
        for key in Array(layersByPlacement.keys) {
            guard var slot = layersByPlacement[key] else { continue }
            if !slot.hidden {
                slot.hidden = true
                slot.layer.isHidden = true
            }
            layersByPlacement[key] = slot
        }

        for key in Array(layersByPlacement.keys) {
            guard let slot = layersByPlacement[key] else { continue }
            guard frameNumber - slot.lastSeen > graceFrames else { continue }
            slot.layer.removeFromSuperlayer()
            layersByPlacement.removeValue(forKey: key)
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
