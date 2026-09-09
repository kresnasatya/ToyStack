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
    private var compositedLayers: [CompositedLayer] = []
    public private(set) var drawList: [Any] = []
    private var activeTabDisplayList: [Any] = []
    private var compositedUpdates: [ObjectIdentifier: VisualEffect] = [:]
    public private(set) var activeTabScroll: CGFloat = 0
    public private(set) var activeTabInterestTop: CGFloat = 0
    private var activeTabPaintEpoch = 0
    private var activeTabLayoutHeight: CGFloat = 0
    public private(set) var contentImage: CGImage?

    private var needsComposite: Bool = false
    private var needsRaster: Bool = false
    private var needsDraw: Bool = false
    private var needsAnimationFrame: Bool = true
    private var compositeInFlight = false
    private var lastCommittedSignature: FrameSignature?
    private var effectUpdateEpoch = 0

    @Published public var prefersDark: Bool = false
    public private(set) var activeTabPrefersDark: Bool = false
    @Published public private(set) var commitedPrefersDark: Bool = false

    @Published public var forcedColors: Bool = false
    public private(set) var activeTabForcedColors: Bool = false
    @Published public private(set) var commitedForcedColors: Bool = false

    public var measure = MeasureTime()

    let networkingThread = NetworkingThread()
    let rasterThread = RasterThread()
    private let tileStore = TileStore(tileSize: CompositedLayer.tileSize)

    public init() {}

    public func newTab(_ url: WebURL) {
        let tab = Engine.Tab(
            tabHeight: windowSize.height - topInset,
            tabWidth: windowSize.width
        )
        tab.browser = self
        tab.networkingThread = networkingThread
        tab.prefersDark = prefersDark
        tab.forcedColors = forcedColors
        tab.load(url)
        activeTab = tab
        tabs.append(tab)
        lastCommittedSignature = nil
        drawList = []
        compositedLayers = []
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

        nextFrameTime = max(nextFrameTime + estimatedFrameTime, now)
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
        print("[commit] scroll=\(data.scroll) layoutH=\(data.layoutHeight) height=\(data.height) updates=\(data.compositedUpdates?.count ?? -1) epoch=\(data.paintEpoch)")
        activeTabDisplayList = data.displayList
        activeTabScroll = data.scroll
        activeTabInterestTop = data.interestTop
        activeTabPrefersDark = data.prefersDark
        activeTabForcedColors = data.forcedColors
        activeTabPaintEpoch = data.paintEpoch
        activeTabLayoutHeight = data.layoutHeight
        compositedUpdates = data.compositedUpdates ?? [:]

        if let updates = data.compositedUpdates, !updates.isEmpty {
            effectUpdateEpoch += 1
        }

        if data.compositedUpdates == nil {
            setNeedsComposite()
        } else {
            setNeedsDrawOnly()
        }

        scheduleRasterAndDraw()
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

        let wantsComposite = needsComposite && !compositeInFlight
        if compositeInFlight && !wantsComposite {
            return
        }

        let inputs = RasterInputs(
            displayList: activeTabDisplayList, scroll: activeTabScroll,
            interestTop: activeTabInterestTop, interestBottom: activeTabInterestTop + 4 * (activeTab?.tabHeight ?? HEIGHT),
            windowSize: windowSize, topInset: topInset, docHeight: activeTabLayoutHeight,
            compositedUpdates: compositedUpdates, previousLayes: compositedLayers,
            tileStore: tileStore, displayScale: displayScale,
            prefersDark: activeTabPrefersDark, forcedColors: activeTabForcedColors,
            needsComposite: wantsComposite, needsRaster: needsRaster, needsDraw: needsDraw,
            hoveredBounds: hoveredA11yNode?.bounds, readBounds: accessibilityFocusNode?.bounds
        )

        let signature = FrameSignature(
            scroll: activeTabScroll,
            viewport: windowSize,
            paintEpoch: activeTabPaintEpoch,
            effectUpdates: effectUpdateEpoch,
            displayScale: displayScale,
            prefersDark: activeTabPrefersDark,
            forcedColors: activeTabForcedColors,
            hoveredBounds: hoveredA11yNode?.bounds,
            readBounds: accessibilityFocusNode?.bounds
        )
        if signature == lastCommittedSignature {
            needsDraw = false
            frameStartTime = .distantPast
            return
        }

        if wantsComposite {
            compositeInFlight = true
            needsComposite = false
            needsRaster = false
        }
        needsDraw = false

        measure.start("composite_raster_and_draw")
        let frameStart = frameStartTime
        frameStartTime = .distantPast

        rasterThread.submit(
            {
                let layers =
                    inputs.needsComposite
                    ? Browser.computeComposite(inputs)
                    : inputs.previousLayes
                if inputs.needsComposite {
                    inputs.tileStore.beginComposite(
                        viewportTop: inputs.scroll,
                        viewportBottom: inputs.scroll + (inputs.interestBottom - inputs.interestTop) / 4
                    )
                    let tabHeight = (inputs.interestBottom - inputs.interestTop) / 4
                    let budget = RasterBudget(CompositedLayer.rasterCapPerComposite)
                    for layer in layers {
                        layer.rasterIfNeeded(
                            scale: inputs.displayScale,
                            store: inputs.tileStore,
                            hintTop: inputs.interestTop,
                            hintBottom: inputs.interestBottom,
                            visibleTop: inputs.scroll,
                            visibleBottom: inputs.scroll + tabHeight,
                            budget: budget
                        )
                    }
                }
                let drawList =
                    inputs.needsDraw
                    ? Browser.computePaintDrawList(layers: layers, inputs: inputs)
                    : nil

                let tileInfo = layers.map { layer in
                    let rows = layer.tiles.keys.map(\.row)
                    return "cmds=\(layer.displayItems.count) tiles=\(layer.tiles.count) rows=\(rows.min() ?? -1)...\(rows.max() ?? -1)"
                }.joined(separator: " | ")
                print("[bitmap] scroll=\(inputs.scroll) topInset=\(inputs.topInset) docH=\(inputs.docHeight) winH=\(inputs.windowSize.height) translateY=\(inputs.topInset - inputs.scroll) layers=\(layers.count) \(tileInfo)")

                let contentImage: CGImage? =
                    inputs.needsDraw
                    ? CGRenderer.renderBitmap(
                        width: inputs.windowSize.width,
                        height: inputs.windowSize.height,
                        scale: inputs.displayScale,
                        backgroundColor: inputs.forcedColors
                            ? EngineColor(cssName: ForcedColor.canvas)
                            : (inputs.prefersDark ? EngineColor(cssName: "black") : EngineColor(cssName: "white"))
                    ) { r in
                        r.saveState()
                        r.translateBy(x: 0, y: inputs.topInset - inputs.scroll)
                        for item in drawList ?? [] {
                            if let cmd = item as? any PaintCommand {
                                cmd.execute(scroll: 0, renderer: r)
                            } else if let ve = item as? Engine.VisualEffect {
                                ve.execute(renderer: r)
                            }
                        }
                        r.restoreState()
                        if let bar = scrollbarBarRect(
                            docHeight: inputs.docHeight,
                            contentHeight: inputs.windowSize.height - inputs.topInset,
                            contentWidth: inputs.windowSize.width,
                            scroll: inputs.scroll,
                            forcedColors: inputs.forcedColors
                        ) {
                            bar.execute(scroll: 0, renderer: r)
                        }
                    }
                    : nil
                return RasterOutput(compositedLayers: inputs.needsComposite ? layers : nil, drawList: drawList, contentImage: contentImage)
            },
            then: { [weak self] output in
                guard let self = self else { return }
                if let layers = output.compositedLayers {
                    self.compositeInFlight = false
                    self.compositedLayers = layers
                }
                if let drawList = output.drawList { self.drawList = drawList }
                if inputs.needsDraw { self.contentImage = output.contentImage }
                print("[done] stored=\(self.contentImage.map { "\($0.width)x\($0.height)" } ?? "nil") forScroll=\(inputs.scroll) needsDraw=\(inputs.needsDraw)")
                if self.commitedPrefersDark != inputs.prefersDark {
                    self.commitedPrefersDark = inputs.prefersDark
                }
                if self.commitedForcedColors != inputs.forcedColors {
                    self.commitedForcedColors = inputs.forcedColors
                }
                if signature != self.lastCommittedSignature {
                    self.lastCommittedSignature = signature
                    self.objectWillChange.send()
                }

                self.updateAccessibility()
                self.measure.stop("composite_raster_and_draw")
                if inputs.needsComposite {
                    print("[tiles] hits=\(tileStore.hits) misses=\(tileStore.misses) "  + "top=\(Int(inputs.interestTop)) scroll=\(Int(inputs.scroll)) " + tileStore.populationDebug)
                }
                if frameStart != .distantPast {
                    let elapsed = Date().timeIntervalSince(frameStart)
                    self.recentFrameTimes.append(elapsed)
                    if self.recentFrameTimes.count > self.frameHistorySize {
                        self.recentFrameTimes.removeFirst()
                    }
                    let avg =
                        self.recentFrameTimes.reduce(0, +) / Double(self.recentFrameTimes.count)
                    self.estimatedFrameTime = max(avg, self.FRAME_BUDGET)
                }
                if self.needsComposite || self.needsRaster || self.needsDraw {
                    self.scheduleRasterAndDraw()
                }
            })
    }

    nonisolated static func computeComposite(_ inputs: RasterInputs) -> [CompositedLayer] {
        var displayList = inputs.displayList
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

    nonisolated static func computePaintDrawList(
        layers: [CompositedLayer],
        inputs: RasterInputs
    ) -> [Any] {
        var newEffects: [ObjectIdentifier: VisualEffect] = [:]
        var drawList: [Any] = []
        for layer in layers {
            guard !layer.displayItems.isEmpty else { continue }
            var currentEffect: Any = DrawCompositedLayer(
                layer: layer,
                visibleTop: inputs.scroll - 2 * CompositedLayer.tileSize,
                visibleBottom: inputs.scroll + (inputs.interestBottom - inputs.interestTop) / 4 + (2 * CompositedLayer.tileSize)
            )
            var mergedIntoExisting = false
            for p in layer.ancestorChain {
                let newParent = getLatest(p, in: inputs.compositedUpdates)
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

        if let bounds = inputs.hoveredBounds {
            drawList.append(DrawOutline(rect: bounds, color: inputs.forcedColors ? ForcedColor.highlight : "white", thickness: 4))
            drawList.append(DrawOutline(rect: bounds, color: "black", thickness: 2))
        }

        if let bounds = inputs.readBounds {
            drawList.append(DrawOutline(rect: bounds, color: "gold", thickness: 4))
            drawList.append(DrawOutline(rect: bounds, color: "black", thickness: 2))
        }

        return drawList
    }

    func setNeedsComposite() {
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
        print("[scroll] applyScroll=\(scroll) (was \(activeTabScroll)) layoutH=\(activeTabLayoutHeight)")
        activeTabScroll = scroll
        setNeedsDrawOnly()
        scheduleRasterAndDraw()
    }

    public func applyScrollAndRecomposite(scroll: CGFloat, interestTop: CGFloat) {
        print("[scroll] recomposite scroll=\(scroll) interestTop=\(interestTop) (was \(activeTabScroll))")
        activeTabScroll = scroll
        activeTabInterestTop = interestTop
        setNeedsComposite()
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
        activeTab = tab
        hoveredA11yNode = nil
        hasSpokenDocument = false
        spokenAlerts = []
        liveRegionTexts = [:]
        lastFocus = nil
        lastCommittedSignature = nil
        drawList = []
        compositedLayers = []
        setNeedsComposite()
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
