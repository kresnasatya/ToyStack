import CoreGraphics
import Foundation
import ImageIO

typealias ResourceLoad = (index: Int, url: WebURL, ref: WebURL?)

struct ResourceLoads {
    let styleURLs: [ResourceLoad]
    let scriptURLs: [ResourceLoad]
    let imageURLs: [ResourceLoad]
}

@MainActor
class Frame {
    static let scrollStep: CGFloat = 100

    let links: FrameLinks

    var state: FrameState
    private var styleSnapshotCache: StyleSnapshot?
    private var styleSnapshotRevision: UInt64 = .max
    private var layoutInputsKey: LayoutInputsKey?
    private var layoutInFlight: Bool = false
    /// Set when the document changes while a background pass runs. A viewport
    /// change does not set it; the pass's `LayoutJobKey` already records that.
    private var layoutInFlightDirty: Bool = false
    /// True when the running pass reused the installed tree's inputs: the
    /// document has not changed, and the pass only moves the viewport.
    private var layoutJobMovesViewportOnly: Bool = false
    private var layoutJobID: UInt = 0
    private var layoutJobKey: LayoutJobKey?
    /// The viewport moved since the last pass started. The next pass marks
    /// the document geometry dirty on the tree it lays out; the installed tree
    /// is never marked, so it stays paintable while that pass runs.
    private var viewportGeometryPending: Bool = false
    private var layoutSize: CGSize = .zero
    private(set) var paintedLayoutSize: CGSize = .zero

    var tab: BrowserTab? { links.tab }
    var parentFrame: Frame? { tab?.frame(links.parent) }
    var frameElement: NodeID? { links.element }
    var windowID: Int { links.id.raw }

    var url: WebURL! { state.document.meta.url }
    var dom: DOMTree { state.document.dom }
    var nodes: DOMRef { DOMRef(id: dom.root, dom: dom) }

    func setURL(_ newURL: WebURL) {
        state.document.meta.url = newURL
    }

    /// The one path that swaps the document. Layout and display state point at
    /// the old tree, so they are reset here instead of in a property observer.
    func replaceDOM(_ newDOM: DOMTree) {
        guard dom !== newDOM else { return }
        newDOM.links.tab = tab
        state.document.dom = newDOM
        styleSnapshotCache = nil
        styleSnapshotRevision = .max
        layoutInputsKey = nil
        state.layout.tree.box = nil
        state.layout.tree.isDirty = true
        state.layout.targets = ScrollTargetState()
        state.runtime.interaction.scrollFocus = nil
        state.display.composite.updates.removeAll()
        state.runtime.schedule.needsRender = true
        state.display.paint.isNeeded = true
    }

    /// Replacing a sheet invalidates the sorted index and the `:has` precompute.
    func setStyleRules(_ newRules: [RuleIndex.Rule]) {
        state.document.sheets.rules = newRules
        state.document.sheets.index.list.rulesRevision += 1
        state.document.sheets.pending.needsHasPrecompute = true
    }

    func appendStyleRules(_ newRules: [RuleIndex.Rule]) {
        state.document.sheets.rules.append(contentsOf: newRules)
        state.document.sheets.index.list.rulesRevision += 1
        state.document.sheets.pending.needsHasPrecompute = true
    }

    func mergeKeyframes(_ newFrames: [String: [Keyframe]]) {
        state.document.sheets.keyframes.merge(newFrames) { _, new in new }
    }

    /// Width and height change together on resize; only a width change dirties
    /// the document's available width.
    func setViewport(width: CGFloat, height: CGFloat) {
        let oldWidth: CGFloat = state.layout.viewport.width
        state.layout.viewport.width = width
        state.layout.viewport.height = height
        if oldWidth != width {
            viewportGeometryPending = true
        }
    }

    func clearPaintRequest() {
        state.display.paint.isNeeded = false
    }

    func setScroll(_ offset: CGFloat) {
        state.layout.scroll.offset = offset
    }

    func setJSRuntime(_ runtime: JSRuntime?) {
        state.runtime.script = runtime
    }
    var document: LayoutTree? { state.layout.tree.box?.tree }

    /// Borrows the layout tree for a direct mutation (tests, tools).
    func withLayoutTree(_ body: (inout LayoutTree) -> Void) {
        guard let box: LayoutBox = state.layout.tree.box else { return }
        body(&box.tree)
    }

    func setLayoutTree(_ tree: LayoutTree?) {
        state.layout.tree.box = tree.map({ LayoutBox($0) })
        state.layout.tree.isDirty = false
        dom.layoutBox = state.layout.tree.box
    }
    private func applyLayoutEffects(_ effects: [LayoutEffect]) {
        for effect in effects {
            switch effect {
            case .iframeViewport(let node, let width, let height):
                guard let frame: Frame = DOMRef(id: node, dom: dom).element?.frame,
                    frame.loaded
                else { continue }
                if frame.frameWidth != width {
                    frame.setViewport(width: width, height: height)
                    frame.setNeedsRender()
                } else if frame.frameHeight != height {
                    frame.setViewport(width: width, height: height)
                    frame.setNeedsLayout()
                }
            case .canvasSize(let node, let width, let height, let scale):
                guard let context: CanvasRenderingContext2D = DOMRef(id: node, dom: dom)
                    .element?.canvasContext
                else { continue }
                context.resize(width: width, height: height)
                context.setScale(scale)
            }
        }
    }

    var displayList: [DisplayOp] { state.display.paint.ops }
    // Bumped when anything that paint reads may have changed.
    // One epoch covers many paints; a cached item is valid only in its epoch.
    var paintEpoch: UInt { state.display.paint.epoch }
    var paintCaches: PaintCacheStore {
        get { state.display.caches }
        set { state.display.caches = newValue }
    }
    var title: String { state.document.meta.title }
    var isSecure: Bool { state.document.meta.isSecure }

    var scroll: CGFloat { state.layout.scroll.offset }
    var frameWidth: CGFloat { state.layout.viewport.width }
    var frameHeight: CGFloat { state.layout.viewport.height }
    var loaded: Bool { state.document.meta.loaded }

    private(set) var focus: NodeID? {
        get { state.runtime.interaction.focus }
        set { state.runtime.interaction.focus = newValue }
    }
    var js: JSRuntime! { state.runtime.script }
    var interestTop: CGFloat { state.layout.scroll.interestTop }
    private var interestBottom: CGFloat {
        return state.layout.scroll.interestTop + 4 * state.layout.viewport.height
    }
    private(set) var pageZoom: CGFloat {
        get { state.layout.viewport.zoom }
        set { state.layout.viewport.zoom = newValue }
    }


    func markStructureChanged() {
        state.layout.targets.needsRebuild = true
    }

    var hasScrollElement: Bool { state.runtime.interaction.scrollFocus != nil }

    var maxScroll: CGFloat {
        let documentHeight: CGFloat = document.map({ $0.heightIfUsed(at: $0.rootID) ?? 0 }) ?? 0
        let padded: CGFloat = documentHeight + 2 * VSTEP
        return max(max(padded, state.display.painted.bottom + VSTEP) - frameHeight, 0)
    }

    private var browser: Browser? { tab?.browser }

    init(
        tab: BrowserTab,
        parentID: FrameID?,
        element: NodeID?,
        frameWidth: CGFloat,
        frameHeight: CGFloat
    ) {
        let id: FrameID = tab.reserveFrameID()
        self.links = FrameLinks(
            tab: tab,
            id: id,
            parent: parentID,
            element: element
        )
        self.state = FrameState(
            document: FrameDocumentState(dom: DOMTree()),
            layout: FrameLayoutState(width: frameWidth, height: frameHeight),
            display: FrameDisplayState(),
            runtime: FrameRuntimeState()
        )
        self.state.document.dom.links.tab = tab
        tab.registerFrame(self)
    }

    private func requestAnimationFrame() {
        if let tab { tab.browser?.setNeedsAnimationFrame(tab) }
    }

    // MARK: - Load

    func load(_ url: WebURL, payload: String? = nil) {
        guard let networkTaskRunner = tab?.networkTaskRunner else { return }
        let referrer: WebURL? = effectiveReferrer(for: url)

        Task {
            self.browser?.measure.start("BrowserTab.load")
            defer { self.browser?.measure.stop("BrowserTab.load") }

            self.browser?.measure.start("BrowserTab.load.page")
            let result: Result<(status: Int, headers: [String : String], content: String), any Error> =
                await networkTaskRunner.schedule(name: "load\(url.toString())") {
                    await self.fetchPage(url: url, referrer: referrer, payload: payload)
                }
            self.browser?.measure.stop("BrowserTab.load.page")

            self.browser?.measure.start("BrowserTab.load.parseHTML")
            profiler.reset()
            let parsedPage: ResourceLoads? = self.parseHTML(url: url, result: result)
            self.browser?.measure.stop("BrowserTab.load.parseHTML")
            profiler.emitProfile(into: self.browser?.measure, named: "profile.load")
            guard let resources = parsedPage else { return }

            self.browser?.measure.start("BrowserTab.load.styles")
            let styleBodies: [(index: Int, body: String)] = await networkTaskRunner.schedule(name: "fetch-styles") {
                await self.fetchStyles(urls: resources.styleURLs)
            }
            self.browser?.measure.stop("BrowserTab.load.styles")

            self.browser?.measure.start("BrowserTab.load.applyStyles")
            self.applyStyles(bodies: styleBodies)
            self.browser?.measure.stop("BrowserTab.load.applyStyles")

            self.browser?.measure.start("BrowserTab.load.scripts")
            let scriptBodies: [(index: Int, url: WebURL, body: String)] = await networkTaskRunner.schedule(name: "fetch-scripts") {
                await self.fetchScripts(urls: resources.scriptURLs)
            }
            self.browser?.measure.stop("BrowserTab.load.scripts")

            self.browser?.measure.start("BrowserTab.load.images")
            let images: [(index: Int, image: CGImage?)] = await networkTaskRunner.schedule(name: "fetch-images") {
                await self.fetchImages(urls: resources.imageURLs)
            }
            self.applyImages(images)
            self.browser?.measure.stop("BrowserTab.load.images")

            self.browser?.measure.start("BrowserTab.load.iframes")
            self.syncIframes()
            self.browser?.measure.stop("BrowserTab.load.iframes")

            self.browser?.measure.start("BrowserTab.load.exec")
            self.execScripts(url: url, bodies: scriptBodies)
            self.browser?.measure.stop("BrowserTab.load.exec")

            self.js.dispatchWindowLoad()

            state.document.meta.loaded = true
        }
    }

    private func fetchPage(url: WebURL, referrer: WebURL?, payload: String?) async -> Result<
        (status: Int, headers: [String: String], content: String), Error
    > {
        do {
            return .success(try await url.request(referrer: referrer, payload: payload))
        } catch {
            return .failure(error)
        }
    }

    private func parseHTML(
        url: WebURL, result: Result<(status: Int, headers: [String: String], content: String), Error>
    ) -> ResourceLoads? {
        let certErrorCodes: [URLError.Code] = [
            .serverCertificateUntrusted, .serverCertificateHasBadDate,
            .serverCertificateNotYetValid, .serverCertificateHasUnknownRoot,
        ]

        switch result {
        case .failure(let error):
            if let urlError = error as? URLError, certErrorCodes.contains(urlError.code) {
                BrowserTab.showAlert("Certificate Error", "The certificate for \(url.host) is invalid. " + "Your connection may not be private.")
            }
            return nil

        case .success(let (_, headers, body)):
            state.document.meta.isSecure = url.scheme == "https"
            state.layout.scroll.offset = 0
            state.runtime.animation.tween = nil
            state.layout.scroll.interestTop = 0
            setURL(url)
            tab?.markVisited(url.toString())
            discardChildFrames()
            if let message = frameBlockMessage(headers: headers) {
                print("Blocked iframe", url.toString(), "due to X-Frame-Options")
                return showFrameBlockedPage(message)
            }
            replaceDOM(
                profiler.measure("load.parse", {
                    HTMLParser(body: body).parse()
                })
            )
            state.runtime.animation.activeCount = 0
            state.runtime.interaction.hovered.removeAll()

            profiler.measure("load.checkboxes", {
                for node in treeToList(nodes) {
                    if let el = node.element, el.tag == "input",
                        el.attributes["type"] == "checkbox"
                    {
                        el.isChecked = el.attributes["checked"] != nil
                    }
                }
            })

            state.runtime.script = profiler.measure("load.jsInit", { JSRuntime(frame: self) })

            let titleText: String = profiler.measure("load.title", {
                treeToList(nodes)
                .compactMap({ $0.element })
                .first(where: { $0.tag == "title" })?.children
                .compactMap({ $0.text })
                .map(\.text).joined()
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            })
            state.document.meta.title = titleText.isEmpty ? url.toString() : titleText

            state.document.resources.network.allowedOrigins = nil
            state.document.resources.network.referrerPolicy = headers["referrer-policy"] ?? ""
            if let csp = headers["content-security-policy"] {
                let parts: [String] = csp.split(separator: " ").map(String.init)
                if parts.first == "default-src" {
                    state.document.resources.network.allowedOrigins = parts.dropFirst().map {
                        WebURL($0).origin()
                    }
                }
            }

            setStyleRules(profiler.measure("load.defaultCss") { defaultStyleSheet })

            let (styleURLs, scriptURLs, imageURLs): ([ResourceLoad], [ResourceLoad], [ResourceLoad]) =
            profiler.measure("load.resources", {
                let elements: [ElementRef] = treeToList(nodes).compactMap({ $0.element })
                let styles: [ResourceLoad] = elements
                    .filter({ $0.tag == "link" && $0.attributes["rel"] == "stylesheet" && $0.attributes["href"] != nil })
                    .enumerated()
                    .map({ (i, link) in
                        let styleURL: WebURL = url.resolve(link.attributes["href"]!)
                        return (i, styleURL, self.effectiveReferrer(for: styleURL))
                    })
                let scripts: [ResourceLoad] = elements
                    .filter({ $0.tag == "script" && $0.attributes["src"] != nil })
                    .enumerated()
                    .map({ (i, node) in
                        let scriptURL: WebURL = url.resolve(node.attributes["src"]!)
                        return (i, scriptURL, self.effectiveReferrer(for: scriptURL))
                    })
                let imgs: [ElementRef] = elements.filter({ $0.tag == "img" })
                self.state.document.resources.images.lazy = imgs.filter({ ImageLoading(attributes: $0.attributes) == .lazy }).map(\.id)
                let images: [ResourceLoad] = imgs.enumerated()
                    .filter({ ImageLoading(attributes: $0.element.attributes) == .eager })
                    .map({ (i, img) in
                        let src: String = img.attributes["src"] ?? ""
                        let imageURL: WebURL = src.isEmpty ? url : url.resolve(src)
                        return (i, imageURL, self.effectiveReferrer(for: imageURL))
                    })
                return (styles, scripts, images)
            })

            return ResourceLoads(styleURLs: styleURLs, scriptURLs: scriptURLs, imageURLs: imageURLs)
        }
    }

    private func fetchStyles(
        urls: [(index: Int, url: WebURL, ref: WebURL?)]
    ) async -> [(index: Int, body: String)] {
        typealias Response = (status: Int, headers: [String: String], content: String)
        var result: [(index: Int, body: String)] = []
        var allowed: [ResourceLoad] = []
        for entry in urls {
            guard allowedRequest(entry.url) else {
                print("Blocked style", entry.url.toString(), "due to CSP")
                continue
            }
            allowed.append(entry)
        }
        await withTaskGroup(of: (Int, WebURL, Response?).self) { group in
            for (i, styleURL, ref) in allowed {
                group.addTask {
                    return (i, styleURL, try? await styleURL.request(referrer: ref))
                }
            }
            for await (i, styleURL, response) in group {
                guard let response,
                    BrowserTab.isUsableStylesheet(status: response.status, headers: response.headers, url: styleURL)
                else { continue }
                result.append((i, response.content))
            }
        }
        return result
    }

    private func applyStyles(bodies: [(index: Int, body: String)]) {
        for (_, body) in bodies.sorted(by: { $0.index < $1.index }) {
            let parsed: (rules: [(String?, any CSSSelector, [String : String])], keyframes: [String : [Keyframe]]) = CSSParser(body).parse()
            appendStyleRules(parsed.rules)
            mergeKeyframes(parsed.keyframes)
        }

        for styleNode in treeToList(nodes).compactMap({ $0.element }).filter({
            $0.tag == "style"
        }) {
            let css: String = styleNode.children.compactMap({ $0.text }).map(\.text).joined()
            let parsed: (rules: [(String?, any CSSSelector, [String : String])], keyframes: [String : [Keyframe]]) = CSSParser(css).parse()
            appendStyleRules(parsed.rules)
            mergeKeyframes(parsed.keyframes)
        }
    }

    private func fetchScripts(
        urls: [(index: Int, url: WebURL, ref: WebURL?)]
    ) async -> [(index: Int, url: WebURL, body: String)] {
        typealias Response = (status: Int, headers: [String: String], content: String)
        var result: [(index: Int, url: WebURL, body: String)] = []
        var allowed: [ResourceLoad] = []
        for entry in urls {
            guard allowedRequest(entry.url) else {
                print("Blocked script", entry.url.toString(), "due to CSP")
                continue
            }
            allowed.append(entry)
        }
        await withTaskGroup(of: (Int, WebURL, Response?).self) { group in
            for (i, scriptURL, ref) in allowed {
                group.addTask {
                    return (i, scriptURL, (try? await scriptURL.request(referrer: ref)))
                }
            }
            for await (i, scriptURL, response) in group {
                guard let response,
                    BrowserTab.isExecutableScript(status: response.status, headers: response.headers, url: scriptURL)
                else { continue }
                result.append((i, scriptURL, response.content))
            }
        }
        return result
    }

    private func execScripts(
        url: WebURL,
        bodies: [(index: Int, url: WebURL, body: String)]
    ) {
        for (_, scriptURL, body) in bodies.sorted(by: { $0.index < $1.index }) {
            js.run(script: scriptURL.toString(), code: body)
            state.document.resources.loadedScripts.insert(scriptURL.toString())
        }

        js.defineIDs()

        for scriptNode in treeToList(nodes).compactMap({ $0.element })
            .filter({ $0.tag == "script" && $0.attributes["src"] == nil })
        {
            let code: String = scriptNode.children.compactMap({ $0.text }).map(\.text).joined()
            if !code.isEmpty { js.run(script: "inline", code: code) }
        }

        setNeedsRender()

        if let fragment = url.fragment {
            scrollToFragment(fragment)
        }
    }

    private func fetchImages(
        urls: [(index: Int, url: WebURL, ref: WebURL?)]
    ) async -> [(index: Int, image: CGImage?)] {
        var result: [(index: Int, image: CGImage?)] = []
        var allowed: [ResourceLoad] = []
        for entry in urls {
            guard allowedRequest(entry.url) else {
                print("Blocked image", entry.url.toString(), "due to CSP")
                continue
            }
            allowed.append(entry)
        }
        await withTaskGroup(of: (Int, CGImage?).self) { group in
            for (i, imageURL, ref) in allowed {
                group.addTask(operation: {
                    return await (i, self.decodeImage(url: imageURL, referrer: ref))
                })
            }
            for await (i, image) in group {
                result.append((index: i, image: image))
            }
        }
        return result
    }

    private nonisolated func decodeImage(url: WebURL, referrer: WebURL?) async -> CGImage? {
        guard let (_, _, data) = try? await url.requestRawBytes(referrer: referrer),
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let decoded = CGImageSourceCreateImageAtIndex(source, 0, nil)
            else {
            return nil
        }
        return decoded
    }

    private func applyImages(_ images: [(index: Int, image: CGImage?)]) {
        let elements: [ElementRef] = treeToList(nodes).compactMap({ $0.element })
        let imgs: [ElementRef] = elements.filter({ $0.tag == "img" })
        for (i, image) in images where i < imgs.count {
            imgs[i].image = image ?? BrokenImage.replacement(for: imgs[i].attributes)
            LayoutInvalidation.imageChanged(imgs[i].ref)
        }
    }

    private func loadLazyImages() {
        guard let tab, let runner = tab.networkTaskRunner, let base = url else { return }
        let region: ImageLoadingRegion = ImageLoadingRegion(
            scroll: scroll,
            viewportHeight: frameHeight,
            margin: frameHeight
        )
        var remaining: [NodeID] = []
        for id in state.document.resources.images.lazy {
            let ref: DOMRef = DOMRef(id: id, dom: dom)
            guard let el = ref.element, el.image == nil,
                let tree: LayoutTree = ref.dom.layoutBox?.tree,
                let layoutID: LayoutID = ref.layoutID,
                region.contains(tree.absoluteBounds(layoutID))
            else {
                remaining.append(id)
                continue
            }
            let src: String = el.attributes["src"] ?? ""
            let imageURL: WebURL = src.isEmpty ? base : base.resolve(src)
            guard allowedRequest(imageURL) else { continue }
            let referrer: WebURL? = effectiveReferrer(for: imageURL)
            Task { @MainActor in
                let image: CGImage? = await runner.schedule(name: "lazy-image", {
                    await self.decodeImage(url: imageURL, referrer: referrer)
                })
                guard let el = ref.element else { return }
                el.image = image ?? BrokenImage.replacement(for: el.attributes)
                LayoutInvalidation.imageChanged(ref)
                self.setNeedsLayout()
            }
        }
        state.document.resources.images.lazy = remaining
    }

    private func loadBackgroundImages(_ nodes: [DOMRef]) {
        guard let tab, let runner = tab.networkTaskRunner, let base = url else { return }

        var order: [String] = []
        var urlByKey: [String: WebURL] = [:]
        var elementsByKey: [String: [ElementRef]] = [:]

        for node in nodes {
            guard let el = node.element,
                let raw: String = el.style.computed.visual.background.image
            else { continue }

            if el.backgroundImageSource != raw {
                el.backgroundImage = nil
                el.backgroundImageSource = raw
            }

            let resolved: WebURL = base.resolve(raw)
            guard allowedRequest(resolved) else { continue }
            let key: String = resolved.toString()
            if urlByKey[key] == nil {
                order.append(key)
                urlByKey[key] = resolved
            }
            elementsByKey[key, default: []].append(el)
        }

        for key in order {
            let elements: [ElementRef] = elementsByKey[key] ?? []
            if let cached: CGImage = state.document.resources.images.backgroundCache[key] {
                for el in elements { el.backgroundImage = cached }
                continue
            }
            guard !state.document.resources.images.requestedBackgrounds.contains(key), let resolved = urlByKey[key] else {
                continue
            }
            state.document.resources.images.requestedBackgrounds.insert(key)
            let referrer: WebURL? = effectiveReferrer(for: resolved)
            Task { @MainActor in
                let image: CGImage? = await runner.schedule(name: "bg-image", {
                    await self.decodeImage(url: resolved, referrer: referrer)
                })
                guard let image else { return }
                self.state.document.resources.images.backgroundCache[key] = image
                for el in elements { el.backgroundImage = image }
                self.setNeedsPaint()
            }
        }
    }

    func syncIframes() {
        guard let tab else { return }

        var live: Set<NodeID> = []
        for node in treeToList(nodes) {
            guard let iframe = node.element, iframe.tag == "iframe" else { continue }
            guard let src = iframe.attributes["src"] else {
                unloadIframe(iframe)
                continue
            }
            let documentURL: WebURL = url.resolve(src)
            guard allowedRequest(documentURL) else {
                print("Blocked iframe", documentURL.toString(), "due to CSP")
                unloadIframe(iframe)
                continue
            }
            live.insert(iframe.id)
            if iframe.frame != nil, iframe.frameSource != src {
                unloadIframe(iframe)
            }
            if iframe.frame == nil {
                loadIframe(iframe, documentURL: documentURL, source: src)
            }
        }

        let children: [Frame] = tab.allFrames.filter({ $0.links.parent == links.id })
        for child in children {
            guard let el = child.frameElement, live.contains(el) else {
                unload(child)
                continue
            }
        }
    }

    private func loadIframe(_ iframe: ElementRef, documentURL: WebURL, source: String) {
        guard let tab else { return }
        markStructureChanged()
        let child: Frame = Frame(
            tab: tab,
            parentID: links.id,
            element: iframe.id,
            frameWidth: 0,
            frameHeight: 0
        )
        child.pageZoom = pageZoom
        iframe.frame = child
        iframe.frameSource = source
        child.load(documentURL)
    }

    private func unloadIframe(_ iframe: ElementRef) {
        guard let child = iframe.frame else { return }
        markStructureChanged()
        unload(child)
    }

    private func unload(_ frame: Frame) {
        if let element = frame.frameElement, let parentDOM = frame.parentFrame?.dom {
            parentDOM.side.embeds.frames.removeValue(forKey: element)
            parentDOM.side.embeds.frameSources.removeValue(forKey: element)
        }
        frame.discardChildFrames()
        tab?.removeFrame(frame.links.id)
        if let tab, tab.frame(tab.focusedFrameID) == nil {
            tab.setFocusedFrame(self)
        }
    }

    private func discardChildFrames() {
        guard let tab else { return }
        let children: [Frame] = tab.allFrames.filter({ $0.links.parent == links.id })
        for child in children {
            child.discardChildFrames()
            tab.removeFrame(child.links.id)
        }
        if tab.frame(tab.focusedFrameID) == nil {
            tab.setFocusedFrame(self)
        }
    }

    private func effectiveReferrer(for targetURL: WebURL) -> WebURL? {
        switch state.document.resources.network.referrerPolicy {
        case "no-referrer":
            return nil
        case "same-origin":
            return url?.origin() == targetURL.origin() ? url : nil
        default:
            return url
        }
    }

    func allowedRequest(_ url: WebURL) -> Bool {
        state.document.resources.network.allowedOrigins == nil || (state.document.resources.network.allowedOrigins?.contains(url.origin()) ?? false)
    }

    private func frameBlockMessage(headers: [String: String]) -> String? {
        guard let parentFrame else { return nil }
        let options: XFrameOptions = XFrameOptions(header: headers["x-frame-options"])

        var ancestorOrigins: [String] = []
        var ancestor: Frame? = parentFrame
        while let frame = ancestor {
            ancestorOrigins.append(frame.url.origin())
            ancestor = frame.parentFrame
        }

        guard !options.allowsEmbedding(documentOrigin: url.origin(), ancestorOrigins: ancestorOrigins)
            else { return nil }

        return "This content is blocked. Visit \(url.origin()) to view it."
    }

    private func showFrameBlockedPage(_ message: String) -> ResourceLoads {
        replaceDOM(
            HTMLParser(body: """
                <html>
                <body><p>\(message)</p></body>
                </html>
                """).parse()
        )
        state.runtime.script = JSRuntime(frame: self)
        state.document.meta.title = "Blocked"
        state.document.resources.network.allowedOrigins = nil
        state.document.resources.network.referrerPolicy = ""
        setStyleRules(defaultStyleSheet)
        return ResourceLoads(styleURLs: [], scriptURLs: [], imageURLs: [])
    }

    func runNewScripts(in root: DOMRef) {
        for node in treeToList(root) {
            guard let el = node.element, el.tag == "script",
                let src = el.attributes["src"]
            else { continue }
            let scriptURL: WebURL = url.resolve(src)
            guard allowedRequest(scriptURL) else {
                print("Blocked script", src, "due to CSP")
                continue
            }
            let urlStr: String = scriptURL.toString()
            guard !state.document.resources.loadedScripts.contains(urlStr) else { continue }
            guard let (status, headers, body) = scriptURL.requestSync() else { continue }
            guard BrowserTab.isExecutableScript(status: status, headers: headers, url: scriptURL) else { continue }
            state.document.resources.loadedScripts.insert(urlStr)
            js.run(script: urlStr, code: body)
        }
    }

    func reloadStylesheets() {
        setStyleRules(defaultStyleSheet)
        for node in treeToList(nodes) {
            guard let el = node.element else { continue }
            if el.tag == "link", el.attributes["rel"] == "stylesheet",
                let href = el.attributes["href"]
            {
                let styleURL: WebURL = url.resolve(href)
                guard allowedRequest(styleURL) else { continue }
                guard let (status, headers, body) = styleURL.requestSync() else { continue }
                guard BrowserTab.isUsableStylesheet(status: status, headers: headers, url: styleURL) else { continue }
                let parsed: (rules: [(String?, any CSSSelector, [String : String])], keyframes: [String : [Keyframe]]) = CSSParser(body).parse()
                appendStyleRules(parsed.rules)
                mergeKeyframes(parsed.keyframes)
            }
            if el.tag == "style" {
                let css: String = el.children.compactMap({ $0.text }).map(\.text).joined()
                let parsed: (rules: [(String?, any CSSSelector, [String : String])], keyframes: [String : [Keyframe]]) = CSSParser(css).parse()
                appendStyleRules(parsed.rules)
                mergeKeyframes(parsed.keyframes)
            }
        }
        StyleInvalidation.markDocument(nodes)
    }

    // MARK: - Render

    var isLayoutInFlight: Bool { layoutInFlight }
    var installedLayoutSize: CGSize { layoutSize }
    var needsPaint: Bool { state.display.paint.isNeeded }

    /// True while a background pass runs for a document that changed since
    /// the installed tree was built. A pass that only moves the viewport
    /// leaves the installed tree a valid picture of the document, so the tab
    /// may keep painting it.
    var layoutBlocksPaint: Bool {
        return layoutInFlight && (!layoutJobMovesViewportOnly || layoutInFlightDirty)
    }

    func render() {
        if !state.document.sheets.pending.counters.isEmpty {
            browser?.measure.counter("style.invalidation", state.document.sheets.pending.counters)
            state.document.sheets.pending.counters.removeAll(keepingCapacity: true)
        }
        let viewportStyle: Bool = state.document.sheets.pending.byViewport
        let reusableStyle: Bool = viewportStyle
        var layoutChanged: Bool = false
        state.document.sheets.pending.byViewport = false
        state.document.sheets.pending.byOther = false
        let stylesDirty: Bool = nodes.style.isDirty || nodes.style.hasDirtyDescendant
        if stylesDirty || viewportStyle {
            browser?.measure.start("BrowserTab.style")
            profiler.reset()
            defer { profiler.emitProfile(into: browser?.measure, named: "profile.style") }
            defer { browser?.measure.stop("BrowserTab.style") }

            browser?.measure.start("BrowserTab.style.rules")
            if state.document.sheets.index.list.indexedRevision != state.document.sheets.index.list.rulesRevision {
                state.document.sheets.index.list.sorted = state.document.sheets.rules.sorted(by: { cascadePriority($0) < cascadePriority($1) })
                state.document.sheets.index.list.index = RuleIndex(rules: state.document.sheets.index.list.sorted)
                state.document.sheets.index.media.queries = Set(state.document.sheets.index.list.sorted.compactMap({ $0.0 }))
                state.document.sheets.index.list.indexedRevision = state.document.sheets.index.list.rulesRevision
                profiler.count("style.rules", by: state.document.sheets.index.list.sorted.count)
            }
            browser?.measure.stop("BrowserTab.style.rules")

            browser?.measure.start("BrowserTab.style.has")
            if state.document.sheets.pending.needsHasPrecompute {
                precomputeHas(node: nodes, rules: state.document.sheets.index.list.sorted)
                state.document.sheets.pending.needsHasPrecompute = false
            }
            browser?.measure.stop("BrowserTab.style.has")

            browser?.measure.start("BrowserTab.style.apply")
            let media: MediaFeatures = currentMedia()
            let flipped: Set<String> = flippedMediaQueries(media)
            recordMediaMatches(media)
            browser?.measure.start("BrowserTab.style.scope")
            let scoped: (scope: StyleScope?, snapshot: StyleSnapshot?) =
                reusableStyle ? scopedStyleScope(flipped) : (nil, nil)
            let scope: StyleScope? = scoped.scope
            profiler.count(scope == nil ? "style.scope.none" : "style.scope.used")
            browser?.measure.stop("BrowserTab.style.scope")
            profiler.count("style.flipped.queries", by: flipped.count)
            profiler.count("style.scope.direct", by: scope?.direct.count ?? 0)
            let cascade: StyleCascade = StyleCascade(
                index: state.document.sheets.index.list.index,
                media: media,
                scope: scope
            )
            if scope?.isEmpty != true || stylesDirty {
                let snapshot: StyleSnapshot = scoped.snapshot ?? cachedStyleSnapshot()
                applyStyle(node: nodes, cascade: cascade, snapshot: snapshot)
            }
            profiler.count("style.applied", by: cascade.appliedNodes.count)
            StyleDiagnostics.begin(
                width: frameWidth,
                viewport: viewportStyle,
                flipped: flipped.count,
                applied: cascade.appliedNodes.count
            )
            browser?.measure.stop("BrowserTab.style.apply")

            browser?.measure.start("BrowserTab.style.diff")
            let animationsBefore: Int = cascade.appliedNodes.reduce(0) { $0 + $1.animations.count }
            var paintedChanged: Bool = false
            // One trace event per tag, written after the loop: a breakpoint
            // flip changes thousands of nodes and one event each slowed the pass.
            var fontChangesByTag: [String: Int] = [:]
            for node in cascade.appliedNodes {
                guard let old: ComputedStyle = cascade.oldStyle(for: node) else { continue }
                if old.text.font.size != node.style.computed.text.font.size {
                    StyleDiagnostics.fontChange(
                        node: node,
                        from: old.text.font.size,
                        to: node.style.computed.text.font.size
                    )
                    fontChangesByTag[node.element?.tag ?? "text", default: 0] += 1
                }
                if Self.paintStyleChanged(old: old, new: node.style.computed) {
                    paintedChanged = true
                }
                if node.style.hasLayoutChanges {
                    layoutChanged = true
                }
                // Scroll targets are collected by layout class and computed overflow.
                // A style-only change to either changes the target set, not just rects.
                if old.layout.display != node.style.computed.layout.display
                    || old.layout.overflow != node.style.computed.layout.overflow
                {
                    markStructureChanged()
                }
                let newAnimations: [StyleProperty: any Animation] = StyleTransitions.diff(
                    node: node,
                    oldStyle: old,
                    newStyle: node.style.computed
                )
                for (property, animation) in newAnimations {
                    node.animations[.property(property)] = animation
                }
            }
            for (tag, count) in fontChangesByTag {
                browser?.measure.counter("style.font-size.changed.\(tag)", ["count": count])
            }
            if paintedChanged {
                // The paint caches are keyed by the changed node's style
                // revision, so one element's colour change no longer has to
                // invalidate every block and line on the page.
                state.display.paint.isNeeded = true
            }
            browser?.measure.stop("BrowserTab.style.diff")

            browser?.measure.start("BrowserTab.style.keyframes")
            if !state.document.sheets.keyframes.isEmpty {
                for node in cascade.appliedNodes {
                    guard let animDecl = node.style.unknownValue("animation"),
                        let playback = KeyframePlayback.parse(animDecl),
                        let frames = state.document.sheets.keyframes[playback.name]
                    else { continue }
                    let key: AnimationKey = .keyframes(playback.name)
                    guard node.animations[key] == nil else { continue }
                    if let anim = KeyframeAnimation.make(frames: frames, playback: playback)
                    {
                        node.animations[key] = anim
                    }
                }
            }
            browser?.measure.stop("BrowserTab.style.keyframes")

            state.runtime.animation.activeCount += cascade.appliedNodes.reduce(0) { $0 + $1.animations.count } - animationsBefore

            browser?.measure.start("BrowserTab.style.visited")
            if tab?.hasVisitedURLs == true {
                for node in cascade.appliedNodes {
                    guard let el = node.element, el.tag == "a",
                        let href = el.attributes["href"]
                    else {
                        continue
                    }
                    if tab?.hasVisited(url.resolve(href).toString()) == true {
                        let color: BrowserColor = BrowserColor(
                            cssName: (tab?.forcedColors ?? false) ? ForcedColor.visitedText : "purple"
                        )
                        el.style.mutate { $0.text.color = color }
                    }
                }
            }
            browser?.measure.stop("BrowserTab.style.visited")

            loadBackgroundImages(cascade.appliedNodes)
            emitStyleProfileCounters()
        }

        if state.layout.tree.isDirty && !layoutChanged && !viewportStyle
            && !state.layout.tree.forced && !viewportGeometryPending,
            state.layout.tree.box?.tree.documentNeedsLayout(counting: false) == false
        {
            // The pass was scheduled by a style change that only touches paint.
            state.layout.tree.isDirty = false
            state.layout.tree.forced = false
        }

        if state.layout.tree.isDirty, browser?.usesAsyncLayout == true {
            if !layoutInFlight {
                startAsyncLayout(stylesDirty: stylesDirty, viewportStyle: viewportStyle)
            }
            return
        }

        if state.layout.tree.isDirty {
            browser?.measure.start("BrowserTab.layout")
            profiler.reset()
            defer { profiler.emitProfile(into: browser?.measure, named: "profile.layout") }
            defer { browser?.measure.stop("BrowserTab.layout") }
            let inputs: LayoutInputs = resolveLayoutInputs(
                stylesDirty: stylesDirty,
                viewportStyle: viewportStyle,
                incremental: true
            ).inputs
            let box: LayoutBox = profiler.measure("layout.prepare", {
                let box: LayoutBox
                if let existing = state.layout.tree.box, existing.tree.dom === dom,
                    browser?.forceFullLayout != true
                {
                    box = existing
                } else {
                    box = LayoutBox(LayoutTree(
                        dom: dom,
                        root: dom.root,
                        inputs: inputs
                    ))
                    state.layout.targets.isValid = false
                }
                state.layout.tree.box = box
                dom.layoutBox = box
                box.tree.refreshInputs(inputs)
                if viewportGeometryPending {
                    box.tree.markDocumentGeometryDirty()
                    viewportGeometryPending = false
                }
                return box
            })
            profiler.measure("layout.document", {
                box.tree.layoutDocument(
                    availableWidth: frameWidth,
                    zoom: 1.0,
                    pageZoom: pageZoom
                )
            })
            layoutSize = CGSize(width: frameWidth, height: frameHeight)
            profiler.measure("layout.effects", {
                applyLayoutEffects(box.tree.takeEffects())
            })
            let removed: Set<LayoutID>
            if box.tree.needsSweep {
                removed = profiler.measure("layout.sweep", {
                    box.tree.sweepUnreachable()
                })
            } else {
                profiler.count("layout.sweep.skipped")
                removed = []
            }
            if !removed.isEmpty {
                state.display.composite.updates = state.display.composite.updates
                    .filter({ box.tree.primaryLayout(for: $0.key) != nil })
                state.display.caches.prune(removing: removed)
            }
            if state.layout.targets.iframes.contains(where: { removed.contains($0.layout) })
                || state.layout.targets.blocks.contains(where: { removed.contains($0.layout) })
            {
                state.layout.targets.isValid = false
                state.layout.targets.needsRebuild = true
            }
            state.layout.tree.isDirty = false
            state.layout.tree.forced = false
            #if DEBUG
            if state.runtime.schedule.debugDumpDependencies {
                dumpDependencies(box.tree, box.tree.rootID)
            }
            #endif
            browser?.measure.start("BrowserTab.rebuildScrollTargets")
            if state.layout.targets.needsRebuild || !state.layout.targets.isValid {
                rebuildScrollTargets(box.tree)
                state.layout.targets.isValid = true
                state.layout.targets.needsRebuild = false
                profiler.count("scrollTargets.rebuilt")
            } else {
                refreshScrollTargetRects()
                profiler.count("scrollTargets.reused")
            }
            browser?.measure.stop("BrowserTab.rebuildScrollTargets")

            tab?.needsAccessibility = true
            state.display.paint.isNeeded = true
        }

        resolveHover()

        requestAnimationFrame()
    }

    private static func paintStyleChanged(
        old: ComputedStyle,
        new: ComputedStyle
    ) -> Bool {
        return StyleProperty.paintStyle.contains {
            !old.matches(new, for: $0)
        }
    }

    private func windowForScroll() -> PaintWindow {
        let overscan: CGFloat = 2 * frameHeight
        return PaintWindow(
            top: scroll - overscan,
            bottom: scroll + frameHeight + overscan
        )
    }

    private func viewportFitsInPaintedWindow() -> Bool {
        let window: PaintWindow = state.display.painted.window
        guard window != .full else { return true }

        let margin: CGFloat = frameHeight / 2
        return scroll >= window.top + margin
            && scroll + frameHeight <= window.bottom - margin
    }

    func paint() {
        paint(window: windowForScroll())
    }

    func paint(window: PaintWindow) {
        guard state.display.paint.isNeeded else { return }

        state.display.painted.window = window

        browser?.measure.start("BrowserTab.paint")
        profiler.reset()
        defer {
            profiler.emitProfile(into: browser?.measure, named: "profile.paint")
            browser?.measure.stop("BrowserTab.paint")
        }
        guard let doc = document else { return }

        var list: [DisplayOp] = []
        list.reserveCapacity(state.display.paint.ops.count)
        var session: PaintSession = PaintSession(
            paint: state.display.paint.revision,
            epoch: state.display.paint.epoch,
            window: window
        )
        var builder: PaintSceneBuilder = PaintSceneBuilder()
        let rootFrame: Int = profiler.measure("paint.scene.build", {
            builder.build(root: doc.rootID, tree: doc, frame: self, window: window)
        })
        profiler.count(
            "paint.scene.nodes",
            by: builder.sink.scenes.reduce(0, { (total: Int, scene: PaintFrame) -> Int in
                total + scene.nodes.count
            })
        )
        var pass: PaintPass = PaintPass(
            scene: PaintScene(frames: builder.sink.scenes),
            caches: builder.sink.owners.map({ $0.paintCaches })
        )
        profiler.measure("paint.pass", {
            pass.paint(rootFrame, into: &list, session: &session)
        })
        profiler.count("paint.ops.count", by: list.count)

        for (index, owner) in builder.sink.owners.enumerated() where index != rootFrame {
            owner.paintCaches = pass.caches[index]
        }
        state.display.caches = pass.caches[rootFrame]

        state.display.paint.ops = list
        state.display.painted.bottom = contentBottom
        state.display.paint.revision += 1
        state.display.paint.isNeeded = false
    }

    private var contentBottom: CGFloat {
        return document.map({ $0.selfRect($0.rootID).bottom }) ?? 0
    }

    func runAnimationFrame() {
        guard js != nil else { return }
        browser?.measure.start("BrowserTab.animFrame")
        defer { browser?.measure.stop("BrowserTab.animFrame") }
        browser?.measure.start("BrowserTab.raf")
        js.run(script: "raf", code: "__runRAFHandlers()")
        browser?.measure.stop("BrowserTab.raf")
        var needsAnotherFrame: Bool = false
        state.display.composite.isNeeded = nodes.style.isDirty || state.layout.tree.isDirty || state.display.paint.isNeeded
        var needsLayoutUpdate: Bool = false
        var animationFallbacks: Int = 0
        browser?.measure.start("BrowserTab.animScan")
        let animated: [DOMRef] = state.runtime.animation.activeCount > 0 ? treeToList(nodes) : []
        for node in animated {
            for (key, animation) in node.animations {
                let property: StyleProperty = animation.animatedProperty
                if let value = animation.nextValue() {
                    needsAnotherFrame = true
                    node.style.set(value, for: property)
                    if property.affectsLayout {
                        state.layout.tree.box?.tree.noteStyleChange(node.id, property)
                        state.layout.tree.box?.tree.consumeStyleChanges(for: node.id)
                    }
                    if property == .transform || property == .opacity {
                        if let doc = document, let layoutID = node.layoutID,
                            doc.isBlock(layoutID),
                            let style: PaintEffectStyle = paintEffectStyle(
                                node.style.computed,
                                animated: node.animations[.property(.transform)] != nil
                                    || node.animations[.property(.opacity)] != nil
                            )
                        {
                            state.display.composite.updates[node.id] = EffectUpdate(
                                style: style,
                                isAnimatedTransform: node.animations[.property(.transform)] != nil
                            )
                        }
                    } else if property.affectsLayout {
                        if document?.documentNeedsLayout() == true {
                            needsLayoutUpdate = true
                        } else {
                            // A layout property that marked no field is a missing edge.
                            // Trap in debug; mark the nearest block in release so the
                            // page still updates instead of freezing on a stale layout.
                            assertionFailure("Animation for \(property.cssName) did not dirty a layout field")
                            LayoutInvalidation.animatedPropertyChanged(node, property: property)
                            needsLayoutUpdate = true
                            animationFallbacks += 1
                        }
                    } else {
                        state.display.composite.isNeededForPaint = true
                        state.display.paint.isNeeded = true
                    }
                } else {
                    if dom.removeAnimation(key, from: node.id) != nil { state.runtime.animation.activeCount -= 1 }
                    state.display.composite.isNeededForPaint = true
                    state.display.paint.isNeeded = true
                }
            }
        }
        browser?.measure.counter("layout.animation.fallback", ["nodes": animationFallbacks])
        browser?.measure.stop("BrowserTab.animScan")

        if state.display.paint.isNeeded {
            setNeedsPaint()
        }

        if needsLayoutUpdate {
            state.display.composite.isNeededForPaint = true
            setNeedsLayout()
        }

        if state.runtime.schedule.needsRender {
            state.runtime.schedule.needsRender = false
            inlineCacheProbe(self, "frame-before-render")
            render()
            inlineCacheProbe(self, "frame-after-render")

            if state.runtime.interaction.needsFocusScroll, let f = focus {
                scrollTo(dom.ref(f))
            }
            state.runtime.interaction.needsFocusScroll = false
        }

        if let tween = state.runtime.animation.tween {
            if let value = tween.nextValue() {
                state.layout.scroll.offset = max(0, min(value, maxScroll))
                needsAnotherFrame = true
                checkInterestRegion()
            } else {
                state.runtime.animation.tween = nil
            }
        }

        if !state.document.resources.images.lazy.isEmpty {
            loadLazyImages()
        }

        if needsAnotherFrame {
            requestAnimationFrame()
        }
    }

    /// Returns the inputs for the next layout pass. When nothing but the width
    /// changed, the previous inputs are still correct, so they are reused.
    private func resolveLayoutInputs(
        stylesDirty: Bool,
        viewportStyle: Bool,
        incremental: Bool
    ) -> (inputs: LayoutInputs, reused: Bool) {
        let previousInputs: LayoutInputs? = state.layout.tree.box?.tree.inputs
        let pendingChanges: Bool = !(previousInputs?.styleChanges.isEmpty ?? true)
        let keyChanged: Bool = layoutInputsKey.map({ key in
            key.dom != ObjectIdentifier(dom)
                || key.domRevision != dom.revision
                || key.imageRevision != dom.side.images.revision
                || key.styleRevision != StyleRevision.epoch
        }) ?? true
        var reusable: LayoutInputs?
        // Reused inputs carry their pending style changes into the background
        // job. The synchronous path stays strict.
        let blockedByPending: Bool = pendingChanges && incremental
        if !stylesDirty, !viewportStyle, !blockedByPending, !keyChanged, let previousInputs {
            reusable = previousInputs
            profiler.count("layout.inputs.reused", by: previousInputs.nodes.count)
        }
        // One event per job says why the inputs were rebuilt, if they were.
        browser?.measure.counter(
            "layout.inputs.decision",
            [
                "reused": reusable == nil ? 0 : 1,
                "stylesDirty": stylesDirty ? 1 : 0,
                "viewportStyle": viewportStyle ? 1 : 0,
                "pendingChanges": pendingChanges ? 1 : 0,
                "keyChanged": keyChanged ? 1 : 0,
            ]
        )
        let inputs: LayoutInputs = profiler.measure("layout.inputs.build", {
            if let reusable {
                return reusable
            }
            // The background path rebuilds every input; only the synchronous
            // path patches the previous ones.
            if !incremental {
                return LayoutInputsBuilder.build(dom: dom)
            }
            return LayoutInputsBuilder.build(
                dom: dom,
                previous: previousInputs,
                key: layoutInputsKey
            )
        })
        layoutInputsKey = LayoutInputsKey(
            dom: ObjectIdentifier(dom),
            domRevision: dom.revision,
            imageRevision: dom.side.images.revision,
            styleRevision: StyleRevision.epoch
        )
        return (inputs, reusable != nil)
    }

    /// Runs the layout pass on a background worker. The installed tree stays
    /// untouched for paint and hit testing; the completed tree replaces it.
    private func startAsyncLayout(stylesDirty: Bool, viewportStyle: Bool) {
        browser?.measure.start("layout.async.start")
        defer { browser?.measure.stop("layout.async.start") }
        layoutJobID &+= 1
        let jobID: UInt = layoutJobID
        layoutInFlight = true
        layoutInFlightDirty = false

        browser?.measure.start("layout.async.start.inputs")
        let resolved: (inputs: LayoutInputs, reused: Bool) = resolveLayoutInputs(
            stylesDirty: stylesDirty,
            viewportStyle: viewportStyle,
            incremental: false
        )
        browser?.measure.stop("layout.async.start.inputs")
        layoutJobMovesViewportOnly = resolved.reused
        browser?.measure.start("layout.async.start.tree")
        let box: LayoutBox
        if let existing: LayoutBox = state.layout.tree.box, existing.tree.dom === dom {
            box = existing
        } else {
            box = LayoutBox(LayoutTree(dom: dom, root: dom.root, inputs: resolved.inputs))
            state.layout.targets.isValid = false
        }
        state.layout.tree.box = box
        dom.layoutBox = box
        browser?.measure.stop("layout.async.start.tree")
        browser?.measure.start("layout.async.start.refresh")
        // The job gets its own copy. Only the inputs are replaced here; the
        // node storage stays shared until the worker writes to it, so the
        // geometry mark is applied there and the main thread copies nothing.
        var tree: LayoutTree = box.tree
        tree.refreshInputs(resolved.inputs)
        let handoff: LayoutJobHandoff = LayoutJobHandoff(consume tree)
        // The installed tree is only painted and hit-tested while the job
        // runs; neither reads the dependency index, and the job's tree replaces
        // it on install. Hand the index over so the job is its only owner and
        // its first write does not copy both dictionaries.
        box.tree.dependencies = DependencyIndex()
        let marksGeometry: Bool = viewportGeometryPending
        viewportGeometryPending = false
        browser?.measure.stop("layout.async.start.refresh")

        let width: CGFloat = frameWidth
        let pageZoom: CGFloat = self.pageZoom
        layoutJobKey = LayoutJobKey(
            size: CGSize(width: width, height: frameHeight),
            zoom: pageZoom
        )
        let measure: MeasureTime? = browser?.measure
        let jobFrame: Int? = measure?.frame
        Task.detached(priority: .userInitiated) { [handoff, marksGeometry, width, pageZoom, jobID, measure, jobFrame] in
            var tree: LayoutTree = handoff.take()
            // The detached task runs on a pooled thread; its own lane keeps the
            // layout off whatever lane that thread served before.
            let lane: TraceLane? = measure?.beginThreadLane("browser.layout")
            // This thread's profile window is the job's: the main thread keeps
            // its own windows for style and paint meanwhile.
            profiler.reset()
            if marksGeometry {
                tree.markDocumentGeometryDirty()
            }
            measure?.start("layout.async.document")
            tree.layoutDocument(availableWidth: width, zoom: 1.0, pageZoom: pageZoom)
            let effects: [LayoutEffect] = tree.takeEffects()
            let removed: Set<LayoutID> = tree.needsSweep ? tree.sweepUnreachable() : []
            measure?.stop("layout.async.document")
            profiler.emitProfile(into: measure, named: "profile.layout", frame: jobFrame)
            lane?.end()
            let completed: LayoutTree = tree
            await MainActor.run { [weak self] in
                self?.finishAsyncLayout(
                    completed,
                    effects: effects,
                    removed: removed,
                    jobID: jobID
                )
            }
        }
    }

    /// Installs a finished pass. A pass that started before the viewport moved
    /// is still a complete layout for the viewport it started with. Installing
    /// it keeps a drag showing new layouts; the current viewport is laid out
    /// next.
    private func finishAsyncLayout(
        _ tree: LayoutTree,
        effects: [LayoutEffect],
        removed: Set<LayoutID>,
        jobID: UInt
    ) {
        guard layoutInFlight, layoutJobID == jobID else { return }
        browser?.measure.start("layout.async.finish")
        defer { browser?.measure.stop("layout.async.finish") }
        layoutInFlight = false
        let job: LayoutJobKey? = layoutJobKey
        layoutJobKey = nil
        guard let job, let box: LayoutBox = state.layout.tree.box, box.tree.dom === dom else {
            return
        }
        let viewportMoved: Bool = job.isStale(
            currentSize: CGSize(width: frameWidth, height: frameHeight),
            currentZoom: pageZoom
        )
        layoutSize = job.size
        box.tree = tree
        if viewportMoved {
            browser?.measure.counter("layout.async.superseded", ["width": Int(job.size.width)])
        }
        if !effects.isEmpty {
            applyLayoutEffects(effects)
        }
        if !removed.isEmpty {
            state.display.composite.updates = state.display.composite.updates
                .filter({ box.tree.primaryLayout(for: $0.key) != nil })
            state.display.caches.prune(removing: removed)
        }
        state.layout.targets.isValid = false
        state.layout.targets.needsRebuild = true
        rebuildScrollTargets(box.tree)
        state.layout.targets.isValid = true
        state.layout.targets.needsRebuild = false
        tab?.needsAccessibility = true

        let needsRelayout: Bool = layoutInFlightDirty || viewportMoved
        layoutInFlightDirty = false
        state.layout.tree.isDirty = needsRelayout
        state.layout.tree.forced = needsRelayout
        if needsRelayout {
            state.runtime.schedule.needsRender = true
        }
        state.display.paint.isNeeded = true
        requestAnimationFrame()
    }

    func makeSnapshot() -> FrameSnapshot {
        paintedLayoutSize = layoutSize
        let display: FrameDisplayState = state.display
        let updates: [NodeID: EffectUpdate]? =
            (display.composite.isNeeded || display.composite.isNeededForPaint)
            ? nil
            : display.composite.updates
        return FrameSnapshot(
            scroll: ScrollState(
                scroll: scroll,
                interestTop: interestTop,
                interestBottom: interestBottom,
                maxScroll: maxScroll
            ),
            display: DisplaySnapshot(
                ops: display.paint.ops,
                updates: updates,
                revision: display.paint.revision
            ),
            preferences: ColorPreferences(
                prefersDark: tab?.prefersDark ?? false,
                usesForcedColors: tab?.forcedColors ?? false
            )
        )
    }

    func commitFrame() {
        guard let tab else { return }
        state.layout.scroll.offset = min(scroll, maxScroll)
        let snapshot: FrameSnapshot = makeSnapshot()
        state.display.composite.updates.removeAll()
        state.display.composite.isNeededForPaint = false
        browser?.commit(tab: tab, data: snapshot)
    }

    private func refreshScrollTargetRects() {
        guard let doc = document else {
            state.layout.targets.iframes.removeAll()
            state.layout.targets.blocks.removeAll()
            return
        }
        state.layout.targets.iframes = state.layout.targets.iframes.compactMap({ target in
            guard doc.contains(target.layout) else { return nil }
            return IframeTarget(
                rect: doc.absoluteBounds(target.layout),
                layout: target.layout,
                node: target.node
            )
        })
        state.layout.targets.blocks = state.layout.targets.blocks.compactMap({ target in
            guard doc.contains(target.layout) else { return nil }
            return ScrollBlockTarget(
                rect: doc.selfRect(target.layout),
                node: target.node,
                layout: target.layout
            )
        })
    }

    private func rebuildScrollTargets(_ doc: LayoutTree) {
        var iframes: [IframeTarget] = []
        var blocks: [ScrollBlockTarget] = []
        let objects: [LayoutID] = treeToList(doc, doc.rootID)
        for object in objects {
            if doc.isIframe(object) {
                iframes.append(
                    IframeTarget(
                        rect: doc.absoluteBounds(object),
                        layout: object,
                        node: doc.domID(of: object)
                    )
                )
            }
            if doc.isBlock(object),
                doc.domRef(object).style.computed.layout.overflow == .scroll
            {
                blocks.append(
                    ScrollBlockTarget(
                        rect: doc.selfRect(object),
                        node: doc.domID(of: object),
                        layout: object
                    )
                )
            }
        }
        state.layout.targets.iframes = iframes
        state.layout.targets.blocks = blocks
    }

    // MARK: - Scroll

    @discardableResult
    func repaintForScroll() -> Bool {
        guard !viewportFitsInPaintedWindow() else { return false }

        state.display.paint.isNeeded = true
        state.display.composite.isNeededForPaint = true
        paint(window: windowForScroll())
        commitFrame()
        return true
    }

    func scrollNeedsPaint() -> Bool {
        return !viewportFitsInPaintedWindow()
    }

    private func scrollTo(_ elt: DOMRef) {
        state.runtime.animation.tween = nil
        guard let doc = document else { return }
        let node: NodeID = elt.id
        let objs: [LayoutID] = treeToList(doc, doc.rootID).filter({
            doc.domID(of: $0) == node || doc.domRef($0).parent?.id == node
        })
        guard let obj = objs.first else { return }
        let y: CGFloat = doc.y(obj)
        if scroll < y && y + doc.height(obj) < scroll + frameHeight { return }
        state.layout.scroll.offset = max(0, min(y - Frame.scrollStep, maxScroll))
        state.layout.scroll.interestTop = max(0, scroll - frameHeight)
    }

    private func scrollToFragment(_ id: String) {
        guard let doc = document else { return }
        let target: LayoutID? = treeToList(doc, doc.rootID).first(where: {
            doc.domRef($0).element?.attributes["id"] == id
        })
        if let target = target {
            state.layout.scroll.offset = max(0, min(doc.y(target), maxScroll))
            state.runtime.animation.tween = nil
        }
    }

    func jumpTo(_ fragment: String?) {
        if let fragment {
            scrollToFragment(fragment)
        } else {
            state.layout.scroll.offset = 0
        }
        state.layout.scroll.interestTop = max(0, scroll - frameHeight)
        browser?.applyScrollAndUpdateInterest(
            scroll: scroll,
            interestTop: interestTop,
            interestBottom: interestBottom
        )
        browser?.navigationStateChanged()
        if !state.document.resources.images.lazy.isEmpty {
            requestAnimationFrame()
        }
    }

    func navigateToLocation(_ raw: String) {
        guard let tab, let current = url else { return }
        let resolved: WebURL = current.resolve(raw)
        if tab.isSameDocument(current, resolved) {
            tab.navigateToFragment(resolved, in: self)
        } else {
            tab.load(resolved, in: self)
        }
    }

    func linkURL(at x: CGFloat, y: CGFloat) -> WebURL? {
        guard let doc = document,
            let href = doc.linkHref(doc.rootID, x: x, y: y + scroll)
        else { return nil }
        return url?.resolve(href)
    }

    func scrollbarCommands() -> [DisplayOp] {
        guard let doc = document else { return [] }
        guard let bar = scrollbarBarRect(
            ScrollbarGeometry(
                docHeight: doc.height(doc.rootID) + 2 * VSTEP,
                contentHeight: frameHeight,
                contentWidth: frameWidth,
                scroll: scroll
            ),
            forcedColors: tab?.forcedColors ?? false
        ) else { return [] }
        return [bar]
    }

    func scrollDown() {
        if let tween = state.runtime.animation.tween {
            tween.aim(from: scroll, by: Frame.scrollStep, within: 0...maxScroll)
        } else {
            state.runtime.animation.tween = ScrollTween(from: scroll, to: min(scroll + Frame.scrollStep, maxScroll))
        }
        requestAnimationFrame()
    }

    func scrollUp() {
        if let tween = state.runtime.animation.tween {
            tween.aim(from: scroll, by: -Frame.scrollStep, within: 0...maxScroll)
        } else {
            state.runtime.animation.tween = ScrollTween(from: scroll, to: max(scroll - Frame.scrollStep, 0))
        }
        requestAnimationFrame()
    }

    @discardableResult
    func scrollAt(x: CGFloat, y: CGFloat, deltaY: CGFloat) -> Bool {
        let adjustedY: CGFloat = y + scroll
        guard document != nil else { return false }

        if let target = state.layout.targets.iframes.last(where: {
            $0.rect.containsPoint(x, adjustedY)
        }),
            let doc = document,
            doc.contains(target.layout)
        {
            let el: ElementRef? = DOMRef(id: target.node, dom: dom).element
            if let el = el, let child = el.frame, child.loaded {
                let bounds: Rect = doc.absoluteBounds(target.layout)
                let border: CGFloat = doc.zoom(target.layout)
                if child.scrollAt(
                    x: x - bounds.left,
                    y: adjustedY - bounds.top - border,
                    deltaY: deltaY
                ) {
                    return true
                }
            }
        }

        if let target = state.layout.targets.blocks.first(where: {
            $0.rect.containsPoint(x, adjustedY)
        }),
            let doc = document,
            doc.contains(target.layout)
        {
            guard let el: ElementRef = DOMRef(id: target.node, dom: dom).element else {
                return false
            }
            let maxScroll: CGFloat = max(0, doc.blockContentHeight(target.layout) - doc.height(target.layout))
            let current: CGFloat = min(el.scrollOffsetY, maxScroll)
            let next: CGFloat = max(0, min(current - deltaY, maxScroll))
            guard next != current else { return false }
            el.scrollOffsetY = next
            state.layout.tree.box?.tree.setBlockScrollOffset(target.layout, next)
            state.runtime.interaction.scrollFocus = el.id
            setNeedsPaint()
            return true
        }

        let before: CGFloat = scroll
        scrollBy(deltaY: deltaY)
        return scroll != before
    }

    func scrollBy(deltaY: CGFloat) {
        state.runtime.animation.tween = nil
        state.layout.scroll.offset = max(0, min(scroll - deltaY, maxScroll))
        if !checkInterestRegion() {
            browser?.applyScroll(scroll)
        }
        if !state.document.resources.images.lazy.isEmpty {
            requestAnimationFrame()
        }
    }

    private func scrollableAncestor(of obj: LayoutID, in doc: LayoutTree) -> NodeID? {
        var current: LayoutID? = obj
        while let c = current {
            if doc.isBlock(c),
                let el = doc.domRef(c).element,
                el.style.computed.layout.overflow == .scroll
            {
                return el.id
            }
            current = doc.parentID(of: c)
        }
        return nil
    }

    private func liveScrollBlock() -> LayoutID? {
        guard let node = state.runtime.interaction.scrollFocus, let doc = document else {
            return nil
        }
        return treeToList(doc, doc.rootID).first(where: {
            doc.isBlock($0) && doc.domID(of: $0) == node
        })
    }

    func scrollElementDown() {
        guard let node = state.runtime.interaction.scrollFocus, let doc = document,
            let block = liveScrollBlock()
        else {
            return
        }
        let maxScroll: CGFloat = max(0, doc.blockContentHeight(block) - doc.height(block))
        let current: CGFloat = min(dom.side.scrollOffsets[node] ?? 0, maxScroll)
        let next: CGFloat = min(current + Frame.scrollStep, maxScroll)
        dom.side.scrollOffsets[node] = next
        state.layout.tree.box?.tree.setBlockScrollOffset(block, next)
        setNeedsPaint()
    }

    func scrollElementUp() {
        guard let node = state.runtime.interaction.scrollFocus, let doc = document,
            let block = liveScrollBlock()
        else { return }
        let maxScroll: CGFloat = max(0, doc.blockContentHeight(block) - doc.height(block))
        let current: CGFloat = min(dom.side.scrollOffsets[node] ?? 0, maxScroll)
        let next: CGFloat = max(current - Frame.scrollStep, 0)
        dom.side.scrollOffsets[node] = next
        state.layout.tree.box?.tree.setBlockScrollOffset(block, next)
        setNeedsPaint()
    }

    @discardableResult
    private func checkInterestRegion() -> Bool {
        guard parentFrame == nil else {
            setNeedsPaint()
            return true
        }
        if scroll < interestTop || scroll + frameHeight > interestBottom {
            state.layout.scroll.interestTop = max(0, scroll - frameHeight)
            browser?.applyScrollAndUpdateInterest(
                scroll: scroll, interestTop: interestTop, interestBottom: interestBottom)
            return true
        }
        return false
    }

    // MARK: - Hover

    func clearHover() {
        setHoveredElements([])
    }

    private func resolveHover() {
        guard parentFrame == nil,
            let pending = tab?.pendingHover,
            let doc = document
        else { return }
        tab?.pendingHover = nil

        var chain: [NodeID] = []
        var current: DOMRef? = doc.hitTest(doc.rootID, x: pending.x, y: pending.y + scroll)
            .map({ DOMRef(id: $0.dom, dom: doc.dom) })
        while let node = current {
            if node.element != nil {
                chain.append(node.id)
            }
            current = node.parent
        }
        setHoveredElements(chain)
    }

    private func setHoveredElements(_ chain: [NodeID]) {
        let entering: Set<NodeID> = Set(chain)
        let leaving: Set<NodeID> = Set(state.runtime.interaction.hovered)
        guard entering != leaving else { return }

        var changed: [NodeID] = []
        for element in state.runtime.interaction.hovered where !entering.contains(element) {
            dom.setFlag(\.isHovered, false, of: element)
            changed.append(element)
        }

        for element in chain where !leaving.contains(element) {
            dom.setFlag(\.isHovered, true, of: element)
            changed.append(element)
        }
        state.runtime.interaction.hovered = chain

        // A descendant (e.g. `li:hover span`) can be styled by an ancestor
        // that is still hovered after the descendant left the chain.
        // On exit that ancestor is the only path back to the descendant.
        for element in changed {
            let ref: DOMRef = dom.ref(element)
            if state.document.sheets.index.list.index.hoverStylesDescendants {
                noteStyleInvalidation("style.invalidate.hover.node")
                setNeedsStyle(ref)
                markHoverDescendants(of: ref)
            } else {
                noteStyleInvalidation("style.invalidate.hover.node")
                setNeedsStyle(ref)
            }
        }
    }

    // MARK: - Interaction

    func keypress(_ char: String) {
        guard let f = focus else { return }
        let focusRef: DOMRef = dom.ref(f)
        if js.dispatchEvent(type: "keydown", el: focusRef) { return }

        if focusRef.element?.attributes["contenteditable"] != nil {
            let texts: [TextRef] = treeToList(focusRef).compactMap({ $0.text })
            let text: TextRef
            if let last = texts.last {
                text = last
            } else {
                let id: NodeID = dom.createText("")
                dom.append(id, to: f)
                text = dom.ref(id).text!
            }
            text.append(char)
            setNeedsStyle(focusRef)
        } else if dom.tag(of: f) == "input" {
            let value: String = (dom.attribute("value", of: f) ?? "") + char
            dom.setAttribute("value", value, of: f)
            setNeedsStyle(focusRef)
        } else {
            return
        }
    }

    func blur() {
        focusElement(nil)
    }

    func clearFocus() {
        guard let previous = focus else { return }
        let ref: DOMRef = dom.ref(previous)
        dom.setFlag(\.isFocused, false, of: previous)
        dom.setFlag(\.isFocusVisible, false, of: previous)
        setNeedsStyleSubtree(ref)
        _ = js?.dispatchEvent(type: "blur", el: ref)
        focus = nil
    }

    func focusElement(_ node: ElementRef?, showRing: Bool = true) {
        tab?.setFocusedFrame(self)
        if node?.id == focus { return }
        if let previous = focus {
            let ref: DOMRef = dom.ref(previous)
            dom.setFlag(\.isFocused, false, of: previous)
            dom.setFlag(\.isFocusVisible, false, of: previous)
            setNeedsStyleSubtree(ref)
            _ = js?.dispatchEvent(type: "blur", el: ref)
        }
        focus = node?.id
        if let node {
            let ref: DOMRef = node.ref
            dom.setFlag(\.isFocused, true, of: node.id)
            dom.setFlag(\.isFocusVisible, showRing, of: node.id)
            setNeedsStyleSubtree(ref)
            state.runtime.interaction.needsFocusScroll = true
            _ = js?.dispatchEvent(type: "focus", el: ref)
        }
        // Focus is a layout input (caret and text selection geometry), so the
        // pass cannot be skipped even when no style property moves.
        setNeedsLayout()
    }

    func click(x: CGFloat, y: CGFloat) {
        focusElement(nil)
        let clickY: CGFloat = y + scroll

        guard let doc = document,
            let hit: LayoutHit = doc.hitTest(doc.rootID, x: x, y: clickY)
        else {
            setNeedsPaint()
            return
        }

        state.runtime.interaction.scrollFocus = scrollableAncestor(of: hit.layout, in: doc)

        let source: DOMRef = DOMRef(id: hit.dom, dom: doc.dom)
        let prevented: Bool = js.dispatchEvent(type: "click", el: source)

        if !prevented {
            var elt: DOMRef? = source
            while let node = elt {
                if node.text != nil {

                } else if let el = node.element, el.tag == "iframe" {
                    guard let tree: LayoutTree = node.dom.layoutBox?.tree,
                        let layoutID: LayoutID = node.layoutID,
                        let child = el.frame, child.loaded
                    else {
                        return
                    }
                    let bounds: Rect = tree.absoluteBounds(layoutID)
                    let border: CGFloat = tree.zoom(layoutID)
                    child.click(x: x - bounds.left, y: clickY - bounds.top - border)
                    return
                } else if let el = node.element, el.tag == "a", let href = el.attributes["href"]
                {
                    let resolved: WebURL = url.resolve(href)
                    if href.hasPrefix("#") {
                        tab?.navigateToFragment(resolved, in: self)
                    } else {
                        tab?.load(resolved, in: self)
                    }
                    return
                } else if let el = node.element, el.tag == "input" {
                    if el.attributes["type"] == "checkbox" {
                        el.isChecked.toggle()
                        setNeedsStyle(node)
                        return
                    }
                    el.attributes["value"] = ""
                    focusElement(el, showRing: true)
                    setNeedsStyle(node)
                    return
                } else if let el = node.element, el.attributes["contenteditable"] != nil {
                    focusElement(el, showRing: true)
                    return
                } else if let el = node.element, el.tag == "button" {
                    focusElement(el, showRing: false)
                    var cursor: DOMRef? = node
                    while let c = cursor {
                        if let fe = c.element, fe.tag == "form", fe.attributes["action"] != nil {
                            submitForm(fe)
                            return
                        }
                        cursor = c.parent
                    }
                }
                elt = node.parent
            }
        }
        setNeedsPaint()
    }

    func enterKey() {
        guard let f = focus else { return }
        var cursor: DOMRef? = dom.ref(f)
        while let c = cursor {
            if let fe = c.element, fe.tag == "form", fe.attributes["action"] != nil {
                submitForm(fe)
                return
            }
            cursor = c.parent
        }
    }

    private func submitForm(_ el: ElementRef) {
        if js.dispatchEvent(type: "submit", el: el.ref) { return }
        let inputs: [ElementRef] = treeToList(el.ref)
            .compactMap { $0.element }
            .filter({
                $0.tag == "input" && $0.attributes["name"] != nil
                    && ($0.attributes["type"] != "checkbox" || $0.isChecked)
            })
        let body: String = inputs.map({ input -> String in
            let name: String =
                input.attributes["name"]!
                .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            let value: String
            if input.attributes["type"] == "checkbox" {
                value =
                    (input.attributes["value"] ?? "on")
                    .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            } else {
                value =
                    (input.attributes["value"] ?? "")
                    .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            }
            return "\(name)=\(value)"
        }).joined(separator: "&")

        let action: WebURL = url.resolve(el.attributes["action"]!)
        let method: String = el.attributes["method"]?.lowercased() ?? "get"

        if method == "post" {
            tab?.load(action, payload: body, in: self)
        } else {
            tab?.load(WebURL("\(action.toString())?\(body)"), in: self)
        }
    }

    // MARK: - Invalidation

    func setNeedsRender() {
        noteStyleInvalidation("style.invalidate.render")
        StyleInvalidation.markDocument(nodes)
        state.document.sheets.pending.needsHasPrecompute = true
        invalidateStyle()
    }

    func setNeedsStyle(_ node: DOMRef) {
        noteStyleInvalidation("style.invalidate.node")
        StyleInvalidation.markNodeAndAncestors(node)
        state.document.sheets.pending.needsHasPrecompute = true
        invalidateStyle()
    }

    func setNeedsStyleSubtree(_ node: DOMRef) {
        noteStyleInvalidation("style.invalidate.subtree")
        noteStyleInvalidation("style.invalidate.subtree.nodes", by: treeToList(node).count)
        StyleInvalidation.markSubtreeAndAncestors(node)
        state.document.sheets.pending.needsHasPrecompute = true
        invalidateStyle()
    }

    private func invalidateStyle(fromViewport: Bool = false) {
        if fromViewport {
            noteStyleInvalidation("style.invalidate.viewport")
            state.document.sheets.pending.byViewport = true
        } else {
            noteStyleInvalidation("style.invalidate.other")
            state.document.sheets.pending.byOther = true
        }
        // Schedules the pass; whether it becomes a document layout is decided
        // after styles are applied, from the changed properties.
        markDocumentDirty()
        state.runtime.schedule.needsRender = true
        parentFrame?.setNeedsLayout()
        requestAnimationFrame()
    }

    private func markDocumentDirty() {
        if layoutInFlight { layoutInFlightDirty = true }
        state.layout.tree.isDirty = true
    }

    private func markHoverDescendants(of element: DOMRef) {
        let selectors: [any CSSSelector] = state.document.sheets.index.list.index.hoverAncestorSelectors
        guard !selectors.isEmpty else { return }

        let newState: Bool = element.isHovered
        var matched: [NodeID: DOMRef] = [:]
        dom.setFlag(\.isHovered, !newState, of: element.id)
        collectHoverMatches(
            under: element,
            selectors: selectors,
            snapshot: StyleSnapshotBuilder.build(root: nodes),
            into: &matched
        )
        dom.setFlag(\.isHovered, newState, of: element.id)
        collectHoverMatches(
            under: element,
            selectors: selectors,
            snapshot: StyleSnapshotBuilder.build(root: nodes),
            into: &matched
        )

        for node in matched.values {
            StyleInvalidation.markNode(node)
        }

        noteStyleInvalidation("style.invalidate.hover.matched", by: matched.count)
    }

    private func collectHoverMatches(
        under element: DOMRef,
        selectors: [any CSSSelector],
        snapshot: StyleSnapshot,
        into matched: inout [NodeID: DOMRef]
    ) {
        for child in element.children {
            guard let childElement: ElementRef = child.element,
                let index: Int = snapshot.index(of: child.id)
            else { continue }
            if selectors.contains(where: {
                subjectCanMatch($0, childElement) && $0.matches(snapshot, index)
            }) {
                matched[child.id] = child
            }
            collectHoverMatches(
                under: child,
                selectors: selectors,
                snapshot: snapshot,
                into: &matched
            )
        }
    }

    private func subjectCanMatch(_ selector: any CSSSelector, _ element: ElementRef) -> Bool {
        switch selector.key {
        case .tag(let tag):
            return element.tag == tag
        case .className(let cls):
            return element.attributes["class"]?.split(separator: " ").contains(where: { $0 == cls }) == true
        case .id(let id):
            return element.attributes["id"] == id
        case .universal:
            return true
        }
    }

    func addAnimation(_ animation: any Animation, to node: DOMRef) {
        let key: AnimationKey = .property(animation.animatedProperty)
        if dom.addAnimation(animation, key: key, of: node.id) {
            state.runtime.animation.activeCount += 1
        }
    }

    func setNeedsLayout() {
        // Invalidation is field-based: style, structure, and geometry writes
        // mark the fields that read them. This flag only schedules a render
        // pass; dirtying the root here would turn every clean render into a
        // document pass and make a skipped block count as visited.
        state.layout.tree.forced = true
        markDocumentDirty()
        state.runtime.schedule.needsRender = true
        parentFrame?.setNeedsLayout()
        requestAnimationFrame()
    }

    func setNeedsViewportResize() {
        let mediaFlipped: Bool = !state.document.sheets.index.media.matches.isEmpty
            && !flippedMediaQueries(currentMedia()).isEmpty
        // A running pass finishes at the viewport it started with. Its install
        // sees the moved viewport and schedules the next pass, which picks up
        // the pending geometry.
        viewportGeometryPending = true
        if mediaFlipped {
            invalidateStyle(fromViewport: true)
        } else if !layoutInFlight {
            setNeedsLayout()
        }
    }

    func setNeedsPaint() {
        state.display.paint.epoch += 1
        state.display.paint.isNeeded = true
        state.runtime.schedule.needsRender = true
        parentFrame?.setNeedsPaint()
        requestAnimationFrame()
    }

    func setNeedsHoverCheck() {
        state.runtime.schedule.needsRender = true
        requestAnimationFrame()
    }

    func noteStyleInvalidation(_ name: String, by amount: Int = 1) {
        state.document.sheets.pending.counters[name, default: 0] += amount
    }

    // MARK: - Zoom

    func zoomBy(_ increment: Bool) {
        setPageZoom(pageZoom * (increment ? 1.1 : 1 / 1.1))
    }

    func resetZoom() {
        setPageZoom(1.0)
    }

    func setZoom(_ newZoom: CGFloat) {
        setPageZoom(newZoom)
    }

    func setPageZoom(_ newZoom: CGFloat) {
        guard newZoom > 0, abs(newZoom - pageZoom) > 0.001 else { return }
        pageZoom = newZoom
        viewportGeometryPending = true
        if parentFrame == nil, let tab {
            setViewport(
                width: tab.tabWidth / newZoom,
                height: tab.tabHeight / newZoom
            )
        }
        if let tab {
            for child in tab.allFrames where child.links.parent == links.id {
                child.setPageZoom(newZoom)
            }
        }
        setNeedsViewportResize()
    }

    /// The normal profiler bundle is diagnostic, but the GUI trace needs the
    /// style phase breakdown even when the profiler bundle is unavailable.
    private func emitStyleProfileCounters() {
        for (name, metric) in profiler.snapshot() where name.hasPrefix("style.") {
            guard metric.nanos > 0 || metric.count > 0 else { continue }
            browser?.measure.counter(
                name,
                ["us": Int(metric.nanos / 1_000), "count": metric.count]
            )
        }
    }

    private func currentMedia() -> MediaFeatures {
        MediaFeatures(
            preferences: ColorPreferences(
                prefersDark: tab?.prefersDark ?? false,
                usesForcedColors: tab?.forcedColors ?? false
            ),
            frameWidth: frameWidth
        )
    }

    private func flippedMediaQueries(_ media: MediaFeatures) -> Set<String> {
        var flipped: Set<String> = []
        for query in state.document.sheets.index.media.queries where state.document.sheets.index.media.matches[query] != media.matches(query) {
            flipped.insert(query)
        }
        return flipped
    }

    private func cachedStyleSnapshot() -> StyleSnapshot {
        if let snapshot: StyleSnapshot = styleSnapshotCache,
            styleSnapshotRevision == dom.revision
        {
            profiler.count("style.snapshot.cacheHit")
            return snapshot
        }
        profiler.count("style.snapshot.cacheMiss")
        let snapshot: StyleSnapshot = profiler.measure("style.snapshot.build", {
            StyleSnapshotBuilder.build(root: nodes)
        })
        styleSnapshotCache = snapshot
        styleSnapshotRevision = dom.revision
        return snapshot
    }

    private func scopedStyleScope(
        _ flipped: Set<String>
    ) -> (scope: StyleScope?, snapshot: StyleSnapshot?) {
        var selectors: [any CSSSelector] = []
        for rule in state.document.sheets.index.list.sorted {
            guard let query: String = rule.0, flipped.contains(query) else { continue }
            selectors.append(rule.1)
        }
        profiler.count("style.scope.rules", by: selectors.count)
        guard !selectors.isEmpty else { return (StyleScope(direct: []), nil) }

        let snapshot: StyleSnapshot = profiler.measure("style.snapshot.scope", {
            cachedStyleSnapshot()
        })
        let direct: Set<NodeID> = profiler.measure("style.scope.walk", {
            let matches: Set<NodeID> = ScopedStyleMatcher(selectors: selectors)
                .directMatches(in: snapshot)
            for id in matches {
                StyleInvalidation.markNode(dom.ref(id))
            }
            return matches
        })
        return (StyleScope(direct: direct), snapshot)
    }

    private func recordMediaMatches(_ media: MediaFeatures) {
        state.document.sheets.index.media.matches = state.document.sheets.index.media.queries.reduce(into: [:], { verdicts, query in
            verdicts[query] = media.matches(query)
        })
    }
}

let defaultStyleSheet: [(String?, any CSSSelector, [String: String])] = {
    guard let url = EngineResources.bundle.url(forResource: "browser", withExtension: "css"),
        let source = try? String(contentsOf: url, encoding: .utf8)
    else { return [] }
    return CSSParser(source).parse().rules
}()
