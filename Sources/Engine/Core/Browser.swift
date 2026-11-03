import Combine
import CoreGraphics
import Foundation

@MainActor
public class Browser: ObservableObject {
    @Published public var tabs: [BrowserTab] = []
    @Published public private(set) var activeTab: BrowserTab?
    public var windowSize: CGSize = CGSize(width: WIDTH, height: HEIGHT)
    public var topInset: CGFloat = 0
    public var displayScale: CGFloat = 2.0
    private var animationTimer: Timer?
    private var nextFrameTime: Date = .distantPast
    private let FRAME_BUDGET: TimeInterval = 1.0 / 60.0
    private var frameStartTime: Date = .distantPast
    private var recentFrameTimes: [TimeInterval] = []
    private let frameHistorySize: Int = 5
    private var estimatedFrameTime: TimeInterval = 1.0 / 60.0
    private let accessibilityThread: AccessibilityThread = AccessibilityThread()
    public var accessibilityIsOn: Bool = false
    private var hasSpokenDocument: Bool = false
    private var spokenAlerts: [AccessibilityNode] = []
    private var lastFocus: NodeID? = nil
    private var pendingHover: CGPoint? = nil
    private var hoveredA11yNode: AccessibilityNode? = nil
    private var needsSpeakHoveredNode: Bool = false
    private var accessibilityFocusNode: AccessibilityNode? = nil
    private var liveRegionTexts: [NodeID: String] = [:]

    private var activePresentation: TabPresentation {
        get { activeTab?.presentation ?? TabPresentation.empty }
        set { activeTab?.presentation = newValue }
    }
    private var presentRevision: Int = 0

    public var drawList: [DisplayOp] { activePresentation.render.drawList }
    public var activeTabScroll: CGFloat { activePresentation.scroll.scroll }
    public var pageZoom: CGFloat { activeTab?.pageZoom ?? 1.0 }
    public var contentImage: CGImage? { activePresentation.render.content.image }
    public var usesSublayers: Bool { activePresentation.render.content.usesSublayers }

    func beginFrame() {
        currentFrameID += 1
        measure.setFrame(currentFrameID)
    }

    public var presentedFrame: PresentedFrame {
        return presentedFrame(frameID: currentFrameID)
    }

    private func presentedFrame(frameID: Int) -> PresentedFrame {
        PresentedFrame(
            revision: presentRevision,
            frameID: frameID,
            content: activePresentation.render.content,
            viewport: PresentedViewport(
                contentOffset: topInset - activePresentation.scroll.scroll * pageZoom,
                scale: ContentScale(display: displayScale, page: pageZoom),
                canvasColor: canvasColor,
                scrollbar: activeSidebar
            )
        )
    }

    public var onPresent: ((PresentedFrame) -> Void)?
    private var lastTileScroll: CGFloat = .nan

    public var canvasColor: CGColor {
        let name: String = activePresentation.preferences.usesForcedColors ? ForcedColor.canvas : (activePresentation.preferences.prefersDark ? "black" : "white")
        return BrowserColor(cssName: name).cgColor
    }

    public var activeSidebar: (frame: CGRect, color: CGColor)? {
        let contentHeight: CGFloat = windowSize.height - topInset
        guard contentHeight > 0,
            let bar = scrollbarBarRect(
                ScrollbarGeometry(
                    docHeight: activePresentation.scroll.maxScroll * pageZoom + contentHeight,
                    contentHeight: contentHeight,
                    contentWidth: windowSize.width,
                    scroll: activePresentation.scroll.scroll * pageZoom
                ),
                forcedColors: activePresentation.preferences.usesForcedColors,
                topInset: topInset
            ),
            case .rrect(let rect, _, let color) = bar
        else { return nil }
        return (rect.cgRect, color.cgColor)
    }

    private var needsComposite: Bool = false
    private var needsRaster: Bool = false
    private var needsDraw: Bool = false
    private var needsAnimationFrame: Bool = true
    private var compositeInFlight: Bool = false
    private var currentFrameID: Int = 0
    private var needsTileContinuation: Bool = false
    private var tileContinuationPasses: UInt = 0

    @Published public var prefersDark: Bool = false
    @Published public private(set) var commitedPrefersDark: Bool = false

    @Published public var forcedColors: Bool = false
    @Published public private(set) var commitedForcedColors: Bool = false

    public let measure: MeasureTime

    public var forceFullLayout: Bool = false

    let networkTaskRunner: NetworkTaskRunner = NetworkTaskRunner()
    let rasterScheduler: RasterScheduler = RasterScheduler()

    private struct LayerRasterKey: Hashable {
        let left: CGFloat
        let top: CGFloat
        let right: CGFloat
        let bottom: CGFloat
        let content: [Int]
    }

    public init(tracePath: String? = nil) {
        measure = MeasureTime(path: tracePath)
        rasterScheduler.measure = measure
        measure.noteThread("main")
    }

    public func newTab(_ url: WebURL) {
        let tab: BrowserTab = BrowserTab(
            tabHeight: windowSize.height - topInset,
            tabWidth: windowSize.width
        )
        tab.browser = self
        tab.networkTaskRunner = networkTaskRunner
        tab.prefersDark = prefersDark
        tab.forcedColors = forcedColors
        tab.load(url)
        activeTab = tab
        tabs.append(tab)
        dispatchPresent(frameID: currentFrameID)
        startAnimationTimer()
    }

    public func resize(to size: CGSize) {
        windowSize = size
        for tab in tabs {
            tab.resize(width: size.width, height: size.height - topInset)
        }
    }

    public func startAnimationTimer() {
        guard animationTimer == nil else { return }
        nextFrameTime = Date()
        scheduleNextFrame()
    }

    private func scheduleNextFrame() {
        let now: Date = Date()

        nextFrameTime = max(nextFrameTime + FRAME_BUDGET, now)
        let delay: TimeInterval = nextFrameTime.timeIntervalSinceNow
        let timer: Timer = Timer(timeInterval: max(0, delay), repeats: false) {
            [weak self] _ in
            Task { @MainActor in
                self?.animationTick()
                self?.scheduleNextFrame()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        animationTimer = timer
    }

    public func stopAnimationTimer() {
        pauseAnimationTimer()
        measure.close()
    }

    public func pauseAnimationTimer() {
        animationTimer?.invalidate()
        animationTimer = nil
    }

    private func animationTick() {
        guard needsAnimationFrame else {
            return
        }
        needsAnimationFrame = false
        frameStartTime = Date()
        activeTab?.runAnimationFrame()
    }

    public func advanceFrame() {
        animationTick()
    }

    public var isRenderIdle: Bool {
        return !compositeInFlight && !needsComposite && !needsRaster && !needsDraw && !needsTileContinuation
    }

    func commit(tab: BrowserTab, data: FrameCommit) {
        guard tab === activeTab else { return }
        let paintChanged: Bool = data.display.paintRevision != activePresentation.display.paintRevision
        activePresentation.display.displayList = data.display.displayList
        activePresentation.scroll.scroll = data.scrollState.scroll
        activePresentation.scroll.interestTop = data.scrollState.interestTop
        activePresentation.scroll.interestBottom = data.scrollState.interestBottom
        activePresentation.scroll.maxScroll = data.scrollState.maxScroll
        activePresentation.preferences.prefersDark = data.preferences.prefersDark
        activePresentation.preferences.usesForcedColors = data.preferences.usesForcedColors
        activePresentation.display.paintRevision = data.display.paintRevision
        activePresentation.display.compositedUpdates = data.display.compositedUpdates ?? [:]

        if let updates = data.display.compositedUpdates, !updates.isEmpty {
            activePresentation.display.effectRevision += 1
        }

        if paintChanged {
            objectWillChange.send()
        }

        if let updates = data.display.compositedUpdates, !updates.isEmpty,
            activePresentation.render.content.usesSublayers,
            !needsComposite, !needsRaster, !needsDraw, !compositeInFlight,
            Browser.updatesAreCA(updates),
            applyEffectFastPath(updates)
        {
            return
        }

        if data.display.compositedUpdates == nil {
            setNeedsComposite()
        } else {
            setNeedsDrawOnly()
        }

        scheduleRasterAndDraw()
    }

    private func applyEffectFastPath(_ updates: [NodeID: EffectUpdate]) -> Bool {
        let layers: [CompositedLayer] = activePresentation.render.layers
        let effectStrategies: [LayerEffectStrategy] = layers.map({ Browser.layerEffectStrategy($0, updates: updates) })
        let keys: Set<NodeID> = Set(effectStrategies.compactMap({ $0.effect?.key }))
        guard updates.keys.allSatisfy({ keys.contains($0) }) else { return false }
        for (index, info) in effectStrategies.enumerated() where info.kind == .ca {
            if layers[index].effectImage == nil { return false }
        }
        activePresentation.render.content.placements = Browser.layerPlacements(layers, effectStrategies: effectStrategies)
        dispatchPresent(frameID: currentFrameID)
        return true
    }

    private func dispatchPresent(frameID: Int) {
        measure.start("present.main", category: .present, frame: frameID)
        presentRevision += 1
        onPresent?(presentedFrame(frameID: frameID))
        measure.stop("present.main")
    }

    private func resolvePendingHover() {
        guard let pending = pendingHover else { return }
        let adjustedY: CGFloat = pending.y / pageZoom + activeTabScroll
        if let hit = activeTab?.accessibilityTree?.hitTest(x: pending.x / pageZoom, y: adjustedY) {
            if hoveredA11yNode == nil || hit.node.id != hoveredA11yNode!.node.id {
                needsSpeakHoveredNode = true
            }
            hoveredA11yNode = hit
        }
        pendingHover = nil
    }

    private func scheduleRasterAndDraw() {
        guard needsComposite || needsRaster || needsDraw else { return }

        resolvePendingHover()

        if compositeInFlight {
            return
        }

        let wantsComposite: Bool = needsComposite

        let scrollState: ScrollState = ScrollState(
            scroll: activePresentation.scroll.scroll,
            interestTop: activePresentation.scroll.interestTop,
            interestBottom: activePresentation.scroll.interestBottom,
            maxScroll: activePresentation.scroll.maxScroll
        )

        let inputs: RasterInput = RasterInput(
            scene: RasterScene(
                displayList: activePresentation.display.displayList,
                compositedUpdates: activePresentation.display.compositedUpdates,
                previousLayers: activePresentation.render.layers,
            ),
            settings: RasterSettings(
                viewport: Viewport(windowSize: windowSize, topInset: topInset, scale: ContentScale(display: displayScale, page: pageZoom)),
                preferences: ColorPreferences(prefersDark: activePresentation.preferences.prefersDark, usesForcedColors: activePresentation.preferences.usesForcedColors),
                flags: RasterInvalidation(needsComposite: wantsComposite, needsDraw: needsDraw),
                accessibility: AccessibilityBounds(hoveredBounds: hoveredA11yNode?.absoluteBounds(), readBounds: accessibilityFocusNode?.absoluteBounds())
            ),
            scrollState: scrollState
        )

        let signature: FrameSignature = FrameSignature(
            viewport: FrameViewport(
                scroll: activePresentation.scroll.scroll,
                size: windowSize,
                scale: ContentScale(display: displayScale, page: pageZoom)
            ),
            revisions: FrameRevisions(
                paint: activePresentation.display.paintRevision,
                effects: activePresentation.display.effectRevision
            ),
            preferences: ColorPreferences(prefersDark: activePresentation.preferences.prefersDark, usesForcedColors: activePresentation.preferences.usesForcedColors),
            accessibility: AccessibilityBounds(hoveredBounds: hoveredA11yNode?.absoluteBounds(), readBounds: accessibilityFocusNode?.absoluteBounds())
        )
        if signature == activePresentation.render.signature && !needsTileContinuation {
            needsDraw = false
            frameStartTime = .distantPast
            return
        }

        let frameID: Int = currentFrameID
        let compositeStart: UInt64 = measure.timestamp()

        if !needsTileContinuation { tileContinuationPasses = 0 }
        needsTileContinuation = false

        compositeInFlight = true
        if wantsComposite {
            needsComposite = false
            needsRaster = false
        }
        needsDraw = false

        let frameStart: Date = frameStartTime
        frameStartTime = .distantPast
        let owner: BrowserTab? = activeTab

        let measure: MeasureTime = self.measure
        let installWait: RasterInstallWait = RasterInstallWait()
        rasterScheduler.schedule(
            RasterScheduler.Job(
                trace: TraceContext(frame: frameID, measure: measure),
                plan: { (store: TileStore) -> RasterPlan in
                    let planStart: UInt64 = measure.timestamp()
                    measure.interval(
                        "raster.queueWait",
                        MeasureTime.SpanInterval(start: compositeStart, end: planStart, category: .raster, frame: frameID)
                    )
                    measure.start("raster.plan", category: .raster, frame: frameID)

                    measure.start("raster.composite", category: .raster, frame: frameID)
                    let layers: [CompositedLayer] =
                        inputs.settings.flags.needsComposite
                        ? Browser.computeComposite(inputs, measure: measure, frame: frameID)
                        : inputs.scene.previousLayers
                    measure.stop("raster.composite")

                    let scale: ContentScale = inputs.settings.viewport.scale
                    let tabHeight: CGFloat = inputs.settings.viewport.windowSize.height - inputs.settings.viewport.topInset
                    let prefetch: CGFloat = 2 * CompositedLayer.tileSize
                    let viewportHeight: CGFloat = tabHeight / scale.page
                    let viewportWidth: CGFloat = inputs.settings.viewport.windowSize.width
                    let region: RasterRegion = RasterRegion(
                        hint: Rect(
                            left: 0,
                            top: inputs.scrollState.scroll - prefetch,
                            right: viewportWidth,
                            bottom: inputs.scrollState.scroll + viewportHeight + prefetch
                        ),
                        visible: Rect(
                            left: 0,
                            top: inputs.scrollState.scroll,
                            right: viewportWidth,
                            bottom: inputs.scrollState.scroll + viewportHeight
                        )
                    )

                    let effectStrategies: [LayerEffectStrategy] = layers.map {
                        Browser.layerEffectStrategy($0, updates: inputs.scene.compositedUpdates)
                    }
                    let usesSublayers: Bool = !effectStrategies.contains {
                        $0.kind == .blendFallback || $0.kind == .scrollFallback
                    }

                    measure.start("raster.plan.tiles", category: .raster, frame: frameID)
                    var strips: [TileStrip] = []
                    var deferred: Bool = false
                    if usesSublayers {
                        store.beginComposite(
                            viewportTop: inputs.scrollState.scroll,
                            viewportBottom: inputs.scrollState.scroll + viewportHeight
                        )
                        let budget: RasterBudget = RasterBudget(CompositedLayer.rasterCapPerComposite)

                        for (index, layer) in layers.enumerated() where effectStrategies[index].kind == .flat {
                            strips.append(contentsOf: layer.rasterIfNeeded(
                                scale: scale.effective,
                                store: store,
                                region: region,
                                budget: budget
                            ))
                            layer.pruneTiles(
                                keepTop: inputs.scrollState.scroll - 4 * CompositedLayer.tileSize,
                                keepBottom: inputs.scrollState.scroll + viewportHeight + 4 * CompositedLayer.tileSize
                            )
                        }

                        deferred = budget.remaining == 0
                    }

                    measure.stop("raster.plan.tiles")
                    measure.stop("raster.plan")

                    return RasterPlan(
                        composition: RasterComposition(
                            inputs: inputs,
                            layers: layers,
                            effectStrategies: effectStrategies,
                            usesSublayers: usesSublayers,
                        ),
                        batch: TileBatch(
                            strips: strips,
                            tabHeight: tabHeight,
                            deferred: deferred
                        )
                    )
                },
                install: { (store: TileStore, plan: RasterPlan, images: [CGImage?]) -> RasterOutput in
                    let layers: [CompositedLayer] = plan.composition.layers
                    let effectStrategies: [LayerEffectStrategy] = plan.composition.effectStrategies
                    let inputs: RasterInput = plan.composition.inputs

                    measure.start("raster.install", category: .raster, frame: frameID)
                    if plan.composition.usesSublayers {
                        measure.start("raster.install.tiles", category: .raster, frame: frameID)
                        for (i, strip) in plan.batch.strips.enumerated() {
                            guard let stripImage = images[i] else { continue }
                            for key in strip.tiles {
                                guard let tile = stripImage.cropping(
                                    to: TileStrip.sliceRect(
                                        for: key,
                                        in: strip.bounds,
                                        scale: inputs.settings.viewport.scale.effective
                                    )
                                ) else { continue }
                                strip.layer.tiles[key.index] = tile
                                store.insert(tile, key: key)
                            }
                        }
                        measure.stop("raster.install.tiles")
                        measure.counter("tiles", [
                            "scroll": Int(inputs.scrollState.scroll),
                            "hits": store.hits,
                            "misses": store.misses,
                            "missNew": store.missNew,
                            "missStale": store.missStale,
                            "missEvicted": store.missEvicted,
                            "entries": store.entryCount,
                            "pixels": store.retainedPixels,
                            "layers": layers.count,
                            "flat": effectStrategies.filter({ $0.kind == .flat }).count
                        ], frame: frameID)
                        if plan.batch.deferred {
                            store.markDeferred()
                        }
                        measure.start("raster.effect", category: .raster, frame: frameID)
                        for (index, layer) in layers.enumerated() where effectStrategies[index].kind == .ca {
                            Browser.updateEffectImage(
                                layer,
                                scale: inputs.settings.viewport.scale.effective,
                                blur: effectStrategies[index].blur
                            )
                        }
                        measure.stop("raster.effect")
                    }

                    let drawList: [DisplayOp] = Browser.computePaintDrawList(layers: layers, inputs: inputs)
                    let regionTop: CGFloat = inputs.scrollState.scroll
                    var contentImage: CGImage? = nil

                    if !plan.composition.usesSublayers && inputs.settings.flags.needsDraw {
                        let regionHeight: CGFloat = inputs.settings.viewport.topInset + plan.batch.tabHeight
                        measure.start("raster.bitmap")
                        contentImage = inputs.settings.flags.needsDraw
                            ? CGRenderer.renderBitmap(
                                size: CGSize(
                                    width: inputs.settings.viewport.windowSize.width,
                                    height: regionHeight
                                ),
                                scale: inputs.settings.viewport.scale.display,
                                backgroundColor: inputs.settings.preferences.usesForcedColors
                                    ? BrowserColor(cssName: ForcedColor.canvas)
                                    : (inputs.settings.preferences.prefersDark ? BrowserColor(cssName: "black") : BrowserColor(cssName: "white"))
                            ) { r in
                                r.saveState()
                                ContentTransform(
                                    pageZoom: inputs.settings.viewport.scale.page,
                                    scroll: regionTop,
                                    topInset: inputs.settings.viewport.topInset
                                ).apply(to: r)
                                renderDisplayList(drawList, renderer: r)
                                r.restoreState()
                            }
                            : nil
                        measure.stop("raster.bitmap")
                    }
                    measure.stop("raster.install")
                    installWait.noteInstallEnd(measure.timestamp())

                    return RasterOutput(
                        compositedLayers: inputs.settings.flags.needsComposite ? layers : nil,
                        drawList: drawList,
                        content: RenderedContent(
                            placements: plan.composition.usesSublayers ? Browser.layerPlacements(layers, effectStrategies: effectStrategies) : [],
                            image: contentImage,
                            regionTop: regionTop,
                            usesSublayers: plan.composition.usesSublayers
                        ),
                        needsMoreTiles: store.needsMoreTiles
                    )
                },
                then: { [weak self, weak owner] (output: RasterOutput) in
                    guard let self = self else { return }
                    let mainHopStart: UInt64 = self.measure.timestamp()
                    if let wait: (start: UInt64, end: UInt64) = installWait.takeWait(endedAt: mainHopStart) {
                        self.measure.interval("raster.installWait", MeasureTime.SpanInterval(start: wait.start, end: wait.end, category: .raster, frame: frameID))
                    }
                    if let owner {
                        var presentation: TabPresentation = owner.presentation
                        presentation.render.layers = output.compositedLayers ?? presentation.render.layers
                        if let drawList: [DisplayOp] = output.drawList {
                            presentation.render.drawList = drawList
                        }
                        if inputs.settings.flags.needsDraw || output.content.usesSublayers {
                            presentation.render.content = output.content
                        }
                        presentation.render.signature = signature
                        owner.presentation = presentation

                        if owner === self.activeTab {
                            if inputs.settings.flags.needsDraw || output.content.usesSublayers {
                                self.dispatchPresent(frameID: frameID)
                            }
                            if output.content.usesSublayers, output.needsMoreTiles, self.tileContinuationPasses < 8 {
                                self.tileContinuationPasses += 1
                                self.needsTileContinuation = true
                                self.needsRaster = true
                            }
                            if self.commitedPrefersDark != inputs.settings.preferences.prefersDark {
                                self.commitedPrefersDark = inputs.settings.preferences.prefersDark
                            }
                            if self.commitedForcedColors != inputs.settings.preferences.usesForcedColors {
                                self.commitedForcedColors = inputs.settings.preferences.usesForcedColors
                            }
                        }
                    }

                    self.updateAccessibility()
                    self.measure.interval(
                        "composite_raster_and_draw",
                        MeasureTime.SpanInterval(
                            start: compositeStart,
                            end: self.measure.timestamp(),
                            category: .frame,
                            frame: frameID
                        ),
                        args: ["owner": owner == nil ? 0 : 1]
                    )
                    self.compositeInFlight = false
                    if frameStart != .distantPast {
                        let elapsed: TimeInterval = Date().timeIntervalSince(frameStart)
                        self.recentFrameTimes.append(elapsed)
                        if self.recentFrameTimes.count > self.frameHistorySize {
                            self.recentFrameTimes.removeFirst()
                        }
                        let avg: Double = self.recentFrameTimes.reduce(0, +) / Double(self.recentFrameTimes.count)
                        self.estimatedFrameTime = max(avg, self.FRAME_BUDGET)
                    }
                    if self.needsComposite || self.needsRaster || self.needsDraw {
                        self.scheduleRasterAndDraw()
                    }
                }
            )
        )
    }

    nonisolated static func computeComposite(
        _ inputs: RasterInput,
        measure: MeasureTime,
        frame: Int
    ) -> [CompositedLayer] {
        measure.start("raster.composite.scan", category: .raster, frame: frame)
        var compositedLayers: [CompositedLayer] = []
        var scopes: [EffectScope] = []
        var ordinals: [EffectScopeID?: Int] = [:]
        var animatedTransforms: Int = 0
        var assumeOverlap: Bool = false
        var commandIndex: Int = 0

        for op in inputs.scene.displayList {
            switch op {
            case .beginEffect(let scope):
                scopes.append(scope)
                if case .transform = scope.kind, scope.placement.animatedTransform {
                    animatedTransforms += 1
                }
            case .endEffect:
                let scope: EffectScope = scopes.removeLast()
                if case .transform = scope.kind, scope.placement.animatedTransform {
                    animatedTransforms -= 1
                }
            default:
                let scopeID: EffectScopeID? = scopes.last?.id
                if animatedTransforms > 0 { assumeOverlap = true }
                var merged: Bool = false
                for layer in compositedLayers.reversed() {
                    if layer.id.effect == scopeID {
                        layer.add(op)
                        merged = true
                        break
                    } else if assumeOverlap {
                        break
                    }
                }
                if !merged {
                    let ordinal: Int = ordinals[scopeID, default: 0]
                    ordinals[scopeID] = ordinal + 1
                    let layer: CompositedLayer = CompositedLayer(
                        displayItem: op,
                        firstCommandIndex: commandIndex,
                        id: LayerID(effect: scopeID, ordinal: ordinal)
                    )
                    layer.ancestorChain = Array(scopes.reversed())
                    compositedLayers.append(layer)
                }
                commandIndex += 1
            }
        }

        reuseRasterization(from: inputs.scene.previousLayers, into: compositedLayers)
        measure.stop("raster.composite.scan")
        return compositedLayers
    }

    nonisolated private static func reuseRasterization(
        from previous: [CompositedLayer],
        into layers: [CompositedLayer]
    ) {
        guard !previous.isEmpty else { return }
        var pool: [LayerID: [CompositedLayer]] = [:]
        for layer in previous {
            pool[layer.id, default: []].append(layer)
        }
        for layer in layers {
            guard var candidates = pool[layer.id], let source = candidates.popLast() else { continue }
            pool[layer.id] = candidates
            layer.effectImage = source.effectImage
            layer.effectImageKey = source.effectImageKey
        }
    }

    nonisolated static func layerEffectStrategy(
        _ layer: CompositedLayer,
        updates: [NodeID: EffectUpdate]
    ) -> LayerEffectStrategy {
        var kind: LayerEffectStrategy.Kind = LayerEffectStrategy.Kind.flat
        var opacity: Double = 1
        var translation: CGPoint = CGPoint.zero
        var blur: CGFloat = 0
        var key: NodeID?
        var blendMode: BrowserBlendMode?
        var clipRect: Rect?
        for scope in layer.ancestorChain {
            let update: EffectUpdate? = scope.placement.node.flatMap { updates[$0] }
            let animated: Bool = update?.isAnimatedTransform ?? scope.placement.animatedTransform
            switch scope.kind {
            case .scroll:
                kind = max(kind, .scrollFallback)
            case .blend(let scopeOpacity, let scopeMode):
                let updatedOpacity: Double = update?.style.opacity ?? scopeOpacity
                let updatedMode: BrowserBlendMode? = update.map({ $0.style.blendMode }) ?? scopeMode
                opacity *= updatedOpacity
                if let updatedMode, updatedMode != .normal {
                    if updatedMode.compositingFilterName != nil {
                        kind = max(kind, .ca)
                        if blendMode == nil { blendMode = updatedMode }
                    } else {
                        kind = max(kind, .blendFallback)
                    }
                } else if updatedOpacity < 1 {
                    kind = max(kind, .ca)
                }
                if key == nil { key = scope.placement.node }
            case .transform(let scopeTranslation):
                let updatedTranslation: CGPoint? = update.map({ $0.style.translation }) ?? scopeTranslation
                if let updatedTranslation {
                    translation.x += updatedTranslation.x
                    translation.y += updatedTranslation.y
                    kind = max(kind, .ca)
                }
                if animated { kind = max(kind, .ca) }
                if key == nil { key = scope.placement.node }
            case .blur(let scopeRadius):
                let updatedRadius: CGFloat = update?.style.blurRadius ?? scopeRadius
                if updatedRadius > 0 {
                    blur = max(blur, updatedRadius)
                    kind = max(kind, .ca)
                    if key == nil { key = scope.placement.node }
                }
            case .clip(let shape):
                let local: Rect = Rect(
                    left: shape.rect.left - translation.x,
                    top: shape.rect.top - translation.y,
                    right: shape.rect.right - translation.x,
                    bottom: shape.rect.bottom - translation.y
                )
                clipRect = clipRect.map({ $0.intersect(local) }) ?? local
            }
        }
        let effect: LayerEffect? = kind == .ca
            ? LayerEffect(
                key: key,
                opacity: opacity,
                translation: translation,
                blendMode: blendMode,
                clipRect: clipRect
            )
            : nil
        return LayerEffectStrategy(kind: kind, effect: effect, blur: blur)
    }

    nonisolated static func updatesAreCA(_ updates: [NodeID: EffectUpdate]) -> Bool {
        updates.values.allSatisfy({ update in
            update.style.blurRadius == 0
                && (update.style.blendMode == nil
                    || update.style.blendMode == .normal
                    || update.style.blendMode?.compositingFilterName != nil)
        })
    }

    nonisolated static func computePaintDrawList(
        layers: [CompositedLayer],
        inputs: RasterInput
    ) -> [DisplayOp] {
        var layerByIndex: [Int: CompositedLayer] = [:]
        for layer in layers where layer.firstCommandIndex >= 0 {
            layerByIndex[layer.firstCommandIndex] = layer
        }

        let scale: ContentScale = inputs.settings.viewport.scale
        let viewportHeight: CGFloat = (inputs.settings.viewport.windowSize.height - inputs.settings.viewport.topInset) / scale.page
        let visibleTop: CGFloat = inputs.scrollState.scroll - 2 * CompositedLayer.tileSize
        let visibleBottom: CGFloat = inputs.scrollState.scroll + viewportHeight + 2 * CompositedLayer.tileSize

        var commandIndex: Int = 0
        var drawList: [DisplayOp] = []
        drawList.reserveCapacity(inputs.scene.displayList.count)
        for op in inputs.scene.displayList {
            switch op {
            case .beginEffect(let scope):
                drawList.append(
                    .beginEffect(Browser.updatedScope(scope, updates: inputs.scene.compositedUpdates))
                )
            case .endEffect:
                drawList.append(op)
            default:
                if let layer: CompositedLayer = layerByIndex[commandIndex] {
                    drawList.append(
                        .compositedLayer(
                            layer: layer,
                            rect: layer.absoluteBounds(),
                            visibleTop: visibleTop,
                            visibleBottom: visibleBottom
                        )
                    )
                }
                commandIndex += 1
            }
        }

        if let bounds = inputs.settings.accessibility.hoveredBounds {
            drawList.append(.outline(rect: bounds, color: BrowserColor(cssName: inputs.settings.preferences.usesForcedColors ? ForcedColor.highlight : "white"), width: 4))
            drawList.append(.outline(rect: bounds, color: BrowserColor(cssName: "black"), width: 2))
        }

        if let bounds = inputs.settings.accessibility.readBounds {
            drawList.append(.outline(rect: bounds, color: BrowserColor(cssName: "gold"), width: 4))
            drawList.append(.outline(rect: bounds, color: BrowserColor(cssName: "black"), width: 2))
        }

        return drawList
    }

    nonisolated private static func updatedScope(
        _ scope: EffectScope,
        updates: [NodeID: EffectUpdate]
    ) -> EffectScope {
        guard let node = scope.placement.node, let update = updates[node] else { return scope }
        let kind: EffectKind
        switch scope.kind {
        case .blend:
            kind = .blend(opacity: update.style.opacity, mode: update.style.blendMode)
        case .transform:
            kind = .transform(update.style.translation)
        case .blur:
            kind = .blur(radius: update.style.blurRadius)
        case .clip, .scroll:
            kind = scope.kind
        }
        return EffectScope(
            id: scope.id,
            kind: kind,
            placement: EffectPlacement(
                rect: scope.placement.rect,
                node: scope.placement.node,
                animatedTransform: update.isAnimatedTransform
            )
        )
    }

    nonisolated static func layerPlacements(_ layers: [CompositedLayer], effectStrategies: [LayerEffectStrategy]) -> [LayerPlacement] {
        let t: CGFloat = CompositedLayer.tileSize
        var placements: [LayerPlacement] = []
        for (z, layer) in layers.enumerated() {
            switch effectStrategies[z].kind {
                case .flat:
                    for index in layer.orderedTileIndices {
                        guard let image: CGImage = layer.tiles[index] else { continue }
                        placements.append(
                            LayerPlacement(
                                key: .tile(zIndex: z, col: index.col, row: index.row),
                                image: image,
                                frame: CGRect(
                                    x: CGFloat(index.col) * t,
                                    y: CGFloat(index.row) * t,
                                    width: t,
                                    height: t
                                ),
                            )
                        )
                    }
                case .ca:
                    guard let image = layer.effectImage else { break }
                    let bounds: Rect = layer.compositedBounds()
                    placements.append(
                        LayerPlacement(
                            key: .composited(zIndex: z),
                            image: image,
                            frame: CGRect(x: bounds.left, y: bounds.top, width: bounds.right - bounds.left, height: bounds.bottom - bounds.top),
                            effect: effectStrategies[z].effect
                        )
                    )
                case .blendFallback, .scrollFallback:
                    break
            }
        }
        return placements
    }

    nonisolated static func rasterEffectBitmap(_ layer: CompositedLayer, scale: CGFloat, blur: CGFloat) -> CGImage? {
        let bounds: Rect = layer.compositedBounds()
        let size: CGSize = CGSize(width: bounds.right - bounds.left, height: bounds.bottom - bounds.top)
        guard size.width > 0, size.height > 0 else { return nil }
        return CGRenderer.renderBitmap(size: size, scale: scale, { renderer in
            if blur > 0 {
                renderer.drawLayer(LayerOptions(blur: blur), content: { inner in
                    layer.raster(renderer: inner)
                })
            } else {
                layer.raster(renderer: renderer)
            }
        })
    }

    nonisolated static func updateEffectImage(_ layer: CompositedLayer, scale: CGFloat, blur: CGFloat) {
        let key: CompositedLayer.EffectImageKey = CompositedLayer.EffectImageKey(scale: scale, blur: blur, bounds: layer.compositedBounds())
        guard layer.effectImageKey != key else { return }
        layer.effectImage = Browser.rasterEffectBitmap(layer, scale: scale, blur: blur)
        layer.effectImageKey = key
    }

    func setNeedsComposite() {
        lastTileScroll = .nan
        needsComposite = true
        needsRaster = true
        needsDraw = true
    }

    func setNeedsDrawOnly() {
        needsDraw = true
    }

    func navigationStateChanged() {
        objectWillChange.send()
    }

    func setNeedsAnimationFrame(_ tab: BrowserTab) {
        if tab === activeTab {
            needsAnimationFrame = true
        }
    }

    public func applyScroll(_ scroll: CGFloat) {
        activePresentation.scroll.scroll = scroll

        let didRepaint: Bool = activeTab?.rootFrame.repaintForScroll() ?? false

        if activePresentation.render.content.usesSublayers {
            if didRepaint {
                setNeedsComposite()
            }
            dispatchPresent(frameID: currentFrameID)
            let step: CGFloat = CompositedLayer.tileSize
            if lastTileScroll.isNaN || abs(scroll - lastTileScroll) >= step {
                lastTileScroll = scroll
                setNeedsDrawOnly()
                scheduleRasterAndDraw()
            }
        } else {
            setNeedsDrawOnly()
            scheduleRasterAndDraw()
        }
    }

    public func applyScrollAndUpdateInterest(scroll: CGFloat, interestTop: CGFloat, interestBottom: CGFloat) {
        activePresentation.scroll.scroll = scroll
        activePresentation.scroll.interestTop = interestTop
        activePresentation.scroll.interestBottom = interestBottom
        let didRepaint: Bool = activeTab?.rootFrame.repaintForScroll() ?? false
        if didRepaint && activePresentation.render.content.usesSublayers {
            setNeedsComposite()
        }
        setNeedsDrawOnly()
        scheduleRasterAndDraw()
    }

    public func togglePrefersDark() {
        prefersDark = !prefersDark
        activeTab?.prefersDark = prefersDark
    }

    public func toggleForcedColors() {
        forcedColors = !forcedColors
        activeTab?.forcedColors = forcedColors
    }

    // MARK: - Zoom

    public func incrementZoom(_ increment: Bool) {
        activeTab?.zoomBy(increment)
    }

    public func resetZoom() {
        activeTab?.resetZoom()
    }

    public func setZoom(_ newZoom: CGFloat) {
        activeTab?.setZoom(newZoom)
    }

    public func cycleTabs() {
        guard !tabs.isEmpty, let current = activeTab,
            let idx = tabs.firstIndex(where: { $0 === current })
        else {
            return
        }
        let nextIdx: Int = (idx + 1) % tabs.count
        selectTab(tabs[nextIdx])
    }

    public func selectTab(_ tab: BrowserTab) {
        guard tab !== activeTab else { return }
        activeTab?.clearHover()
        activeTab = tab
        hoveredA11yNode = nil
        hasSpokenDocument = false
        spokenAlerts = []
        liveRegionTexts = [:]
        lastFocus = nil
        needsComposite = false
        needsRaster = false
        needsDraw = false
        if activePresentation.render.content.image == nil && !activePresentation.render.content.usesSublayers {
            setNeedsComposite()
        } else if let sig = activePresentation.render.signature,
            sig.viewport.size != windowSize || sig.viewport.scale.display != displayScale || sig.viewport.scale.page != pageZoom {
            setNeedsComposite()
        }
        needsAnimationFrame = true
        activeTab?.runAnimationFrame()
        dispatchPresent(frameID: currentFrameID)
    }

    private func speakText(_ text: String) {
        accessibilityThread.speak(text)
    }

    private func speakDocument() {
        guard let tree = activeTab?.accessibilityTree else { return }
        var text: String = "Here the document contents: "
        for node in treeToList(tree) {
            if !node.text.isEmpty { text += "\n" + node.text }
        }
        accessibilityThread.stopSpeaking()
        speakText(text)
    }

    public func advanceAccessibility() {
        guard accessibilityIsOn, let tree = activeTab?.accessibilityTree else { return }
        let readable: [AccessibilityNode] = treeToList(tree).filter({ !$0.text.isEmpty })
        guard !readable.isEmpty else { return }

        var nextIndex: Int = 0
        if let current = accessibilityFocusNode, let idx = readable.firstIndex(where: { $0.node.id == current.node.id }) {
            nextIndex = idx + 1
        }

        if nextIndex < readable.count {
            let next: AccessibilityNode = readable[nextIndex]
            accessibilityFocusNode = next
            speakNode(next, "")
        } else {
            accessibilityFocusNode = nil
            speakText("End of document")
        }

        setNeedsDrawOnly()
        scheduleRasterAndDraw()
    }

    private func speakNode(_ node: AccessibilityNode, _ prefix: String) {
        let text: String = prefix + node.text
        if !text.isEmpty { speakText(text) }
    }

    func updateAccessibility() {
        guard accessibilityIsOn, let tree = activeTab?.accessibilityTree else { return }

        if !hasSpokenDocument {
            speakDocument()
            hasSpokenDocument = true
        }

        let allNodes: [AccessibilityNode] = treeToList(tree)

        // --- Live Regions (aria-live) ---
        let liveNodes: [AccessibilityNode] = allNodes.filter({ $0.live != "off" })
        for node in liveNodes {
            let key: NodeID = node.node.id
            let newText: String = node.text
            guard let oldText = liveRegionTexts[key] else {
                liveRegionTexts[key] = newText
                continue
            }
            if newText != oldText {
                liveRegionTexts[key] = newText
                if !newText.isEmpty {
                    if node.live == "assertive" {
                        accessibilityThread.speakUrgent(newText)
                    } else {
                        accessibilityThread.speakPolite(newText)
                    }
                }
            }
        }

        // --- Legacy "role=alert" (backward compat) ---
        let activeAlerts: [AccessibilityNode] = allNodes.filter({ $0.role == "alert" })
        for alert in activeAlerts {
            if !spokenAlerts.contains(where: { $0.node.id == alert.node.id }) {
                speakNode(alert, "New alert")
                spokenAlerts.append(alert)
            }
        }
        spokenAlerts = spokenAlerts.filter({ old in
            allNodes.contains(where: { $0.node.id == old.node.id && $0.role == "alert" })
        })

        let currentFocus: ElementRef? = activeTab?.focus
        if currentFocus?.id != lastFocus {
            if let f = currentFocus,
                let focused = allNodes.first(where: { $0.node.id == f.id })
            {
                speakNode(focused, "element focused ")
            }
            lastFocus = currentFocus?.id
        }

        if needsSpeakHoveredNode, let hovered = hoveredA11yNode {
            accessibilityThread.stopSpeaking()
            speakNode(hovered, "Hit test ")
        }

        needsSpeakHoveredNode = false
    }

    public func toggleAccessibility() {
        accessibilityIsOn = !accessibilityIsOn
        if accessibilityIsOn { hasSpokenDocument = false }
        activeTab?.needsAccessibility = true
        hoveredA11yNode = nil
        accessibilityFocusNode = nil
        needsSpeakHoveredNode = false
    }

    public func handleHover(x: CGFloat, y: CGFloat) {
        activeTab?.hover(x: x, y: y)
        guard accessibilityIsOn, activeTab?.accessibilityTree != nil else { return }
        pendingHover = CGPoint(x: x, y: y)
        setNeedsDrawOnly()
        scheduleRasterAndDraw()
    }
}

