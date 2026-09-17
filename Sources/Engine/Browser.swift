import Combine
import CoreGraphics
import Foundation

@MainActor
public class Browser: ObservableObject {
    @Published public var tabs: [Engine.Tab] = []
    @Published public private(set) var activeTab: Engine.Tab?
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
    private let accessibilityThread = AccessibilityThread()
    public var accessibilityIsOn: Bool = false
    private var hasSpokenDocument: Bool = false
    private var spokenAlerts: [AccessibilityNode] = []
    private var lastFocus: Element? = nil
    private var pendingHover: CGPoint? = nil
    private var hoveredA11yNode: AccessibilityNode? = nil
    private var needsSpeakHoveredNode: Bool = false
    private var accessibilityFocusNode: AccessibilityNode? = nil
    private var liveRegionTexts: [ObjectIdentifier: String] = [:]

    struct FramePaint {
        var displayList: [Any] = []
        var compositedUpdates: [ObjectIdentifier: Engine.VisualEffect] = [:]
        var paintEpoch = 0
        var effectUpdateEpoch = 0
    }

    struct FrameRender {
        var layers: [CompositedLayer] = []
        var drawList: [Any] = []
        var content = RenderedContent()
        var signature: FrameSignature?
    }

    private struct TabFrame {
        var paint = FramePaint()
        var scroll = ScrollState(scroll: 0, interestTop: 0, interestBottom: 0, maxScroll: 0)
        var render = FrameRender()
        var theme = ThemeState(prefersDark: false, forcedColors: false)
    }

    private var frames: [ObjectIdentifier: TabFrame] = [:]
    private var activeFrameID: ObjectIdentifier?
    private var activeFrame = TabFrame()

    public var drawList: [Any] { activeFrame.render.drawList }
    public var activeTabScroll: CGFloat { activeFrame.scroll.scroll }
    public var activeTabInterestTop: CGFloat { activeFrame.scroll.interestTop }
    public var contentImage: CGImage? { activeFrame.render.content.image }
    public var contentRegionTop: CGFloat { activeFrame.render.content.regionTop }
    public var activePlacements: [PlacedLayer] { activeFrame.render.content.placements }
    public var usesSublayers: Bool { activeFrame.render.content.usesSublayers }
    public var presentedFrame: PresentedFrame {
        PresentedFrame(
            content: activeFrame.render.content,
            viewport: PresentedViewport(
                contentOffset: topInset - activeFrame.scroll.scroll,
                displayScale: displayScale,
                canvasColor: canvasColor,
                scrollbar: activeSidebar
            )
        )
    }
    public var onPresent: ((PresentedFrame) -> Void)?
    private var lastTileScroll: CGFloat = .nan

    public var canvasColor: CGColor {
        let name = activeFrame.theme.forcedColors ? ForcedColor.canvas : (activeFrame.theme.prefersDark ? "black" : "white")
        return EngineColor(cssName: name).cgColor
    }

    public var activeSidebar: (frame: CGRect, color: CGColor)? {
        let contentHeight = windowSize.height - topInset
        guard contentHeight > 0,
            let bar = scrollbarBarRect(
                ScrollbarGeometry(
                    docHeight: activeFrame.scroll.maxScroll + contentHeight,
                    contentHeight: contentHeight,
                    contentWidth: windowSize.width,
                    scroll: activeFrame.scroll.scroll
                ),
                forcedColors: activeFrame.theme.forcedColors,
                topInset: topInset
            )
        else { return nil }
        let color = EngineColor(cssName: activeFrame.theme.forcedColors ? ForcedColor.canvasText : "blue")
        return (bar.rect.cgRect, color.cgColor)
    }

    private var needsComposite: Bool = false
    private var needsRaster: Bool = false
    private var needsDraw: Bool = false
    private var needsAnimationFrame: Bool = true
    private var compositeInFlight = false
    private var needsTileContinuation = false
    private var tileContinuationPasses = 0

    @Published public var prefersDark: Bool = false
    @Published public private(set) var commitedPrefersDark: Bool = false

    @Published public var forcedColors: Bool = false
    @Published public private(set) var commitedForcedColors: Bool = false

    public var measure = MeasureTime()

    let networkTaskRunner = NetworkTaskRunner()
    let rasterScheduler = RasterScheduler()

    public init() {
        rasterScheduler.measure = measure
    }

    public func newTab(_ url: WebURL) {
        let tab = Engine.Tab(
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
        let id = ObjectIdentifier(tab)
        activeFrameID = id
        activeFrame = TabFrame()
        frames[id] = activeFrame
        startAnimationTimer()
    }

    public func resize(to size: CGSize) {
        windowSize = size
        activeTab?.resize(width: size.width, height: size.height - topInset)
    }

    public func startAnimationTimer() {
        guard animationTimer == nil else { return }
        nextFrameTime = Date()
        scheduleNextFrame()
    }

    private func scheduleNextFrame() {
        let now = Date()

        nextFrameTime = max(nextFrameTime + FRAME_BUDGET, now)
        let delay = nextFrameTime.timeIntervalSinceNow
        animationTimer = Timer.scheduledTimer(
            withTimeInterval: max(0, delay), repeats: false,
            block: {
                [weak self] _ in
                Task { @MainActor in
                    self?.animationTick()
                    self?.scheduleNextFrame()
                }
            })
    }

    public func stopAnimationTimer() {
        animationTimer?.invalidate()
        animationTimer = nil
        measure.close()
    }

    private func animationTick() {
        guard needsAnimationFrame else {
            return
        }
        needsAnimationFrame = false
        frameStartTime = Date()
        activeTab?.runAnimationFrame()
    }

    func commit(tab: Engine.Tab, data: CommitData) {
        guard tab === activeTab else { return }
        let paintChanged = data.paint.paintEpoch != activeFrame.paint.paintEpoch
        activeFrame.paint.displayList = data.paint.displayList
        activeFrame.scroll.scroll = data.scrollState.scroll
        activeFrame.scroll.interestTop = data.scrollState.interestTop
        activeFrame.scroll.interestBottom = data.scrollState.interestBottom
        activeFrame.scroll.maxScroll = data.scrollState.maxScroll
        activeFrame.theme.prefersDark = data.theme.prefersDark
        activeFrame.theme.forcedColors = data.theme.forcedColors
        activeFrame.paint.paintEpoch = data.paint.paintEpoch
        activeFrame.paint.compositedUpdates = data.paint.compositedUpdates ?? [:]

        if let updates = data.paint.compositedUpdates, !updates.isEmpty {
            activeFrame.paint.effectUpdateEpoch += 1
        }

        if paintChanged {
            objectWillChange.send()
        }

        if let updates = data.paint.compositedUpdates, !updates.isEmpty,
            activeFrame.render.content.usesSublayers,
            !needsComposite, !needsRaster, !needsDraw, !compositeInFlight,
            Browser.updatesAreCA(updates),
            applyEffectFastPath(updates)
        {
            frames[ObjectIdentifier(tab)] = activeFrame
            return
        }

        if data.paint.compositedUpdates == nil {
            setNeedsComposite()
        } else {
            setNeedsDrawOnly()
        }

        frames[ObjectIdentifier(tab)] = activeFrame
        scheduleRasterAndDraw()
    }

    private func applyEffectFastPath(_ updates: [ObjectIdentifier: Engine.VisualEffect]) -> Bool {
        let layers = activeFrame.render.layers
        let infos = layers.map({ Browser.layerEffectInfo($0, updates: updates) })
        let keys = Set(infos.compactMap({ $0.effect?.key }))
        guard updates.keys.allSatisfy({ keys.contains($0) }) else { return false }
        for (index, info) in infos.enumerated() where info.kind == .ca {
            if layers[index].effectImage == nil { return false }
        }
        activeFrame.render.content.placements = Browser.layerPlacements(layers, infos: infos)
        dispatchPresent()
        return true
    }

    private func dispatchPresent() {
        measure.start("present.main")
        onPresent?(presentedFrame)
        measure.stop("present.main")
    }

    private func resolvePendingHover() {
        guard let pending = pendingHover else { return }
        let adjustedY = pending.y + activeTabScroll
        if let hit = activeTab?.accessibilityTree?.hitTest(x: pending.x, y: adjustedY) {
            if hoveredA11yNode == nil || hit.node !== hoveredA11yNode!.node {
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

        let wantsComposite = needsComposite

        let scrollState = ScrollState(
            scroll: activeFrame.scroll.scroll,
            interestTop: activeFrame.scroll.interestTop,
            interestBottom: activeFrame.scroll.interestBottom,
            maxScroll: activeFrame.scroll.maxScroll
        )

        let inputs = RasterInput(
            scene: RasterScene(
                displayList: activeFrame.paint.displayList,
                compositedUpdates: activeFrame.paint.compositedUpdates,
                previousLayers: activeFrame.render.layers,
            ),
            settings: RasterSettings(
                viewport: ViewportInfo(windowSize: windowSize, topInset: topInset, displayScale: displayScale),
                theme: ThemeState(prefersDark: activeFrame.theme.prefersDark, forcedColors: activeFrame.theme.forcedColors),
                flags: RasterFlags(needsComposite: wantsComposite, needsDraw: needsDraw),
                accessibility: AccessibilityBounds(hoveredBounds: hoveredA11yNode?.bounds, readBounds: accessibilityFocusNode?.bounds)
            ),
            scrollState: scrollState
        )

        let signature = FrameSignature(
            geometry: FrameGeometry(
                scroll: activeFrame.scroll.scroll,
                viewport: windowSize,
                displayScale: displayScale
            ),
            epochs: FrameEpoch(
                paintEpoch: activeFrame.paint.paintEpoch,
                effectUpdates: activeFrame.paint.effectUpdateEpoch
            ),
            theme: ThemeState(prefersDark: activeFrame.theme.prefersDark, forcedColors: activeFrame.theme.forcedColors),
            accessibility: AccessibilityBounds(hoveredBounds: hoveredA11yNode?.bounds, readBounds: accessibilityFocusNode?.bounds)
        )
        if signature == activeFrame.render.signature && !needsTileContinuation {
            needsDraw = false
            frameStartTime = .distantPast
            return
        }

        if !needsTileContinuation { tileContinuationPasses = 0 }
        needsTileContinuation = false

        compositeInFlight = true
        if wantsComposite {
            needsComposite = false
            needsRaster = false
        }
        needsDraw = false

        measure.start("composite_raster_and_draw")
        let frameStart = frameStartTime
        frameStartTime = .distantPast
        let ownerID = activeFrameID

        let measure = self.measure
        rasterScheduler.schedule(
            RasterScheduler.Job(
                scale: inputs.settings.viewport.displayScale,
                plan: { (store: TileStore) -> RasterPlan in
                    measure.start("raster.plan")

                    measure.start("raster.composite")
                    let layers =
                        inputs.settings.flags.needsComposite
                        ? Browser.computeComposite(inputs)
                        : inputs.scene.previousLayers
                    measure.stop("raster.composite")

                    let tabHeight = inputs.settings.viewport.windowSize.height - inputs.settings.viewport.topInset
                    let prefetch = 2 * CompositedLayer.tileSize
                    let viewportWidth = inputs.settings.viewport.windowSize.width
                    let window = RasterWindow(
                        hint: Rect(
                            left: 0,
                            top: inputs.scrollState.scroll - prefetch,
                            right: viewportWidth,
                            bottom: inputs.scrollState.scroll + tabHeight + prefetch
                        ),
                        visible: Rect(
                            left: 0,
                            top: inputs.scrollState.scroll,
                            right: viewportWidth,
                            bottom: inputs.scrollState.scroll + tabHeight
                        )
                    )

                    let infos = layers.map {
                        Browser.layerEffectInfo($0, updates: inputs.scene.compositedUpdates)
                    }
                    let usesSublayers = !infos.contains {
                        $0.kind == .blendFallback || $0.kind == .scrollFallback
                    }

                    measure.start("raster.plan.tiles")
                    var strips: [TileStrip] = []
                    var deferred = false
                    if usesSublayers {
                        store.beginComposite(
                            viewportTop: inputs.scrollState.scroll,
                            viewportBottom: inputs.scrollState.scroll + tabHeight
                        )
                        let budget = RasterBudget(CompositedLayer.rasterCapPerComposite)

                        for (index, layer) in layers.enumerated() where infos[index].kind == .flat {
                            strips.append(contentsOf: layer.rasterIfNeeded(
                                scale: inputs.settings.viewport.displayScale,
                                store: store,
                                window: window,
                                budget: budget
                            ))
                            layer.pruneTiles(
                                keepTop: inputs.scrollState.scroll - 4 * CompositedLayer.tileSize,
                                keepBottom: inputs.scrollState.scroll + tabHeight + 4 * CompositedLayer.tileSize
                            )
                        }

                        deferred = budget.remaining == 0
                    }

                    measure.stop("raster.plan.tiles")
                    measure.stop("raster.plan")

                    return RasterPlan(
                        commit: RasterCommit(
                            inputs: inputs,
                            layers: layers,
                            infos: infos,
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
                    let layers = plan.commit.layers
                    let infos = plan.commit.infos
                    let inputs = plan.commit.inputs

                    measure.start("raster.install")
                    if plan.commit.usesSublayers {
                        measure.start("raster.install.tiles")
                        for (i, strip) in plan.batch.strips.enumerated() {
                            guard let stripImage = images[i] else { continue }
                            for key in strip.tiles {
                                guard let tile = stripImage.cropping(
                                    to: TileStrip.sliceRect(
                                        for: key,
                                        in: strip.bounds,
                                        scale: inputs.settings.viewport.displayScale
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
                            "layers": layers.count,
                            "flat": infos.filter({ $0.kind == .flat }).count
                        ])
                        if plan.batch.deferred {
                            store.markDeferred()
                        }
                        measure.start("raster.effect")
                        for (index, layer) in layers.enumerated() where infos[index].kind == .ca {
                            Browser.updateEffectImage(
                                layer,
                                scale: inputs.settings.viewport.displayScale,
                                blur: infos[index].blur
                            )
                        }
                        measure.stop("raster.effect")
                    }

                    let drawList = Browser.computePaintDrawList(layers: layers, inputs: inputs)
                    let regionTop = inputs.scrollState.scroll
                    var contentImage: CGImage? = nil

                    if !plan.commit.usesSublayers && inputs.settings.flags.needsDraw {
                        let regionHeight = inputs.settings.viewport.topInset + plan.batch.tabHeight
                        measure.start("raster.bitmap")
                        contentImage = inputs.settings.flags.needsDraw
                            ? CGRenderer.renderBitmap(
                                size: CGSize(
                                    width: inputs.settings.viewport.windowSize.width,
                                    height: regionHeight
                                ),
                                scale: inputs.settings.viewport.displayScale,
                                backgroundColor: inputs.settings.theme.forcedColors
                                    ? EngineColor(cssName: ForcedColor.canvas)
                                    : (inputs.settings.theme.prefersDark ? EngineColor(cssName: "black") : EngineColor(cssName: "white"))
                            ) { r in
                                r.saveState()
                                r.translateBy(x: 0, y: inputs.settings.viewport.topInset - regionTop)
                                for item in drawList {
                                    if let cmd = item as? any PaintCommand {
                                        cmd.execute(scroll: 0, renderer: r)
                                    } else if let ve = item as? Engine.VisualEffect {
                                        ve.execute(renderer: r)
                                    }
                                }
                                r.restoreState()
                            }
                            : nil
                        measure.stop("raster.bitmap")
                    }
                    measure.stop("raster.install")

                    return RasterOutput(
                        compositedLayers: inputs.settings.flags.needsComposite ? layers : nil,
                        drawList: drawList,
                        content: RenderedContent(
                            placements: plan.commit.usesSublayers ? Browser.layerPlacements(layers, infos: infos) : [],
                            image: contentImage,
                            regionTop: regionTop,
                            usesSublayers: plan.commit.usesSublayers
                        ),
                        needsMoreTiles: store.needsMoreTiles
                    )
                },
                then: { [weak self] (output: RasterOutput) in
                    guard let self = self else { return }
                    if let ownerID {
                        if ownerID == self.activeFrameID {
                            self.activeFrame.render.layers = output.compositedLayers ?? self.activeFrame.render.layers
                            if let drawList = output.drawList { self.activeFrame.render.drawList = drawList }
                            if inputs.settings.flags.needsDraw || output.content.usesSublayers {
                                self.activeFrame.render.content = output.content
                                self.dispatchPresent()
                            }
                            self.activeFrame.render.signature = signature
                            self.frames[ownerID] = self.activeFrame
                            if output.content.usesSublayers, output.needsMoreTiles, self.tileContinuationPasses < 8 {
                                self.tileContinuationPasses += 1
                                self.needsTileContinuation = true
                                self.needsRaster = true
                            }
                            if self.commitedPrefersDark != inputs.settings.theme.prefersDark {
                                self.commitedPrefersDark = inputs.settings.theme.prefersDark
                            }
                            if self.commitedForcedColors != inputs.settings.theme.forcedColors {
                                self.commitedForcedColors = inputs.settings.theme.forcedColors
                            }
                        } else if var stale = self.frames[ownerID] {
                            stale.render.layers = output.compositedLayers ?? stale.render.layers
                            if let drawList = output.drawList { stale.render.drawList = drawList }
                            if inputs.settings.flags.needsDraw { stale.render.content = output.content }
                            stale.render.signature = signature
                            self.frames[ownerID] = stale
                        }
                    }

                    self.updateAccessibility()
                    self.measure.stop("composite_raster_and_draw")
                    self.compositeInFlight = false
                    if frameStart != .distantPast {
                        let elapsed = Date().timeIntervalSince(frameStart)
                        self.recentFrameTimes.append(elapsed)
                        if self.recentFrameTimes.count > self.frameHistorySize {
                            self.recentFrameTimes.removeFirst()
                        }
                        let avg = self.recentFrameTimes.reduce(0, +) / Double(self.recentFrameTimes.count)
                        self.estimatedFrameTime = max(avg, self.FRAME_BUDGET)
                    }
                    if self.needsComposite || self.needsRaster || self.needsDraw {
                        self.scheduleRasterAndDraw()
                    }
                }
            )
        )
    }

    nonisolated static func computeComposite(_ inputs: RasterInput) -> [CompositedLayer] {
        var displayList = inputs.scene.displayList
        addParentPointers(&displayList)

        var allCommands: [Any] = []
        for item in displayList {
            treeToList(item, into: &allCommands)
        }

        let nonComposited = allCommands.compactMap({ item -> (any PaintCommand)? in
            if let pc = item as? (any PaintCommand) { return pc }
            if let ve = item as? VisualEffect, !ve.needsCompositing {
                if ve.parent == nil || ve.parent!.needsCompositing { return nil }
            }
            return nil
        })

        var compositedLayers: [CompositedLayer] = []
        var assumeOverlap = false
        for cmd in nonComposited {
            let underAnimated = sequence(
                first: cmd.parentEffect, next: { $0?.parent as? VisualEffect }
            ).contains(where: { ($0 as? Transform)?.isAnimated == true })
            if underAnimated { assumeOverlap = true }
            var merged = false
            for layer in compositedLayers.reversed() {
                if layer.canMerge(cmd) {
                    layer.add(cmd)
                    merged = true
                    break
                } else if assumeOverlap {
                    compositedLayers.append(CompositedLayer(displayItem: cmd))
                    merged = true
                    break
                }
            }
            if !merged {
                compositedLayers.append(CompositedLayer(displayItem: cmd))
            }
        }

        for layer in compositedLayers {
            var chain: [VisualEffect] = []
            var effect = layer.displayItems.first?.parentEffect
            while let e = effect {
                chain.append(e)
                effect = e.parent
            }
            layer.ancestorChain = chain
        }

        return compositedLayers
    }

    nonisolated private static func getLatest(
        _ effect: Engine.VisualEffect,
        in compositedUpdates: [ObjectIdentifier: Engine.VisualEffect]
    ) -> Engine.VisualEffect {
        guard let node = effect.node else { return effect }
        let key = ObjectIdentifier(node)
        guard let updated = compositedUpdates[key] else { return effect }
        if type(of: effect) == type(of: updated) {
            return updated
        }
        var stack: [VisualEffect] = [updated]
        while let candidate = stack.popLast() {
            if type(of: candidate) == type(of: effect) {
                return candidate
            }
            for child in candidate.children {
                if let ve = child as? VisualEffect {
                    stack.append(ve)
                }
            }
        }
        return effect
    }

    nonisolated static func layerEffectInfo(_ layer: CompositedLayer, updates: [ObjectIdentifier: Engine.VisualEffect]) -> LayerEffectInfo {
        var kind = LayerEffectInfo.Kind.flat
        var opacity: Double = 1
        var translation = CGPoint.zero
        var blur: CGFloat = 0
        var key: ObjectIdentifier?
        var blendMode: EngineBlendMode?
        for effect in layer.ancestorChain {
            let latest = getLatest(effect, in: updates)
            if latest is ScrollEffect {
                kind = max(kind, .scrollFallback)
            } else if let blend = latest as? Blend {
                opacity *= blend.opacity
                if let mode = blend.blendMode, mode != .normal {
                    if mode.compositingFilterName != nil {
                        kind = max(kind, .ca)
                        if blendMode == nil { blendMode = mode }
                    } else {
                        kind = max(kind, .blendFallback)
                    }
                } else if blend.opacity < 1 {
                    kind = max(kind, .ca)
                }
                if key == nil, let node = latest.node { key = ObjectIdentifier(node) }
            } else if let transform = latest as? Transform {
                if let t = transform.translation {
                    translation.x += t.x
                    translation.y += t.y
                    kind = max(kind, .ca)
                }
                if transform.isAnimated { kind = max(kind, .ca) }
                if key == nil, let node = latest.node { key = ObjectIdentifier(node) }
            } else if let filter = latest as? BlurFilter, filter.radius > 0 {
                blur = max(blur, filter.radius)
                kind = max(kind, .ca)
                if key == nil, let node = latest.node { key = ObjectIdentifier(node) }
            }
        }
        let effect = kind == .ca
            ? LayerEffect(
                key: key,
                opacity: opacity,
                translation: translation,
                blendMode: blendMode
            )
            : nil
        return LayerEffectInfo(kind: kind, effect: effect, blur: blur)
    }

    nonisolated static func updatesAreCA(_ updates: [ObjectIdentifier: Engine.VisualEffect]) -> Bool {
        updates.values.allSatisfy({ isCAEffect($0) })
    }

    nonisolated private static func isCAEffect(_ effect: Engine.VisualEffect) -> Bool {
        if effect is ScrollEffect { return false }
        if let blend = effect as? Blend,
            let mode = blend.blendMode, mode != .normal, mode.compositingFilterName == nil {
            return false
        }
        if let blur = effect as? BlurFilter, blur.radius > 0 { return false }
        for child in effect.children {
            if let nested = child as? VisualEffect, isCAEffect(nested) { return false }
        }
        return true
    }

    nonisolated static func computePaintDrawList(
        layers: [CompositedLayer],
        inputs: RasterInput
    ) -> [Any] {
        var newEffects: [ObjectIdentifier: VisualEffect] = [:]
        var drawList: [Any] = []
        for layer in layers {
            guard !layer.displayItems.isEmpty else { continue }
            var currentEffect: Any = DrawCompositedLayer(
                layer: layer,
                visibleTop: inputs.scrollState.scroll - 2 * CompositedLayer.tileSize,
                visibleBottom: inputs.scrollState.scroll + (inputs.settings.viewport.windowSize.height - inputs.settings.viewport.topInset) + 2 * CompositedLayer.tileSize
            )
            var mergedIntoExisting = false
            for p in layer.ancestorChain {
                let newParent = getLatest(p, in: inputs.scene.compositedUpdates)
                let newParentKey = ObjectIdentifier(newParent)
                if let existing = newEffects[newParentKey] {
                    existing.children.append(currentEffect)
                    mergedIntoExisting = true
                    break
                } else {
                    let cloned: Engine.VisualEffect
                    if let blend = newParent as? Blend {
                        cloned = blend.clone(child: currentEffect)
                    } else if let transform = newParent as? Transform {
                        cloned = transform.clone(child: currentEffect)
                    } else if let blur = newParent as? BlurFilter {
                        cloned = blur.clone(child: currentEffect)
                    } else if let se = newParent as? ScrollEffect {
                        cloned = se.clone(child: currentEffect)
                    } else {
                        cloned = newParent
                    }
                    newEffects[newParentKey] = cloned
                    currentEffect = cloned
                }
            }
            if !mergedIntoExisting {
                drawList.append(currentEffect)
            }
        }

        if let bounds = inputs.settings.accessibility.hoveredBounds {
            drawList.append(DrawOutline(rect: bounds, color: inputs.settings.theme.forcedColors ? ForcedColor.highlight : "white", thickness: 4))
            drawList.append(DrawOutline(rect: bounds, color: "black", thickness: 2))
        }

        if let bounds = inputs.settings.accessibility.readBounds {
            drawList.append(DrawOutline(rect: bounds, color: "gold", thickness: 4))
            drawList.append(DrawOutline(rect: bounds, color: "black", thickness: 2))
        }

        return drawList
    }

    nonisolated static func layerPlacements(_ layers: [CompositedLayer], infos: [LayerEffectInfo]) -> [PlacedLayer] {
        let t = CompositedLayer.tileSize
        var placements: [PlacedLayer] = []
        for (z, layer) in layers.enumerated() {
            switch infos[z].kind {
                case .flat:
                    for (index, image) in layer.tiles {
                        placements.append(
                            PlacedLayer(
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
                    let bounds = layer.compositedBounds()
                    placements.append(
                        PlacedLayer(
                            key: .composited(zIndex: z),
                            image: image,
                            frame: CGRect(x: bounds.left, y: bounds.top, width: bounds.right - bounds.left, height: bounds.bottom - bounds.top),
                            effect: infos[z].effect
                        )
                    )
                case .blendFallback, .scrollFallback:
                    break
            }
        }
        return placements
    }

    nonisolated static func rasterEffectBitmap(_ layer: CompositedLayer, scale: CGFloat, blur: CGFloat) -> CGImage? {
        let bounds = layer.compositedBounds()
        let size = CGSize(width: bounds.right - bounds.left, height: bounds.bottom - bounds.top)
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
        let key = CompositedLayer.EffectImageKey(scale: scale, blur: blur, bounds: layer.compositedBounds())
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

    func setNeedsRaster() {
        needsRaster = true
        needsDraw = true
    }

    func setNeedsDrawOnly() {
        needsDraw = true
    }

    func setNeedsAnimationFrame(_ tab: Engine.Tab) {
        if tab === activeTab {
            needsAnimationFrame = true
        }
    }

    public func applyScroll(_ scroll: CGFloat) {
        activeFrame.scroll.scroll = scroll
        if let id = activeFrameID {
            frames[id]?.scroll.scroll = scroll
        }

        if activeFrame.render.content.usesSublayers {
            dispatchPresent()
            let step = CompositedLayer.tileSize
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
        activeFrame.scroll.scroll = scroll
        activeFrame.scroll.interestTop = interestTop
        activeFrame.scroll.interestBottom = interestBottom
        if let id = activeFrameID {
            frames[id]?.scroll.scroll = scroll
            frames[id]?.scroll.interestTop = interestTop
            frames[id]?.scroll.interestBottom = interestBottom
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

    public func incrementZoom(_ increment: Bool) {
        activeTab?.zoomBy(increment)
    }

    public func resetZoom() {
        activeTab?.resetZoom()
    }

    public func cycleTabs() {
        guard !tabs.isEmpty, let current = activeTab,
            let idx = tabs.firstIndex(where: { $0 === current })
        else {
            return
        }
        let nextIdx = (idx + 1) % tabs.count
        selectTab(tabs[nextIdx])
    }

    public func selectTab(_ tab: Tab) {
        guard tab !== activeTab else { return }
        if let oldID = activeFrameID {
            frames[oldID] = activeFrame
        }
        let id = ObjectIdentifier(tab)
        activeFrameID = id
        activeFrame = frames[id] ?? TabFrame()
        activeTab = tab
        hoveredA11yNode = nil
        hasSpokenDocument = false
        spokenAlerts = []
        liveRegionTexts = [:]
        lastFocus = nil
        needsComposite = false
        needsRaster = false
        needsDraw = false
        if activeFrame.render.content.image == nil && !activeFrame.render.content.usesSublayers {
            setNeedsComposite()
        } else if let sig = activeFrame.render.signature,
            sig.geometry.viewport != windowSize || sig.geometry.displayScale != displayScale {
            setNeedsComposite()
        }
        needsAnimationFrame = true
        activeTab?.runAnimationFrame()
    }

    private func speakText(_ text: String) {
        accessibilityThread.speak(text)
    }

    private func speakDocument() {
        guard let tree = activeTab?.accessibilityTree else { return }
        var text = "Here the document contents: "
        for node in treeToList(tree) {
            if !node.text.isEmpty { text += "\n" + node.text }
        }
        accessibilityThread.stopSpeaking()
        speakText(text)
    }

    public func advanceAccessibility() {
        guard accessibilityIsOn, let tree = activeTab?.accessibilityTree else { return }
        let readable = treeToList(tree).filter({ !$0.text.isEmpty })
        guard !readable.isEmpty else { return }

        var nextIndex = 0
        if let current = accessibilityFocusNode, let idx = readable.firstIndex(where: { $0.node === current.node }) {
            nextIndex = idx + 1
        }

        if nextIndex < readable.count {
            let next = readable[nextIndex]
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
        let text = prefix + node.text
        if !text.isEmpty { speakText(text) }
    }

    func updateAccessibility() {
        guard accessibilityIsOn, let tree = activeTab?.accessibilityTree else { return }

        if !hasSpokenDocument {
            speakDocument()
            hasSpokenDocument = true
        }

        let allNodes = treeToList(tree)

        // --- Live Regions (aria-live) ---
        let liveNodes = allNodes.filter({ $0.live != "off" })
        for node in liveNodes {
            let key = ObjectIdentifier(node.node)
            let newText = node.text
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
        let activeAlerts = allNodes.filter({ $0.role == "alert" })
        for alert in activeAlerts {
            if !spokenAlerts.contains(where: { $0.node === alert.node }) {
                speakNode(alert, "New alert")
                spokenAlerts.append(alert)
            }
        }
        spokenAlerts = spokenAlerts.filter({ old in
            allNodes.contains(where: { $0.node === old.node && $0.role == "alert" })
        })

        let currentFocus = activeTab?.focus
        if currentFocus !== lastFocus {
            if let f = currentFocus,
                let focused = allNodes.first(where: { $0.node === f })
            {
                speakNode(focused, "element focused ")
            }
            lastFocus = currentFocus
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
        hoveredA11yNode = nil
        accessibilityFocusNode = nil
        needsSpeakHoveredNode = false
    }

    public func handleHover(x: CGFloat, y: CGFloat) {
        guard accessibilityIsOn, activeTab?.accessibilityTree != nil else { return }
        pendingHover = CGPoint(x: x, y: y)
        setNeedsDrawOnly()
        scheduleRasterAndDraw()
    }
}
