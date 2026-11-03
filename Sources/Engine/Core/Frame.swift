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
        state.layout.tree.value = nil
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
            state.layout.tree.value?.markDocumentWidthDirty()
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
    var document: LayoutTree? { state.layout.tree.value }

    func setLayoutTree(_ tree: LayoutTree?) {
        state.layout.tree.value = tree
        state.layout.tree.isDirty = false
        if let tree {
            tree.dom.layoutTree = tree
        }
    }
    var displayList: [DisplayOp] { state.display.paint.ops }
    // Bumped when anything that paint reads may have changed.
    // One epoch covers many paints; a cached item is valid only in its epoch.
    var paintEpoch: UInt { state.display.paint.epoch }
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
        let documentHeight: CGFloat = document?.root.heightIfUsed ?? 0
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
                self.state.document.resources.images.lazy = imgs.filter({ ImageLoading(element: $0) == .lazy }).map(\.id)
                let images: [ResourceLoad] = imgs.enumerated()
                    .filter({ ImageLoading(element: $0.element) == .eager })
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
            imgs[i].image = image ?? BrokenImage.replacement(for: imgs[i])
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
                let bounds: Rect = ref.layout?.absoluteBounds(),
                region.contains(bounds)
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
                el.image = image ?? BrokenImage.replacement(for: el)
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

    func render() {
        if !state.document.sheets.pending.counters.isEmpty {
            browser?.measure.counter("style.invalidation", state.document.sheets.pending.counters)
            state.document.sheets.pending.counters.removeAll(keepingCapacity: true)
        }
        let viewportStyle: Bool = state.document.sheets.pending.byViewport
        let reusableStyle: Bool = viewportStyle
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
            let hasBaseline: Bool = !state.document.sheets.index.media.matches.isEmpty
            let flipped: Set<String> = flippedMediaQueries(media)
            recordMediaMatches(media)
            browser?.measure.start("BrowserTab.style.scope")
            let scope: StyleScope? = (reusableStyle && hasBaseline) ? scopedStyleScope(flipped) : nil
            profiler.count(scope == nil ? "style.scope.none" : "style.scope.used")
            if viewportStyle, scope == nil {
                StyleInvalidation.markDocument(nodes)
            }
            browser?.measure.stop("BrowserTab.style.scope")
            profiler.count("style.flipped.queries", by: flipped.count)
            profiler.count("style.scope.direct", by: scope?.direct.count ?? 0)
            let cascade: StyleCascade = StyleCascade(
                index: state.document.sheets.index.list.index,
                media: media,
                scope: scope
            )
            if scope?.isEmpty != true {
                applyStyle(node: nodes, cascade: cascade)
            }
            profiler.count("style.applied", by: cascade.appliedNodes.count)
            browser?.measure.stop("BrowserTab.style.apply")

            browser?.measure.start("BrowserTab.style.diff")
            let animationsBefore: Int = cascade.appliedNodes.reduce(0) { $0 + $1.animations.count }
            var paintedChanged: Bool = false
            for node in cascade.appliedNodes {
                guard let old: ComputedStyle = cascade.oldStyle(for: node) else { continue }
                if Self.paintStyleChanged(old: old, new: node.style.computed) {
                    paintedChanged = true
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
            if paintedChanged {
                state.display.paint.epoch += 1
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

            markDocumentDirty()
        }

        if state.layout.tree.isDirty {
            browser?.measure.start("BrowserTab.layout")
            profiler.reset()
            defer { profiler.emitProfile(into: browser?.measure, named: "profile.layout") }
            defer { browser?.measure.stop("BrowserTab.layout") }
            let doc: LayoutTree
            if let existing = document, existing.dom === dom, browser?.forceFullLayout != true {
                doc = existing
            } else {
                doc = LayoutTree(dom: dom)
                state.layout.targets.isValid = false
            }
            doc.layoutDocument(
                availableWidth: frameWidth,
                zoom: 1.0,
                pageZoom: pageZoom
            )
            let removed: Set<LayoutID> = doc.sweepUnreachable()
            if !removed.isEmpty {
                state.display.composite.updates = state.display.composite.updates
                    .filter({ doc.primaryLayout(for: $0.key) != nil })
            }
            if state.layout.targets.iframes.contains(where: { removed.contains($0.layout) })
                || state.layout.targets.blocks.contains(where: { removed.contains($0.layout) })
            {
                state.layout.targets.isValid = false
                state.layout.targets.needsRebuild = true
            }
            setLayoutTree(doc)
            #if DEBUG
            if state.runtime.schedule.debugDumpDependencies {
                dumpDependencies(doc.root)
            }
            #endif
            browser?.measure.start("BrowserTab.rebuildScrollTargets")
            if state.layout.targets.needsRebuild || !state.layout.targets.isValid {
                rebuildScrollTargets(doc)
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
        paintTree(doc.root, into: &list, session: &session)

        state.display.paint.ops = list
        state.display.painted.bottom = contentBottom
        state.display.paint.revision += 1
        state.display.paint.isNeeded = false
    }

    private var contentBottom: CGFloat {
        return document?.root.selfRect().bottom ?? 0
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
                        document?.consumeStyleChanges(for: node.id)
                    }
                    if property == .transform || property == .opacity {
                        if node.layout?.isBlock == true,
                            let style: PaintEffectStyle = paintEffectStyle(node: node)
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
            render()

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

    func makeSnapshot() -> FrameSnapshot {
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
            let iframe: LayoutRef = LayoutRef(id: target.layout, tree: doc)
            return IframeTarget(
                rect: iframe.absoluteBounds(),
                layout: target.layout,
                node: target.node
            )
        })
        state.layout.targets.blocks = state.layout.targets.blocks.compactMap({ target in
            guard doc.contains(target.layout) else { return nil }
            let block: LayoutRef = LayoutRef(id: target.layout, tree: doc)
            return ScrollBlockTarget(
                rect: block.selfRect(),
                node: target.node,
                layout: target.layout
            )
        })
    }

    private func rebuildScrollTargets(_ doc: LayoutTree) {
        var iframes: [IframeTarget] = []
        var blocks: [ScrollBlockTarget] = []
        let objects: [LayoutRef] = treeToList(doc.root)
        for object in objects {
            if object.isIframe {
                iframes.append(
                    IframeTarget(
                        rect: object.absoluteBounds(),
                        layout: object.id,
                        node: object.domNode
                    )
                )
            }
            if object.isBlock,
                object.node.style.computed.layout.overflow == .scroll
            {
                blocks.append(
                    ScrollBlockTarget(
                        rect: object.selfRect(),
                        node: object.domNode,
                        layout: object.id
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
        paint(window: windowForScroll())
        commitFrame()
        return true
    }

    private func scrollTo(_ elt: DOMRef) {
        state.runtime.animation.tween = nil
        guard let doc = document else { return }
        let node: NodeID = elt.id
        let objs: [LayoutRef] = treeToList(doc.root).filter({
            $0.domNode == node || $0.node.parent?.id == node
        })
        guard let obj = objs.first else { return }
        if scroll < obj.y && obj.y + obj.height < scroll + frameHeight { return }
        state.layout.scroll.offset = max(0, min(obj.y - Frame.scrollStep, maxScroll))
        state.layout.scroll.interestTop = max(0, scroll - frameHeight)
    }

    private func scrollToFragment(_ id: String) {
        guard let doc = document else { return }
        let target: LayoutRef? = treeToList(doc.root).first(where: {
            $0.node.element?.attributes["id"] == id
        })
        if let target = target {
            state.layout.scroll.offset = max(0, min(target.y, maxScroll))
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
        guard let href = document?.root.linkElement(at: x, y: y + scroll)?.attributes["href"] else { return nil }
        return url?.resolve(href)
    }

    func scrollbarCommands() -> [DisplayOp] {
        guard let doc = document else { return [] }
        guard let bar = scrollbarBarRect(
            ScrollbarGeometry(
                docHeight: doc.root.height + 2 * VSTEP,
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
            let iframe: LayoutRef = LayoutRef(id: target.layout, tree: doc)
            let el: ElementRef? = DOMRef(id: target.node, dom: dom).element
            if let el = el, let child = el.frame, child.loaded {
                let bounds: Rect = iframe.absoluteBounds()
                let border: CGFloat = iframe.scaled(1)
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
            let block: LayoutRef = LayoutRef(id: target.layout, tree: doc)
            guard let el: ElementRef = DOMRef(id: target.node, dom: dom).element else {
                return false
            }
            let maxScroll: CGFloat = max(0, doc.blockContentHeight(block) - block.height)
            let current: CGFloat = min(el.scrollOffsetY, maxScroll)
            let next: CGFloat = max(0, min(current - deltaY, maxScroll))
            guard next != current else { return false }
            el.scrollOffsetY = next
            doc.setBlockScrollOffset(block, next)
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

    private func scrollableAncestor(of obj: LayoutRef) -> NodeID? {
        var current: LayoutRef? = obj
        while let c = current {
            if c.isBlock,
                let el = c.node.element,
                el.style.computed.layout.overflow == .scroll
            {
                return el.id
            }
            current = c.parent
        }
        return nil
    }

    private func liveScrollBlock() -> LayoutRef? {
        guard let node = state.runtime.interaction.scrollFocus, let doc = document else {
            return nil
        }
        return treeToList(doc.root).first(where: {
            $0.isBlock && $0.domNode == node
        })
    }

    func scrollElementDown() {
        guard let node = state.runtime.interaction.scrollFocus, let doc = document,
            let block = liveScrollBlock()
        else {
            return
        }
        let maxScroll: CGFloat = max(0, doc.blockContentHeight(block) - block.height)
        let current: CGFloat = min(dom.side.scrollOffsets[node] ?? 0, maxScroll)
        let next: CGFloat = min(current + Frame.scrollStep, maxScroll)
        dom.side.scrollOffsets[node] = next
        doc.setBlockScrollOffset(block, next)
        setNeedsPaint()
    }

    func scrollElementUp() {
        guard let node = state.runtime.interaction.scrollFocus, let doc = document,
            let block = liveScrollBlock()
        else { return }
        let maxScroll: CGFloat = max(0, doc.blockContentHeight(block) - block.height)
        let current: CGFloat = min(dom.side.scrollOffsets[node] ?? 0, maxScroll)
        let next: CGFloat = max(current - Frame.scrollStep, 0)
        dom.side.scrollOffsets[node] = next
        doc.setBlockScrollOffset(block, next)
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
        var current: DOMRef? = doc.root.hitTest(x: pending.x, y: pending.y + scroll)?.node
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
    }

    func click(x: CGFloat, y: CGFloat) {
        focusElement(nil)
        let clickY: CGFloat = y + scroll

        guard let source = document?.root.hitTest(x: x, y: clickY) else {
            setNeedsPaint()
            return
        }

        state.runtime.interaction.scrollFocus = scrollableAncestor(of: source)

        let prevented: Bool = js.dispatchEvent(type: "click", el: source.node)

        if !prevented {
            var elt: DOMRef? = source.node
            while let node = elt {
                if node.text != nil {

                } else if let el = node.element, el.tag == "iframe" {
                    guard let layout = node.layout, let child = el.frame, child.loaded else {
                        return
                    }
                    let bounds: Rect = layout.absoluteBounds()
                    let border: CGFloat = layout.scaled(1)
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
        markDocumentDirty()
        state.runtime.schedule.needsRender = true
        parentFrame?.setNeedsLayout()
        requestAnimationFrame()
    }

    private func markDocumentDirty() {
        state.layout.tree.isDirty = true
    }

    private func markHoverDescendants(of element: DOMRef) {
        let selectors: [any CSSSelector] = state.document.sheets.index.list.index.hoverAncestorSelectors
        guard !selectors.isEmpty else { return }

        let newState: Bool = element.isHovered
        var matched: [NodeID: DOMRef] = [:]
        dom.setFlag(\.isHovered, !newState, of: element.id)
        collectHoverMatches(under: element, selectors: selectors, into: &matched)
        dom.setFlag(\.isHovered, newState, of: element.id)
        collectHoverMatches(under: element, selectors: selectors, into: &matched)

        for node in matched.values {
            StyleInvalidation.markNode(node)
        }

        noteStyleInvalidation("style.invalidate.hover.matched", by: matched.count)
    }

    private func collectHoverMatches(
        under element: DOMRef,
        selectors: [any CSSSelector],
        into matched: inout [NodeID: DOMRef]
    ) {
        for child in element.children {
            guard let childElement: ElementRef = child.element else { continue }
            if selectors.contains(where: { subjectCanMatch($0, childElement) && $0.matches(child) }) {
                matched[child.id] = child
            }
            collectHoverMatches(under: child, selectors: selectors, into: &matched)
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
        markDocumentDirty()
        state.runtime.schedule.needsRender = true
        parentFrame?.setNeedsLayout()
        requestAnimationFrame()
    }

    func setNeedsViewportResize() {
        document?.markDocumentGeometryDirty()
        if !state.document.sheets.index.media.matches.isEmpty, !flippedMediaQueries(currentMedia()).isEmpty {
            invalidateStyle(fromViewport: true)
        } else {
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
        document?.markDocumentGeometryDirty()
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

    private func scopedStyleScope(
        _ flipped: Set<String>
    ) -> StyleScope? {
        var rules: [(selector: any CSSSelector, body: [String: String])] = []
        for rule in state.document.sheets.index.list.sorted {
            guard let query: String = rule.0, flipped.contains(query) else { continue }
            rules.append((rule.1, rule.2))
        }
        profiler.count("style.scope.rules", by: rules.count)
        guard !rules.isEmpty else { return StyleScope(direct: []) }
        guard rules.count <= 64 else { return nil } // NOTE: why 64?

        var direct: Set<NodeID> = []
        for node in treeToList(nodes) {
            guard node.element != nil else { continue }
            for rule in rules {
                if rule.selector.matches(node) {
                    StyleInvalidation.markNode(node)
                    direct.insert(node.id)
                    break
                }
            }
        }
        return StyleScope(direct: direct)
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
