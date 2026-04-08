import SwiftUI

@MainActor
public class Browser: ObservableObject {
    @Published public var tabs: [Engine.Tab] = []
    @Published public var activeTab: Engine.Tab?
    public let chrome: Chrome
    public var windowSize: CGSize = CGSize(width: WIDTH, height: HEIGHT)
    private var animationTimer: Timer?
    public var accessibilityIsOn: Bool = false
    private var hasSpokenDocument: Bool = false
    private var spokenAlerts: [AccessibilityNode] = []
    private var lastFocus: Element? = nil
    private var pendingHover: CGPoint? = nil
    private var hoveredA11yNode: AccessibilityNode? = nil
    private var needsSpeakHoveredNode: Bool = false
    private var compositedLayers: [CompositedLayer] = []
    public private(set) var drawList: [Any] = []
    private var activeTabDisplayList: [Any] = []
    private var compositedUpdates: [ObjectIdentifier: VisualEffect] = [:]
    public private(set) var activeTabScroll: CGFloat = 0
    public private(set) var activeTabInterestTop: CGFloat = 0

    private var needsComposite: Bool = false
    private var needsRaster: Bool = false
    private var needsDraw: Bool = false
    private var needsAnimationFrame: Bool = true

    public var darkMode: Bool = false

    public var measure = MeasureTime()

    public init() {
        chrome = Chrome()
        chrome.tabManager = self
    }

    public func newTab(_ url: WebURL) async {
        let tab = Engine.Tab(
            tabHeight: windowSize.height - chrome.bottom,
            tabWidth: windowSize.width
        )
        tab.browser = self
        tab.setDarkMode(darkMode)
        await tab.load(url)
        activeTab = tab
        tabs.append(tab)
        startAnimationTimer()
    }

    public func resize(to size: CGSize) {
        windowSize = size
        chrome.resize(width: size.width)
        activeTab?.resize(width: size.width, height: size.height - chrome.bottom)
    }

    public func startAnimationTimer() {
        guard animationTimer == nil else { return }
        animationTimer = Timer.scheduledTimer(
            withTimeInterval: 1.0 / 60.0, repeats: true
        ) {
            [weak self] _ in
            Task { @MainActor in
                self?.animationTick()
            }
        }
    }

    public func stopAnimationTimer() {
        animationTimer?.invalidate()
        animationTimer = nil
        measure.close()
    }

    private func animationTick() {
        guard needsAnimationFrame else { return }
        needsAnimationFrame = false
        activeTab?.runAnimationFrame()
    }

    func commit(tab: Engine.Tab, data: CommitData) {
        guard tab === activeTab else { return }
        activeTabDisplayList = data.displayList
        activeTabScroll = data.scroll
        activeTabInterestTop = data.interestTop
        compositedUpdates = data.compositedUpdates ?? [:]

        if data.compositedUpdates == nil {
            setNeedsComposite()  // nil -> full composite + raster + draw
        } else {
            setNeedsDrawOnly()
        }

        compositeRasterAndDraw()
        updateAccessibility()
    }

    private func composite() {
        let interestBottom = activeTabInterestTop + 4 * HEIGHT
        compositedLayers = []
        addParentPointers(&activeTabDisplayList)
        var allCommands: [Any] = []
        for item in activeTabDisplayList {
            treeToList(item, into: &allCommands)
        }
        let nonComposited = allCommands.compactMap({ item -> (any PaintCommand)? in
            if let pc = item as? (any PaintCommand) { return pc }
            if let ve = item as? VisualEffect, !ve.needsCompositing {
                if ve.parent == nil || ve.parent!.needsCompositing { return nil }
            }
            return nil
        })
        for cmd in nonComposited {
            // skip commands entirely outside the interest region
            guard cmd.rect.bottom >= activeTabInterestTop && cmd.rect.top <= interestBottom else {
                continue
            }
            var merged = false
            for layer in compositedLayers.reversed() {
                if layer.canMerge(cmd) {
                    layer.add(cmd)
                    merged = true
                    break
                } else if layer.absoluteBounds().intersects(cmd.rect) {
                    compositedLayers.append(CompositedLayer(displayItem: cmd))
                    merged = true
                    break
                }
            }
            if !merged {
                compositedLayers.append(CompositedLayer(displayItem: cmd))
            }
        }
    }

    private func rasterTab() {
        // Rasterization is deferred to draw time in SwiftUI
        // CompositedLayer.raster() is called during execute DrawCompositedLayer
    }

    private func getLatest(_ effect: Engine.VisualEffect) -> Engine.VisualEffect {
        guard let node = effect.node else { return effect }
        let key = ObjectIdentifier(node)
        guard compositedUpdates[key] != nil else { return effect }
        guard effect is Blend else { return effect }
        return compositedUpdates[key]!
    }

    private func paintDrawList() {
        var newEffects: [ObjectIdentifier: VisualEffect] = [:]
        drawList = []
        for layer in compositedLayers {
            guard !layer.displayItems.isEmpty else { continue }
            var currentEffect: Any = DrawCompositedLayer(layer: layer)
            var parent: VisualEffect? = layer.displayItems[0].parentEffect
            while let p = parent {
                let newParent = getLatest(p)
                let newParentKey = ObjectIdentifier(newParent)
                if let existing = newEffects[newParentKey] {
                    existing.children.append(currentEffect)
                    currentEffect = existing
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
                    parent = p.parent
                }
            }
            if parent == nil {
                drawList.append(currentEffect)
            }
        }

        if let pending = pendingHover {
            let adjustedY = pending.y + activeTabScroll
            if let hit = activeTab?.accessibilityTree?.hitTest(x: pending.x, y: adjustedY) {
                if hoveredA11yNode == nil || hit.node !== hoveredA11yNode!.node {
                    needsSpeakHoveredNode = true
                }
                hoveredA11yNode = hit
            }
            pendingHover = nil
        }

        if let hovered = hoveredA11yNode {
            let color = darkMode ? "white" : "black"
            drawList.append(DrawOutline(rect: hovered.bounds, color: color, thickness: 2))
        }
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

    private func compositeRasterAndDraw() {
        guard needsComposite || needsRaster || needsDraw else { return }
        measure.start("composite_raster_and_draw")
        if needsComposite { composite() }
        if needsRaster { rasterTab() }
        if needsDraw {
            paintDrawList()
            objectWillChange.send()
        }

        needsComposite = false
        needsRaster = false
        needsDraw = false
        measure.stop("composite_raster_and_draw")
    }

    public func applyScroll(_ scroll: CGFloat) {
        activeTabScroll = scroll
        setNeedsDrawOnly()
        compositeRasterAndDraw()
    }

    public func toggleDarkMode() {
        darkMode = !darkMode
        activeTab?.setDarkMode(darkMode)
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
        activeTab = tabs[nextIdx]
        hoveredA11yNode = nil
        hasSpokenDocument = false
        spokenAlerts = []
        lastFocus = nil
        needsAnimationFrame = true
        objectWillChange.send()
    }

    private func speakText(_ text: String) {
        print("SPEAK:", text)
    }

    private func speakDocument() {
        guard let tree = activeTab?.accessibilityTree else { return }
        var text = "Here the document contents: "
        for node in treeToList(tree) {
            if !node.text.isEmpty { text += "\n" + node.text }
        }
        speakText(text)
    }

    private func speakNode(_ node: AccessibilityNode, _ prefix: String) {
        var text = prefix + node.text
        if !text.isEmpty, let first = node.children.first, first.role == "StaticText" {
            text += " " + first.text
        }
        if !text.isEmpty { speakText(text) }
    }

    func updateAccessibility() {
        guard accessibilityIsOn, let tree = activeTab?.accessibilityTree else { return }

        if !hasSpokenDocument {
            speakDocument()
            hasSpokenDocument = true
        }

        let allNodes = treeToList(tree)
        let activeAlerts = allNodes.filter({ $0.role == "alert " })
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
            speakNode(hovered, "Hit test ")
        }

        needsSpeakHoveredNode = false
    }

    public func toggleAccessibility() {
        accessibilityIsOn = !accessibilityIsOn
        if accessibilityIsOn { hasSpokenDocument = false }
    }

    public func handleHover(x: CGFloat, y: CGFloat) {
        guard accessibilityIsOn, activeTab?.accessibilityTree != nil else { return }
        pendingHover = CGPoint(x: x, y: y)
        setNeedsDrawOnly()
        compositeRasterAndDraw()
    }
}

// Explicitly declares Browser as a TabManager implementor.
// All required members (tabs, activeTab, newTab) are already defined in the class.
extension Browser: TabManager {}
