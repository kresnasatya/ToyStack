import SwiftUI

@MainActor
public class Browser: ObservableObject {
    @Published public var tabs: [Engine.Tab] = []
    @Published public var activeTab: Engine.Tab?
    public let chrome: Chrome
    public var windowSize: CGSize = CGSize(width: WIDTH, height: HEIGHT)
    private var animationTimer: Timer?
    public var accessibilityIsOn: Bool = false
    private var compositedLayers: [CompositedLayer] = []
    public private(set) var drawList: [Any] = []
    private var activeTabDisplayList: [Any] = []
    private var compositedUpdates: [ObjectIdentifier: VisualEffect] = [:]
    public private(set) var activeTabScroll: CGFloat = 0

    private var needsComposite: Bool = false
    private var needsRaster: Bool = false
    private var needsDraw: Bool = false
    private var needsAnimationFrame: Bool = true

    public var darkMode: Bool = false

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
        compositedUpdates = data.compositedUpdates ?? [:]

        if data.compositedUpdates == nil {
            setNeedsComposite()  // nil -> full composite + raster + draw
        } else {
            setNeedsDrawOnly()
        }

        compositeRasterAndDraw()
    }

    private func composite() {
        compositedLayers = []
        addParentPointers(activeTabDisplayList)
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
                    let cloned: VisualEffect
                    if let blend = newParent as? Blend {
                        cloned = blend.clone(child: currentEffect)
                    } else if let transform = newParent as? Transform {
                        cloned = transform.clone(child: currentEffect)
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

        if needsComposite { composite() }
        if needsRaster { rasterTab() }
        if needsDraw {
            paintDrawList()
            objectWillChange.send()
        }

        needsComposite = false
        needsRaster = false
        needsDraw = false
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
}

// Explicitly declares Browser as a TabManager implementor.
// All required members (tabs, activeTab, newTab) are already defined in the class.
extension Browser: TabManager {}
