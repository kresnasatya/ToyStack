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

    /// One tile image waiting to be bound to its layer.
    private struct LayerRebind {
        let distance: CGFloat
        let layer: CALayer
        let image: CGImage
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
    /// Binding a tile image costs 0.3-0.5 ms in the commit, so a burst of
    /// 12-24 new tiles blows the frame budget. Incremental arrivals are spread.
    private static let uploadsPerPresent: Int = 6
    private static let pixelsPerPresent: Int = 400_000
    private let lock = NSLock()
    private var latest: (frame: PresentedFrame, viewSize: CGSize)?
    private var applied: (revision: PresentedRevision, size: CGSize)?
    private var presentationState: ContentPresentationState = ContentPresentationState()
    private var presenting = false
    private var coalesced = 0
    /// Last frame applied, kept so deferred tile binds can finish without
    /// waiting for the engine to send another present.
    private var lastApplied: (frame: PresentedFrame, viewSize: CGSize)?
    private var lastDeferred: Int = 0
    private var lastBoundGeneration: UInt64 = 0
    /// Generation uploading behind the layers on screen, and the newest frame
    /// waiting for it.
    private var staging: GenerationStaging<PresentedFrame> = GenerationStaging()
    /// When the view width last changed, so a finished drag can skip an
    /// upload laid out for a width the window no longer has.
    private var resizeSettle: ResizeSettle = ResizeSettle()
    /// When the last present started; follow-up presents are paced from it.
    private var lastPresentStart: CFTimeInterval = 0
    private var pendingLayers: [LayerPlacementKey: Slot] = [:]
    private var drainScheduled: Bool = false

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
        let lane: TraceLane = measure.beginStream("browser.present")
        defer { lane.end() }
        while true {
            lock.lock()
            guard let next = latest else {
                presenting = false
                let needsDrain: Bool = (lastDeferred > 0 || staging.current != nil) && !drainScheduled
                if needsDrain { drainScheduled = true }
                lock.unlock()
                if needsDrain { scheduleDeferredDrain() }
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

    /// Tiles left unbound by the scroll budget are picked up on the next frame,
    /// but a page that lands while the pointer is still would otherwise show
    /// only the first few tiles until the user scrolls. A staged generation
    /// also needs more presents to finish. Keep presenting the same frame
    /// until both drain, one display frame after the last present started.
    private func scheduleDeferredDrain() {
        let delay: TimeInterval = PresentPacing.delay(
            lastStart: lastPresentStart,
            now: CACurrentMediaTime()
        )
        queue.asyncAfter(deadline: .now() + delay) {
            let lane: TraceLane = self.measure.beginStream("browser.present")
            defer { lane.end() }
            self.drainScheduled = false
            self.lock.lock()
            let superseded: Bool = self.latest != nil
            self.lock.unlock()
            guard !superseded else { return }
            guard let pending = self.lastApplied else { return }
            self.present(pending.frame, viewSize: pending.viewSize)
            self.measure.counter("present", [
                "coalesced": 0
            ], frame: pending.frame.frameID)
            self.drain()
        }
    }

    private func present(_ frame: PresentedFrame, viewSize: CGSize) {
        lastPresentStart = CACurrentMediaTime()
        lastApplied = (frame, viewSize)
        frameNumber += 1
        resizeSettle.note(width: viewSize.width, at: lastPresentStart)
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
        if usesSublayers {
            // Stage before deciding: a generation that completes here changes
            // the width the preview must scale from. The skip check and the
            // upload share one budget so they agree on what finishes now.
            offerGeneration(frame, viewSize: viewSize)
            let budget: PresentUploadBudget = PresentUploadBudget.generation(
                resizeSettled: resizeSettle.isSettled(at: lastPresentStart)
            )
            let skipped: Bool = skipStaleGeneration(viewSize: viewSize, budget: budget)
            stageGeneration(viewSize: viewSize, skipped: skipped, budget: budget)
        }
        let decision: ContentPresentationState.Decision = presentationState.decide(
            revision: frame.revision,
            viewSize: viewSize,
            layoutSize: frame.displayedLayoutSize,
            stagingLayers: staging.current != nil
        )
        let preview: Bool
        let previousSize: CGSize?
        switch decision {
        case .bind:
            preview = false
            previousSize = nil
        case let .preview(from: size):
            preview = true
            previousSize = size
        }
        measure.counter("view.presentation", [
            "preview": preview ? 1 : 0,
            "baseWidth": Int(previousSize?.width ?? 0),
            "viewWidth": Int(viewSize.width)
        ], frame: frame.frameID)

        if frame.content.usesSublayers {
            applySublayers(
                frame,
                viewSize: viewSize,
                preview: preview,
                previousSize: previousSize
            )
        } else {
            applyImage(frame, viewSize: viewSize, preview: preview)
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

    private func applySublayers(
        _ frame: PresentedFrame,
        viewSize: CGSize,
        preview: Bool,
        previousSize: CGSize?
    ) {
        let scale: ContentScale = frame.viewport.scale
        lastDeferred = 0
        if preview, let previousSize, previousSize.width > 0, previousSize.height > 0 {
            // Keep the last complete frame visible, but fit it into the new
            // viewport so a smaller window does not clip stale content.
            let fit: PreviewFit = PreviewFit(old: previousSize, new: viewSize)
            contentLayer.backgroundColor = frame.viewport.canvasColor
            placeContentLayer(
                originY: frame.viewport.contentOffset.origin(previewScale: fit.scale),
                scale: scale.page * fit.scale,
                viewSize: viewSize
            )
            return
        }
        if lastImage != nil {
            lastImage = nil
            contentLayer.contents = nil
        }
        contentLayer.backgroundColor = frame.viewport.canvasColor
        placeContentLayer(
            originY: frame.viewport.contentOffset.origin,
            scale: scale.page,
            viewSize: viewSize
        )
        if frame.content.source.generation != lastBoundGeneration, !layersByPlacement.isEmpty {
            // This generation is staging, or waiting, behind the layers on
            // screen; `stageGeneration` swaps it in once it is complete.
            return
        }
        let placements = frame.content.placements
        measure.start("view.updateSublayers", category: .present, frame: frame.frameID)
        let previous: Set<LayerPlacementKey> = Set(layersByPlacement.keys)
        let diff: PlacementDiff = PlacementDiff(
            previous: previous,
            current: placements.map(\.key)
        )
        let offset: CGFloat = frame.viewport.contentOffset.origin
        // A different page (or any wholesale replacement of the layer set) is
        // not an incremental arrival: bind it in one go instead of showing six
        // tiles until the next present.
        let replaced: Bool = diff.kept == 0
        let centerY: CGFloat = (-offset + viewSize.height / 2) / scale.page
        var added = 0
        var unhidden = 0
        var removedNow = 0
        var purged = 0
        var contents = 0
        var contentsPixels = 0
        var deferred = 0
        var rebinds: [LayerRebind] = []
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
                layer = makeSublayer(scale: scale.effective)
                layersByPlacement[placed.key] = Slot(
                    layer: layer,
                    lastSeen: frameNumber,
                    hidden: false
                )
                added += 1
            }
            updateSublayer(layer, with: placed, scale: scale.effective)
            if (layer.contents as AnyObject?) !== placed.image {
                rebinds.append(
                    LayerRebind(
                        distance: abs(placed.frame.midY - centerY),
                        layer: layer,
                        image: placed.image
                    )
                )
            }
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
        // A new compositor generation must be bound as one complete frame.
        // Otherwise a scroll can expose layers whose images have not arrived.
        // Within one generation, a few edge tiles may still be spread.
        let completeGeneration: Bool = frame.content.source.generation != lastBoundGeneration
        lastBoundGeneration = frame.content.source.generation
        presentationState.didShow(layoutSize: frame.displayedLayoutSize, viewSize: viewSize)
        let overhaul: Bool = replaced || rebinds.count * 2 >= placements.count
        let throttled: Bool = !overhaul && !completeGeneration
        if throttled {
            rebinds.sort(by: { $0.distance < $1.distance })
        }
        for rebind in rebinds {
            let pixels: Int = rebind.image.width * rebind.image.height
            if throttled,
                contents >= Self.uploadsPerPresent
                    || (contents > 0 && contentsPixels + pixels > Self.pixelsPerPresent)
            {
                deferred += 1
                continue
            }
            rebind.layer.contents = rebind.image
            contents += 1
            contentsPixels += pixels
        }
        lastDeferred = deferred
        measure.stop("view.updateSublayers")
        measure.counter("view", [
            "placements": placements.count,
            "added": added,
            "removed": removedNow,
            "contents": contents,
            "contentsPixels": contentsPixels,
            "deferred": deferred,
            "kept": diff.kept,
            "hidden": layersByPlacement.values.filter(\.hidden).count,
            "unhidden": unhidden,
            "purged": purged,
            "pool": layersByPlacement.count,
            "sublayers": contentLayer.sublayers?.count ?? 0
        ], frame: frame.frameID)
    }

    /// Offers a frame whose generation could replace the layers on screen.
    /// A frame laid out at another width is only previewed, never staged.
    private func offerGeneration(_ frame: PresentedFrame, viewSize: CGSize) {
        let generation: UInt64 = frame.content.source.generation
        guard generation != lastBoundGeneration, !layersByPlacement.isEmpty,
            ContentPresentationState.fitsView(
                layoutSize: frame.displayedLayoutSize,
                viewSize: viewSize
            )
        else { return }
        _ = staging.offer(frame, generation: generation)
    }

    /// Once the window width stops changing, drops an upload laid out for a
    /// width the window no longer has, so the final layout starts at once
    /// instead of waiting for a stale one. An upload this present finishes
    /// within `budget` is kept. Returns true when it skipped.
    private func skipStaleGeneration(viewSize: CGSize, budget: PresentUploadBudget) -> Bool {
        let skipped: Bool = staging.skipStale(
            settled: resizeSettle.isSettled(at: lastPresentStart),
            currentFinishesNow: { self.finishesThisPresent($0, budget: budget) },
            fits: {
                ContentPresentationState.fitsView(
                    layoutSize: $0.displayedLayoutSize,
                    viewSize: viewSize
                )
            }
        )
        if skipped {
            removePendingLayers()
        }
        return skipped
    }

    /// True when the tiles of `frame` still unbound in `pendingLayers` fit
    /// `budget`, so `stageGeneration` completes it in this present.
    private func finishesThisPresent(_ frame: PresentedFrame, budget: PresentUploadBudget) -> Bool {
        var left: [Int] = []
        for placed in frame.content.placements {
            if Self.needsBind(pendingLayers[placed.key]?.layer, to: placed) {
                left.append(placed.image.width * placed.image.height)
            }
        }
        return budget.admitsAll(pixels: left)
    }

    /// True when `layer` (nil: not created yet) does not show `placed`'s
    /// image. `stageGeneration` binds exactly these tiles, and
    /// `finishesThisPresent` predicts from the same test.
    private static func needsBind(_ layer: CALayer?, to placed: LayerPlacement) -> Bool {
        return (layer?.contents as AnyObject?) !== placed.image
    }

    /// Uploads one budgeted chunk of the staged generation behind the
    /// still-visible layers. Only a fully bound generation replaces them; the
    /// newest waiting frame then starts on the next present. Runs on every
    /// present, previews included, so a resize cannot stall the upload.
    /// `skipped` is true when this present dropped a stale upload first.
    /// `budget` is the one the skip check used in this present.
    private func stageGeneration(viewSize: CGSize, skipped: Bool, budget: PresentUploadBudget) {
        guard let entry: GenerationStaging<PresentedFrame>.Entry = staging.current else { return }
        let frame: PresentedFrame = entry.frame
        let scale: ContentScale = frame.viewport.scale
        let placements = frame.content.placements
        measure.start("view.updateSublayers", category: .present, frame: frame.frameID)
        let offset: CGFloat = frame.viewport.contentOffset.origin
        let centerY: CGFloat = (-offset + viewSize.height / 2) / scale.page
        var added: Int = 0
        var contents: Int = 0
        var contentsPixels: Int = 0
        var rebinds: [LayerRebind] = []
        for placed in placements {
            let layer: CALayer
            if let slot: Slot = pendingLayers[placed.key] {
                layer = slot.layer
            } else {
                layer = makeSublayer(scale: scale.effective)
                layer.isHidden = true
                pendingLayers[placed.key] = Slot(
                    layer: layer,
                    lastSeen: frameNumber,
                    hidden: true
                )
                added += 1
            }
            updateSublayer(layer, with: placed, scale: scale.effective)
            if Self.needsBind(layer, to: placed) {
                rebinds.append(
                    LayerRebind(
                        distance: abs(placed.frame.midY - centerY),
                        layer: layer,
                        image: placed.image
                    )
                )
            }
        }
        rebinds.sort(by: { $0.distance < $1.distance })
        var budget: PresentUploadBudget = budget
        for rebind in rebinds {
            let pixels: Int = rebind.image.width * rebind.image.height
            guard budget.take(pixels: pixels) else { continue }
            rebind.layer.contents = rebind.image
            contents += 1
            contentsPixels += pixels
        }
        let deferred: Int = rebinds.count - contents
        let complete: Bool = placements.allSatisfy {
            guard let slot: Slot = pendingLayers[$0.key] else { return false }
            return slot.layer.contents != nil
        }
        let waiting: Bool = staging.waiting != nil
        if complete {
            for slot in layersByPlacement.values {
                slot.layer.removeFromSuperlayer()
            }
            var active: [LayerPlacementKey: Slot] = pendingLayers
            for key in active.keys {
                guard var slot: Slot = active[key] else { continue }
                slot.hidden = false
                slot.layer.isHidden = false
                active[key] = slot
            }
            layersByPlacement = active
            pendingLayers.removeAll(keepingCapacity: true)
            lastBoundGeneration = entry.generation
            presentationState.didShow(layoutSize: frame.displayedLayoutSize, viewSize: viewSize)
            _ = staging.finish()
        }
        measure.stop("view.updateSublayers")
        measure.counter("view", [
            "placements": placements.count,
            "added": added,
            "contents": contents,
            "contentsPixels": contentsPixels,
            "deferred": deferred,
            "kept": 0,
            "hidden": layersByPlacement.values.filter(\.hidden).count,
            "unhidden": 0,
            "purged": 0,
            "pool": layersByPlacement.count + pendingLayers.count,
            "sublayers": contentLayer.sublayers?.count ?? 0,
        ], frame: frame.frameID)
        measure.counter("view.staging", [
            "completed": complete ? 1 : 0,
            "waiting": waiting ? 1 : 0,
            "skipped": skipped ? 1 : 0,
            "budgetPixels": budget.pixels
        ], frame: frame.frameID)
    }

    private func discardPendingGeneration() {
        removePendingLayers()
        staging.cancel()
    }

    private func removePendingLayers() {
        for slot in pendingLayers.values {
            slot.layer.removeFromSuperlayer()
        }
        pendingLayers.removeAll(keepingCapacity: true)
    }

    private func makeSublayer(scale: CGFloat) -> CALayer {
        let layer = CALayer()
        layer.contentsGravity = .resize
        layer.contentsScale = scale
        contentLayer.addSublayer(layer)
        return layer
    }

    /// Geometry and effect only; the image is bound separately so the bind
    /// count can be spread across presents.
    private func updateSublayer(_ layer: CALayer, with placed: LayerPlacement, scale: CGFloat) {
        if layer.contentsScale != scale {
            layer.contentsScale = scale
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

    private func applyImage(
        _ frame: PresentedFrame,
        viewSize: CGSize,
        preview: Bool
    ) {
        let scale: ContentScale = frame.viewport.scale
        lastDeferred = 0
        discardPendingGeneration()
        lastBoundGeneration = frame.content.source.generation
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
            contentLayer.contentsScale = scale.display
        }
        guard let image = frame.content.image else {
            lastImage = nil
            contentLayer.contents = nil
            return
        }

        if image !== lastImage {
            lastImage = image
            contentLayer.contents = image
            contentLayer.contentsScale = scale.display
        }
        presentationState.didShow(layoutSize: frame.displayedLayoutSize, viewSize: viewSize)

        contentLayer.transform = CATransform3DIdentity
        contentLayer.contentsGravity = preview ? .resize : .topLeft
        let imageHeight = CGFloat(image.height) / scale.display
        contentLayer.frame = CGRect(
            x: 0,
            y: 0,
            width: viewSize.width,
            height: preview ? viewSize.height : imageHeight
        )
    }

    private func placeContentLayer(originY: CGFloat, scale: CGFloat, viewSize: CGSize) {
        contentLayer.anchorPoint = CGPoint(x: 0, y: 0)
        contentLayer.transform = CATransform3DMakeScale(scale, scale, 1)
        contentLayer.position = CGPoint(x: 0, y: originY)
        contentLayer.bounds = CGRect(
            x: 0,
            y: 0,
            width: viewSize.width / scale,
            height: viewSize.height / scale
        )
    }
}
