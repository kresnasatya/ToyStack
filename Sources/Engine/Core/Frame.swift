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

    weak var tab: BrowserTab?
    weak var parentFrame: Frame?
    weak var frameElement: Element?
    let windowID: Int

    var url: WebURL!
    var nodes: any DOMNode = Element(tag: "html", attributes: [:], parent: nil)
    private let documentField: ProtectedField<DocumentLayout?>
    var document: DocumentLayout? {
        get { documentField.peek() ?? nil }
        set { documentField.set(newValue) }
    }
    var displayList: [any DisplayItem] = []
    var paintRevision: UInt = 0
    // Bumped when anything that paint reads may have changed.
    // One epoch covers many paints; a cached item is valid only in its epoch.
    var paintEpoch: UInt = 0
    var title: String = "New Tab"
    var isSecure: Bool = false

    var scroll: CGFloat = 0
    var frameWidth: CGFloat {
        didSet {
            if oldValue != frameWidth {
                document?.widthField.mark()
            }
        }
    }
    var frameHeight: CGFloat
    var loaded: Bool = false

    private(set) var focus: Element?
    private var rulesRevision: Int = 0
    var rules: [(String?, any CSSSelector, [String: String])] = [] {
        didSet {
            rulesRevision += 1
            needsHasPrecompute = true
        }
    }
    var keyframes: [String: [Keyframe]] = [:]
    private var allowedOrigins: [String]?
    private var referrerPolicy: String = ""
    private var loadedScriptURLs: Set<String> = []
    private var requestedBackgroundImages: Set<String> = []
    private var backgroundImageCache: [String: CGImage] = [:]
    private var lazyImages: [Element] = []
    var js: JSRuntime!

    private var compositedUpdates: [ObjectIdentifier: BrowserVisualEffect] = [:]

    var needsRender: Bool = false
    var needsPaint: Bool = false
    private var styleInvalidatedByViewport: Bool = false
    private var styleInvalidatedByOther: Bool = false
    private var needsHasPrecompute: Bool = true
    private var mediaQueries: Set<String> = []
    private var mediaMatches: [String: Bool] = [:]
    private var sortedRules: [(String?, any CSSSelector, [String: String])] = []
    private var ruleIndex: RuleIndex = RuleIndex(rules: [])
    private var indexedRulesRevision: Int = -1
    var needsCompositeForPaint: Bool = false
    private var needsComposite: Bool = false
    var needsFocusScroll: Bool = false

    #if DEBUG
    // Print the frozen field graph after a layout pass. Test-only escape hatch.
    var debugDumpDependencies: Bool = false
    #endif

    private(set) var interestTop: CGFloat = 0
    private var interestBottom: CGFloat { interestTop + 4 * frameHeight }
    private var scrollFocusNode: Element? = nil
    private var scrollTween: ScrollTween? = nil
    private var paintedBottom: CGFloat = 0
    private(set) var pageZoom: CGFloat = 1.0

    private var activeAnimations: Int = 0

    private struct IframeTarget {
        let rect: Rect
        let iframe: IframeLayout
    }

    private struct ScrollBlockTarget {
        let rect: Rect
        let element: Element
        let block: BlockLayout
    }

    private var iframeTargets: [IframeTarget] = []
    private var scrollBlockTargets: [ScrollBlockTarget] = []
    private var scrollTargetsValid: Bool = false
    private var scrollTargetsNeedRebuild: Bool = false

    func markStructureChanged() {
        scrollTargetsNeedRebuild = true
    }

    var hasScrollElement: Bool { scrollFocusNode != nil }

    var maxScroll: CGFloat {
        let documentHeight: CGFloat = document?.heightField.peek() ?? 0
        let padded: CGFloat = documentHeight + 2 * VSTEP
        return max(max(padded, paintedBottom + VSTEP) - frameHeight, 0)
    }

    private var browser: Browser? { tab?.browser }

    init(tab: BrowserTab, parent: FrameParent?, frameWidth: CGFloat, frameHeight: CGFloat) {
        self.documentField = ProtectedField<DocumentLayout?>(
            owner: FieldOwner(name: "document"),
            equals: { (lhs: DocumentLayout?, rhs: DocumentLayout?) -> Bool in lhs === rhs }
        )
        self.tab = tab
        self.parentFrame = parent?.frame
        self.frameElement = parent?.element
        self.frameWidth = frameWidth
        self.frameHeight = frameHeight
        self.windowID = tab.reserveWindowID()
        tab.windowIDToFrame[self.windowID] = self
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

            self.loaded = true
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
            isSecure = url.scheme == "https"
            scroll = 0
            scrollTween = nil
            interestTop = 0
            self.url = url
            tab?.markVisited(url.toString())
            discardChildFrames()
            if let message = frameBlockMessage(headers: headers) {
                print("Blocked iframe", url.toString(), "due to X-Frame-Options")
                return showFrameBlockedPage(message)
            }
            nodes = profiler.measure("load.parse", {
                HTMLParser(body: body).parse()
            })
            activeAnimations = 0

            profiler.measure("load.checkboxes", {
                for node in treeToList(nodes) {
                    if let el = node as? Element, el.tag == "input", el.attributes["type"] == "checkbox"
                    {
                        el.isChecked = el.attributes["checked"] != nil
                    }
                }
            })

            js = profiler.measure("load.jsInit", { JSRuntime(frame: self) })

            let titleText: String = profiler.measure("load.title", {
                treeToList(nodes)
                .compactMap({ $0 as? Element })
                .first(where: { $0.tag == "title" })?.children
                .compactMap({ $0 as? TextNode })
                .map(\.text).joined()
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            })
            title = titleText.isEmpty ? url.toString() : titleText

            allowedOrigins = nil
            referrerPolicy = headers["referrer-policy"] ?? ""
            if let csp = headers["content-security-policy"] {
                let parts: [String] = csp.split(separator: " ").map(String.init)
                if parts.first == "default-src" {
                    allowedOrigins = parts.dropFirst().map {
                        WebURL($0).origin()
                    }
                }
            }

            rules = profiler.measure("load.defaultCss") { defaultStyleSheet }

            let (styleURLs, scriptURLs, imageURLs): ([ResourceLoad], [ResourceLoad], [ResourceLoad]) =
            profiler.measure("load.resources", {
                let elements: [Element] = treeToList(nodes).compactMap({ $0 as? Element })
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
                let imgs: [Element] = elements.filter({ $0.tag == "img" })
                self.lazyImages = imgs.filter({ ImageLoading(element: $0) == .lazy })
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
            rules.append(contentsOf: parsed.rules)
            keyframes.merge(parsed.keyframes) { _, new in new }
        }

        for styleNode in treeToList(nodes).compactMap({ $0 as? Element }).filter({
            $0.tag == "style"
        }) {
            let css: String = styleNode.children.compactMap({ $0 as? TextNode }).map(\.text).joined()
            let parsed: (rules: [(String?, any CSSSelector, [String : String])], keyframes: [String : [Keyframe]]) = CSSParser(css).parse()
            rules.append(contentsOf: parsed.rules)
            keyframes.merge(parsed.keyframes) { _, new in new }
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
            loadedScriptURLs.insert(scriptURL.toString())
        }

        js.defineIDs()

        for scriptNode in treeToList(nodes).compactMap({ $0 as? Element })
            .filter({ $0.tag == "script" && $0.attributes["src"] == nil })
        {
            let code: String = scriptNode.children.compactMap({ $0 as? TextNode }).map(\.text).joined()
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
        let elements: [Element] = treeToList(nodes).compactMap({ $0 as? Element })
        let imgs: [Element] = elements.filter({ $0.tag == "img" })
        for (i, image) in images where i < imgs.count {
            imgs[i].image = image ?? BrokenImage.replacement(for: imgs[i])
            LayoutInvalidation.imageChanged(imgs[i])
        }
    }

    private func loadLazyImages() {
        guard let tab, let runner = tab.networkTaskRunner, let base = url else { return }
        let region: ImageLoadingRegion = ImageLoadingRegion(
            scroll: scroll,
            viewportHeight: frameHeight,
            margin: frameHeight
        )
        var remaining: [Element] = []
        for el in lazyImages {
            guard el.image == nil,
                let bounds: Rect = el.layoutObject?.absoluteBounds(),
                region.contains(bounds)
            else {
                remaining.append(el)
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
                el.image = image ?? BrokenImage.replacement(for: el)
                LayoutInvalidation.imageChanged(el)
                self.setNeedsLayout()
            }
        }
        lazyImages = remaining
    }

    private func loadBackgroundImages(_ nodes: [any DOMNode]) {
        guard let tab, let runner = tab.networkTaskRunner, let base = url else { return }

        var order: [String] = []
        var urlByKey: [String: WebURL] = [:]
        var elementsByKey: [String: [Element]] = [:]

        for node in nodes {
            guard let el = node as? Element,
                let value = el.style["background-image"],
                let raw = CSSValueParser.backgroundImageURL(value)
            else { continue }

            if el.backgroundImageSource != value {
                el.backgroundImage = nil
                el.backgroundImageSource = value
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
            let elements: [Element] = elementsByKey[key] ?? []
            if let cached: CGImage = backgroundImageCache[key] {
                for el in elements { el.backgroundImage = cached }
                continue
            }
            guard !requestedBackgroundImages.contains(key), let resolved = urlByKey[key] else {
                continue
            }
            requestedBackgroundImages.insert(key)
            let referrer: WebURL? = effectiveReferrer(for: resolved)
            Task { @MainActor in
                let image: CGImage? = await runner.schedule(name: "bg-image", {
                    await self.decodeImage(url: resolved, referrer: referrer)
                })
                guard let image else { return }
                self.backgroundImageCache[key] = image
                for el in elements { el.backgroundImage = image }
                self.setNeedsPaint()
            }
        }
    }

    func syncIframes() {
        guard let tab else { return }

        var live: Set<ObjectIdentifier> = []
        for node in treeToList(nodes) {
            guard let iframe = node as? Element, iframe.tag == "iframe" else { continue }
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
            live.insert(ObjectIdentifier(iframe))
            if iframe.frame != nil, iframe.frameSource != src {
                unloadIframe(iframe)
            }
            if iframe.frame == nil {
                loadIframe(iframe, documentURL: documentURL, source: src)
            }
        }

        let children: [Frame] = tab.windowIDToFrame.values.filter({ $0.parentFrame === self })
        for child in children {
            guard let el = child.frameElement, live.contains(ObjectIdentifier(el)) else {
                unload(child)
                continue
            }
        }
    }

    private func loadIframe(_ iframe: Element, documentURL: WebURL, source: String) {
        guard let tab else { return }
        markStructureChanged()
        let parent: FrameParent = FrameParent(frame: self, element: iframe)
        let child: Frame = Frame(tab: tab, parent: parent, frameWidth: 0, frameHeight: 0)
        child.pageZoom = pageZoom
        iframe.frame = child
        iframe.frameSource = source
        child.load(documentURL)
    }

    private func unloadIframe(_ iframe: Element) {
        guard let child = iframe.frame else { return }
        markStructureChanged()
        unload(child)
    }

    private func unload(_ frame: Frame) {
        frame.frameElement?.frame = nil
        frame.frameElement?.frameSource = nil
        frame.discardChildFrames()
        tab?.windowIDToFrame.removeValue(forKey: frame.windowID)
        if let tab, let focused = tab.focusedFrame, tab.windowIDToFrame[focused.windowID] == nil {
            tab.setFocusedFrame(self)
        }
    }

    private func discardChildFrames() {
        guard let tab else { return }
        let children: [Frame] = tab.windowIDToFrame.values.filter({ $0.parentFrame === self })
        for child in children {
            child.discardChildFrames()
            tab.windowIDToFrame.removeValue(forKey: child.windowID)
        }
        if let focused = tab.focusedFrame, tab.windowIDToFrame[focused.windowID] == nil {
            tab.setFocusedFrame(self)
        }
    }

    private func effectiveReferrer(for targetURL: WebURL) -> WebURL? {
        switch referrerPolicy {
        case "no-referrer":
            return nil
        case "same-origin":
            return url?.origin() == targetURL.origin() ? url : nil
        default:
            return url
        }
    }

    func allowedRequest(_ url: WebURL) -> Bool {
        allowedOrigins == nil || (allowedOrigins?.contains(url.origin()) ?? false)
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
        nodes = HTMLParser(body: """
            <html>
            <body><p>\(message)</p></body>
            </html>
            """).parse()
        js = JSRuntime(frame: self)
        title = "Blocked"
        allowedOrigins = nil
        referrerPolicy = ""
        rules = defaultStyleSheet
        return ResourceLoads(styleURLs: [], scriptURLs: [], imageURLs: [])
    }

    func runNewScripts(in root: any DOMNode) {
        for node in treeToList(root) {
            guard let el = node as? Element, el.tag == "script",
                let src = el.attributes["src"]
            else { continue }
            let scriptURL: WebURL = url.resolve(src)
            guard allowedRequest(scriptURL) else {
                print("Blocked script", src, "due to CSP")
                continue
            }
            let urlStr: String = scriptURL.toString()
            guard !loadedScriptURLs.contains(urlStr) else { continue }
            guard let (status, headers, body) = scriptURL.requestSync() else { continue }
            guard BrowserTab.isExecutableScript(status: status, headers: headers, url: scriptURL) else { continue }
            loadedScriptURLs.insert(urlStr)
            js.run(script: urlStr, code: body)
        }
    }

    func reloadStylesheets() {
        rules = defaultStyleSheet
        for node in treeToList(nodes) {
            guard let el = node as? Element else { continue }
            if el.tag == "link", el.attributes["rel"] == "stylesheet",
                let href = el.attributes["href"]
            {
                let styleURL: WebURL = url.resolve(href)
                guard allowedRequest(styleURL) else { continue }
                guard let (status, headers, body) = styleURL.requestSync() else { continue }
                guard BrowserTab.isUsableStylesheet(status: status, headers: headers, url: styleURL) else { continue }
                let parsed: (rules: [(String?, any CSSSelector, [String : String])], keyframes: [String : [Keyframe]]) = CSSParser(body).parse()
                rules.append(contentsOf: parsed.rules)
                keyframes.merge(parsed.keyframes) { _, new in new }
            }
            if el.tag == "style" {
                let css: String = el.children.compactMap({ $0 as? TextNode }).map(\.text).joined()
                let parsed: (rules: [(String?, any CSSSelector, [String : String])], keyframes: [String : [Keyframe]]) = CSSParser(css).parse()
                rules.append(contentsOf: parsed.rules)
                keyframes.merge(parsed.keyframes) { _, new in new }
            }
        }
        StyleInvalidation.markDocument(nodes)
    }

    // MARK: - Render

    func render() {
        let viewportStyle: Bool = styleInvalidatedByViewport
        let reusableStyle: Bool =
            viewportStyle && !styleInvalidatedByOther
        styleInvalidatedByViewport = false
        styleInvalidatedByOther = false
        let stylesDirty: Bool = nodes.style.isDirty || nodes.style.hasDirtyDescendant
        if stylesDirty || viewportStyle {
            paintEpoch += 1
            browser?.measure.start("BrowserTab.style")
            profiler.reset()
            defer { profiler.emitProfile(into: browser?.measure, named: "profile.style") }
            defer { browser?.measure.stop("BrowserTab.style") }

            browser?.measure.start("BrowserTab.style.rules")
            if indexedRulesRevision != rulesRevision {
                sortedRules = rules.sorted(by: { cascadePriority($0) < cascadePriority($1) })
                ruleIndex = RuleIndex(rules: sortedRules)
                mediaQueries = Set(sortedRules.compactMap({ $0.0 }))
                indexedRulesRevision = rulesRevision
                profiler.count("style.rules", by: sortedRules.count)
            }
            browser?.measure.stop("BrowserTab.style.rules")

            browser?.measure.start("BrowserTab.style.has")
            if needsHasPrecompute {
                precomputeHas(node: nodes, rules: sortedRules)
                needsHasPrecompute = false
            }
            browser?.measure.stop("BrowserTab.style.has")

            browser?.measure.start("BrowserTab.style.apply")
            let media: MediaFeatures = currentMedia()
            let hasBaseline: Bool = !mediaMatches.isEmpty
            let flipped: Set<String> = flippedMediaQueries(media)
            recordMediaMatches(media)
            browser?.measure.start("BrowserTab.style.scope")
            let scope: StyleScope? = (reusableStyle && hasBaseline) ? scopedStyleScope(flipped) : nil
            if viewportStyle, scope == nil {
                StyleInvalidation.markDocument(nodes)
            }
            browser?.measure.stop("BrowserTab.style.scope")
            profiler.count("style.flipped.queries", by: flipped.count)
            profiler.count("style.scope.direct", by: scope?.direct.count ?? 0)
            let cascade: StyleCascade = StyleCascade(
                index: ruleIndex,
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
            for node in cascade.appliedNodes {
                let old: [String : String] = cascade.oldStyle(for: node)
                // Scroll targets are collected by layout class and computed overflow.
                // A style-only change to either changes the target set, not just rects.
                if old["display"] != node.style["display"]
                    || old["overflow"] != node.style["overflow"]
                {
                    markStructureChanged()
                }
                let newAnimations: [String : any Animation] = StyleTransitions.diff(node: node, oldStyle: old, newStyle: node.style.snapshot())
                for (property, animation) in newAnimations {
                    node.animations[property] = animation
                }
            }
            browser?.measure.stop("BrowserTab.style.diff")

            browser?.measure.start("BrowserTab.style.keyframes")
            if !keyframes.isEmpty {
                for node in cascade.appliedNodes {
                    guard let animDecl = node.style["animation"],
                        let playback = KeyframePlayback.parse(animDecl),
                        let frames = keyframes[playback.name]
                    else { continue }
                    let key: String = "animation/\(playback.name)"
                    guard node.animations[key] == nil else { continue }
                    if let anim = KeyframeAnimation.make(frames: frames, playback: playback)
                    {
                        node.animations[key] = anim
                    }
                }
            }
            browser?.measure.stop("BrowserTab.style.keyframes")

            activeAnimations += cascade.appliedNodes.reduce(0) { $0 + $1.animations.count } - animationsBefore

            browser?.measure.start("BrowserTab.style.visited")
            if tab?.hasVisitedURLs == true {
                for node in cascade.appliedNodes {
                    guard let el = node as? Element, el.tag == "a",
                        let href = el.attributes["href"]
                    else {
                        continue
                    }
                    if tab?.hasVisited(url.resolve(href).toString()) == true {
                        el.style["color"] = (tab?.forcedColors ?? false) ? ForcedColor.visitedText : "purple"
                    }
                }
            }
            browser?.measure.stop("BrowserTab.style.visited")

            loadBackgroundImages(cascade.appliedNodes)

            documentField.mark()
        }

        if documentField.isDirty {
            browser?.measure.start("BrowserTab.layout")
            profiler.reset()
            defer { profiler.emitProfile(into: browser?.measure, named: "profile.layout") }
            defer { browser?.measure.stop("BrowserTab.layout") }
            let doc: DocumentLayout
            if let existing = document, existing.node === nodes, browser?.forceFullLayout != true {
                doc = existing
            } else {
                doc = DocumentLayout(node: nodes)
                scrollTargetsValid = false
            }
            doc.layout(
                availableWidth: frameWidth,
                zoom: 1.0,
                pageZoom: pageZoom
            )
            document = doc
            #if DEBUG
            if debugDumpDependencies {
                dumpDependencies(doc)
            }
            #endif
            browser?.measure.start("BrowserTab.rebuildScrollTargets")
            if scrollTargetsNeedRebuild || !scrollTargetsValid {
                rebuildScrollTargets(doc)
                scrollTargetsValid = true
                scrollTargetsNeedRebuild = false
                profiler.count("scrollTargets.rebuilt")
            } else {
                refreshScrollTargetRects()
                profiler.count("scrollTargets.reused")
            }
            browser?.measure.stop("BrowserTab.rebuildScrollTargets")

            tab?.needsAccessibility = true
            needsPaint = true
        }

        requestAnimationFrame()
    }

    // Properties that cannot change geometry. Everything else is treated as a
    // layout input, including properties this engine does not know yet.
    private static let paintOnlyProperties: Set<String> = [
        "color", "background-color", "background-image", "background-size",
        "border-color", "border-radius",
        "border-top-left-radius", "border-top-right-radius",
        "border-bottom-left-radius", "border-bottom-right-radius",
        "outline-color", "outline-style", "outline-width",
        "filter", "mix-blend-mode", "opacity", "transform", "z-index",
        "image-rendering", "object-fit"
    ]

    static func affectsLayout(_ property: String) -> Bool {
        return !paintOnlyProperties.contains(property)
    }

    func paint() {
        guard needsPaint else { return }
        browser?.measure.start("BrowserTab.paint")
        profiler.reset()
        defer { profiler.emitProfile(into: browser?.measure, named: "profile.paint") }
        defer { browser?.measure.stop("BrowserTab.paint") }
        guard let doc = document else { return }
        var list: [any DisplayItem] = []
        list.reserveCapacity(displayList.count)
        paintTree(doc, into: &list, epoch: paintEpoch)
        displayList = list
        paintedBottom = maxRectBottom(list)
        paintRevision += 1
        needsPaint = false
    }

    func runAnimationFrame() {
        guard js != nil else { return }
        browser?.measure.start("BrowserTab.animFrame")
        defer { browser?.measure.stop("BrowserTab.animFrame") }
        browser?.measure.start("BrowserTab.raf")
        js.run(script: "raf", code: "__runRAFHandlers()")
        browser?.measure.stop("BrowserTab.raf")
        var needsAnotherFrame: Bool = false
        needsComposite = nodes.style.isDirty || documentField.isDirty || needsPaint
        var needsLayoutUpdate: Bool = false
        var animationFallbacks: Int = 0
        browser?.measure.start("BrowserTab.animScan")
        let animated: [any DOMNode] = activeAnimations > 0 ? treeToList(nodes) : []
        for node in animated {
            for (key, animation) in node.animations {
                let property: String = animation.animatedProperty
                if let value = animation.nextValue() {
                    needsAnotherFrame = true
                    if property == "transform" || property == "opacity"
                    {
                        node.style[property] = value
                        if let rect = (node.layoutObject as? BlockLayout)?.selfRect(),
                            let effect = paintBrowserVisualEffects(node: node, items: [], rect: rect).first
                                as? BrowserVisualEffect
                        {
                            compositedUpdates[ObjectIdentifier(node)] = effect
                        }
                    } else if Self.affectsLayout(property) {
                        node.style[property] = value
                        if document?.layoutNeeded() == true {
                            needsLayoutUpdate = true
                        } else {
                            // A layout property that marked no field is a missing edge.
                            // Trap in debug; mark the nearest block in release so the
                            // page still updates instead of freezing on a stale layout.
                            assertionFailure("Animation for \(property) did not dirty a layout field")
                            LayoutInvalidation.animatedPropertyChanged(node, property: property)
                            needsLayoutUpdate = true
                            animationFallbacks += 1
                        }
                    } else {
                        node.style[property] = value
                        needsCompositeForPaint = true
                        needsPaint = true
                    }
                } else {
                    if node.animations.removeValue(forKey: key) != nil { activeAnimations -= 1 }
                    needsCompositeForPaint = true
                    needsPaint = true
                }
            }
        }
        browser?.measure.counter("layout.animation.fallback", ["nodes": animationFallbacks])
        browser?.measure.stop("BrowserTab.animScan")

        if needsPaint {
            setNeedsPaint()
        }

        if needsLayoutUpdate {
            needsCompositeForPaint = true
            setNeedsLayout()
        }

        if needsRender {
            needsRender = false
            render()

            if needsFocusScroll, let f = focus {
                scrollTo(f)
            }
            needsFocusScroll = false
        }

        if let tween = scrollTween {
            if let value = tween.nextValue() {
                scroll = max(0, min(value, maxScroll))
                needsAnotherFrame = true
                checkInterestRegion()
            } else {
                scrollTween = nil
            }
        }

        if !lazyImages.isEmpty {
            loadLazyImages()
        }

        if needsAnotherFrame {
            requestAnimationFrame()
        }
    }

    func commitFrame() {
        guard let tab else { return }
        let updates: [ObjectIdentifier: BrowserVisualEffect]? = (needsComposite || needsCompositeForPaint) ? nil : compositedUpdates
        let data: FrameCommit = FrameCommit(
            scrollState: ScrollState(scroll: scroll, interestTop: interestTop, interestBottom: interestBottom, maxScroll: maxScroll),
            display: FrameDisplayOutput(displayList: displayList, compositedUpdates: updates, paintRevision: paintRevision),
            preferences: ColorPreferences(
                prefersDark: tab.prefersDark,
                usesForcedColors: tab.forcedColors
            )
        )
        compositedUpdates = [:]
        needsCompositeForPaint = false
        browser?.commit(tab: tab, data: data)
    }

    private func refreshScrollTargetRects() {
        iframeTargets = iframeTargets.compactMap({ target in
            let el: Element? = target.iframe.node as? Element
            guard let iframe = el?.layoutObject as? IframeLayout else { return nil }
            return IframeTarget(rect: iframe.absoluteBounds(), iframe: iframe)
        })
        scrollBlockTargets = scrollBlockTargets.map({ target in
            ScrollBlockTarget(
                rect: target.block.selfRect(),
                element: target.element,
                block: target.block
            )
        })
    }

    private func rebuildScrollTargets(_ doc: DocumentLayout) {
        var iframes: [IframeTarget] = []
        var blocks: [ScrollBlockTarget] = []
        var objects: [any LayoutObject] = []
        treeToList(doc, into: &objects)
        for object in objects {
            if let iframe = object as? IframeLayout {
                iframes.append(
                    IframeTarget(rect: iframe.absoluteBounds(), iframe: iframe)
                )
            }
            if let block = object as? BlockLayout,
                block.node.style["overflow"] == "scroll",
                let element = block.node as? Element
            {
                blocks.append(
                    ScrollBlockTarget(
                        rect: block.selfRect(),
                        element: element,
                        block: block
                    )
                )
            }
        }
        iframeTargets = iframes
        scrollBlockTargets = blocks
    }

    // MARK: - Scroll

    private func scrollTo(_ elt: Element) {
        scrollTween = nil
        guard let doc = document else { return }
        let objs: [any LayoutObject] = treeToList(doc).filter({ $0.node === elt || $0.node.parent === elt })
        guard let obj = objs.first else { return }
        if scroll < obj.y && obj.y + obj.height < scroll + frameHeight { return }
        scroll = max(0, min(obj.y - Frame.scrollStep, maxScroll))
        interestTop = max(0, scroll - frameHeight)
    }

    private func scrollToFragment(_ id: String) {
        guard let doc = document else { return }
        let target: (any LayoutObject)? = treeToList(doc).first(where: {
            ($0.node as? Element)?.attributes["id"] == id
        })
        if let target = target {
            scroll = max(0, min(target.y, maxScroll))
            scrollTween = nil
        }
    }

    func jumpTo(_ fragment: String?) {
        if let fragment {
            scrollToFragment(fragment)
        } else {
            scroll = 0
        }
        interestTop = max(0, scroll - frameHeight)
        browser?.applyScrollAndUpdateInterest(
            scroll: scroll,
            interestTop: interestTop,
            interestBottom: interestBottom
        )
        browser?.navigationStateChanged()
        if !lazyImages.isEmpty {
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
        guard let href = document?.linkElement(at: x, y: y + scroll)?.attributes["href"] else { return nil }
        return url?.resolve(href)
    }

    func scrollbarCommands() -> [any DisplayCommand] {
        guard let doc = document else { return [] }
        guard let bar = scrollbarBarRect(
            ScrollbarGeometry(
                docHeight: doc.height + 2 * VSTEP,
                contentHeight: frameHeight,
                contentWidth: frameWidth,
                scroll: scroll
            ),
            forcedColors: tab?.forcedColors ?? false
        ) else { return [] }
        return [ScrollbarBar(rect: bar.rect, color: bar.color, radius: ScrollbarStyle.thumbRadius)]
    }

    func scrollDown() {
        if let tween = scrollTween {
            tween.aim(from: scroll, by: Frame.scrollStep, within: 0...maxScroll)
        } else {
            scrollTween = ScrollTween(from: scroll, to: min(scroll + Frame.scrollStep, maxScroll))
        }
        requestAnimationFrame()
    }

    func scrollUp() {
        if let tween = scrollTween {
            tween.aim(from: scroll, by: -Frame.scrollStep, within: 0...maxScroll)
        } else {
            scrollTween = ScrollTween(from: scroll, to: max(scroll - Frame.scrollStep, 0))
        }
        requestAnimationFrame()
    }

    @discardableResult
    func scrollAt(x: CGFloat, y: CGFloat, deltaY: CGFloat) -> Bool {
        let adjustedY: CGFloat = y + scroll
        guard document != nil else { return false }

        if let target = iframeTargets.last(where: {
            $0.rect.containsPoint(x, adjustedY)
        }),
            let el = target.iframe.node as? Element,
            let child = el.frame, child.loaded
        {
            let bounds: Rect = target.iframe.absoluteBounds()
            let border: CGFloat = target.iframe.scaled(1)
            if child.scrollAt(
                x: x - bounds.left,
                y: adjustedY - bounds.top - border,
                deltaY: deltaY
            ) {
                return true
            }
        }

        if let target = scrollBlockTargets.first(where: {
            $0.rect.containsPoint(x, adjustedY)
        }) {
            let block: BlockLayout = target.block
            let el: Element = target.element
            let maxScroll: CGFloat = max(0, block.contentHeight - block.height)
            let current: CGFloat = min(el.scrollOffsetY, maxScroll)
            let next: CGFloat = max(0, min(current - deltaY, maxScroll))
            guard next != current else { return false }
            el.scrollOffsetY = next
            block.scrollOffset = next
            scrollFocusNode = el
            setNeedsPaint()
            return true
        }

        let before: CGFloat = scroll
        scrollBy(deltaY: deltaY)
        return scroll != before
    }

    func scrollBy(deltaY: CGFloat) {
        scrollTween = nil
        scroll = max(0, min(scroll - deltaY, maxScroll))
        if !checkInterestRegion() {
            browser?.applyScroll(scroll)
        }
        if !lazyImages.isEmpty {
            requestAnimationFrame()
        }
    }

    private func scrollableAncestor(of obj: any LayoutObject) -> Element? {
        var current: (any LayoutObject)? = obj
        while let c = current {
            if let block = c as? BlockLayout,
                let el = block.node as? Element,
                el.style["overflow"] == "scroll"
            {
                return el
            }
            current = c.parent
        }
        return nil
    }

    private func liveScrollBlock() -> BlockLayout? {
        guard let node = scrollFocusNode, let doc = document else {
            return nil
        }
        return treeToList(doc).compactMap({ $0 as? BlockLayout })
            .first(where: { $0.node === node })
    }

    func scrollElementDown() {
        guard let node = scrollFocusNode, let block = liveScrollBlock() else {
            return
        }
        let maxScroll: CGFloat = max(0, block.contentHeight - block.height)
        let current: CGFloat = min(node.scrollOffsetY, maxScroll)
        node.scrollOffsetY = min(current + Frame.scrollStep, maxScroll)
        block.scrollOffset = node.scrollOffsetY
        setNeedsPaint()
    }

    func scrollElementUp() {
        guard let node = scrollFocusNode, let block = liveScrollBlock() else { return }
        let maxScroll: CGFloat = max(0, block.contentHeight - block.height)
        let current: CGFloat = min(node.scrollOffsetY, maxScroll)
        node.scrollOffsetY = max(current - Frame.scrollStep, 0)
        block.scrollOffset = node.scrollOffsetY
        setNeedsPaint()
    }

    @discardableResult
    private func checkInterestRegion() -> Bool {
        guard parentFrame == nil else {
            setNeedsPaint()
            return true
        }
        if scroll < interestTop || scroll + frameHeight > interestBottom {
            interestTop = max(0, scroll - frameHeight)
            browser?.applyScrollAndUpdateInterest(
                scroll: scroll, interestTop: interestTop, interestBottom: interestBottom)
            return true
        }
        return false
    }

    // MARK: - Interaction

    func keypress(_ char: String) {
        guard let f = focus else { return }
        if js.dispatchEvent(type: "keydown", elt: f) { return }

        if f.attributes["contenteditable"] != nil {
            let text: TextNode
            if let last = treeToList(f).compactMap({ $0 as? TextNode }).last {
                text = last
            } else {
                text = TextNode(text: "", parent: f)
                f.children.append(text)
            }
            text.append(char)
            setNeedsStyle(f)
        } else if f.tag == "input" {
            f.attributes["value", default: ""] += char
            setNeedsStyle(f)
        } else {
            return
        }
    }

    func blur() {
        focusElement(nil)
    }

    func clearFocus() {
        guard let previous = focus else { return }
        previous.isFocused = false
        previous.isFocusVisible = false
        setNeedsStyleSubtree(previous)
        _ = js?.dispatchEvent(type: "blur", elt: previous)
        focus = nil
    }

    func focusElement(_ node: Element?, showRing: Bool = true) {
        tab?.setFocusedFrame(self)
        if node === focus { return }
        if let previous = focus {
            previous.isFocused = false
            previous.isFocusVisible = false
            setNeedsStyleSubtree(previous)
            _ = js?.dispatchEvent(type: "blur", elt: previous)
        }
        focus = node
        if let node = node {
            node.isFocused = true
            node.isFocusVisible = showRing
            setNeedsStyleSubtree(node)
            needsFocusScroll = true
            _ = js?.dispatchEvent(type: "focus", elt: node)
        }
    }

    func click(x: CGFloat, y: CGFloat) {
        focusElement(nil)
        let clickY: CGFloat = y + scroll

        guard let source = document?.hitTest(x: x, y: clickY) else {
            setNeedsPaint()
            return
        }

        scrollFocusNode = scrollableAncestor(of: source)

        let prevented: Bool = js.dispatchEvent(type: "click", elt: source.node)

        if !prevented {
            var elt: (any DOMNode)? = source.node
            while let node = elt {
                if node is TextNode {

                } else if let el = node as? Element, el.tag == "iframe" {
                    guard let layout = el.layoutObject, let child = el.frame, child.loaded else {
                        return
                    }
                    let bounds: Rect = layout.absoluteBounds()
                    let border: CGFloat = layout.scaled(1)
                    child.click(x: x - bounds.left, y: clickY - bounds.top - border)
                    return
                } else if let el = node as? Element, el.tag == "a", let href = el.attributes["href"]
                {
                    let resolved: WebURL = url.resolve(href)
                    if href.hasPrefix("#") {
                        tab?.navigateToFragment(resolved, in: self)
                    } else {
                        tab?.load(resolved, in: self)
                    }
                    return
                } else if let el = node as? Element, el.tag == "input" {
                    if el.attributes["type"] == "checkbox" {
                        el.isChecked.toggle()
                        setNeedsStyle(el)
                        return
                    }
                    el.attributes["value"] = ""
                    focusElement(el, showRing: true)
                    setNeedsStyle(el)
                    return
                } else if let el = node as? Element, el.attributes["contenteditable"] != nil {
                    focusElement(el, showRing: true)
                    return
                } else if let el = node as? Element, el.tag == "button" {
                    focusElement(el, showRing: false)
                    var cursor: (any DOMNode)? = el
                    while let c = cursor {
                        if let fe = c as? Element, fe.tag == "form", fe.attributes["action"] != nil
                        {
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
        var cursor: (any DOMNode)? = f
        while let c = cursor {
            if let fe = c as? Element, fe.tag == "form", fe.attributes["action"] != nil {
                submitForm(fe)
                return
            }
            cursor = c.parent
        }
    }

    private func submitForm(_ elt: Element) {
        if js.dispatchEvent(type: "submit", elt: elt) { return }
        let inputs: [Element] = treeToList(elt)
            .compactMap {
                $0 as? Element
            }
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

        let action: WebURL = url.resolve(elt.attributes["action"]!)
        let method: String = elt.attributes["method"]?.lowercased() ?? "get"

        if method == "post" {
            tab?.load(action, payload: body, in: self)
        } else {
            tab?.load(WebURL("\(action.toString())?\(body)"), in: self)
        }
    }

    // MARK: - Invalidation

    func setNeedsRender() {
        StyleInvalidation.markDocument(nodes)
        needsHasPrecompute = true
        invalidateStyle()
    }

    func setNeedsStyle(_ node: any DOMNode) {
        StyleInvalidation.markNodeAndAncestors(node)
        needsHasPrecompute = true
        invalidateStyle()
    }

    func setNeedsStyleSubtree(_ node: any DOMNode) {
        StyleInvalidation.markSubtreeAndAncestors(node)
        needsHasPrecompute = true
        invalidateStyle()
    }

    private func invalidateStyle(fromViewport: Bool = false) {
        if fromViewport {
            styleInvalidatedByViewport = true
        } else {
            styleInvalidatedByOther = true
        }
        documentField.mark()
        needsRender = true
        parentFrame?.setNeedsLayout()
        requestAnimationFrame()
    }

    func setNeedsLayout() {
        documentField.mark()
        needsRender = true
        parentFrame?.setNeedsLayout()
        requestAnimationFrame()
    }

    func setNeedsViewportResize() {
        document?.widthField.mark()
        document?.zoomField.mark()
        if !mediaMatches.isEmpty, !flippedMediaQueries(currentMedia()).isEmpty {
            invalidateStyle(fromViewport: true)
        } else {
            setNeedsLayout()
        }
    }

    func setNeedsPaint() {
        paintEpoch += 1
        needsPaint = true
        needsRender = true
        parentFrame?.setNeedsPaint()
        requestAnimationFrame()
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
        document?.zoomField.mark()
        document?.widthField.mark()
        if parentFrame == nil, let tab {
            frameWidth = tab.tabWidth / newZoom
            frameHeight = tab.tabHeight / newZoom
        }
        if let tab {
            for child in tab.windowIDToFrame.values where child.parentFrame === self {
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
        for query in mediaQueries where mediaMatches[query] != media.matches(query) {
            flipped.insert(query)
        }
        return flipped
    }

    private func scopedStyleScope(
        _ flipped: Set<String>
    ) -> StyleScope? {
        var rules: [(selector: any CSSSelector, body: [String: String])] = []
        for rule in sortedRules {
            guard let query: String = rule.0, flipped.contains(query) else { continue }
            rules.append((rule.1, rule.2))
        }
        profiler.count("style.scope.rules", by: rules.count)
        guard !rules.isEmpty else { return StyleScope(direct: []) }
        guard rules.count <= 64 else { return nil } // NOTE: why 64?

        var direct: Set<ObjectIdentifier> = []
        for node in treeToList(nodes) {
            guard let element: Element = node as? Element else { continue }
            for rule in rules {
                if rule.selector.matches(element) {
                    StyleInvalidation.markNode(node)
                    direct.insert(ObjectIdentifier(node))
                    break
                }
            }
        }
        return StyleScope(direct: direct)
    }

    private func recordMediaMatches(_ media: MediaFeatures) {
        mediaMatches = mediaQueries.reduce(into: [:], { verdicts, query in
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
