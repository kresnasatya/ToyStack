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
    var document: DocumentLayout?
    var displayList: [any DisplayItem] = []
    var paintRevision: UInt = 0
    var title: String = "New Tab"
    var isSecure: Bool = false

    var scroll: CGFloat = 0
    var frameWidth: CGFloat
    var frameHeight: CGFloat
    var loaded: Bool = false

    private(set) var focus: Element?
    var rules: [(String?, any CSSSelector, [String: String])] = []
    var keyframes: [String: [Keyframe]] = [:]
    private var allowedOrigins: [String]?
    private var referrerPolicy: String = ""
    private var loadedScriptURLs: Set<String> = []
    var js: JSRuntime!

    private var compositedUpdates: [ObjectIdentifier: BrowserVisualEffect] = [:]

    var needsRender: Bool = false
    var needsStyle: Bool = false
    var needsLayout: Bool = false
    var needsPaint: Bool = false
    var needsCompositeForPaint: Bool = false
    private var needsComposite: Bool = false
    var needsFocusScroll: Bool = false

    private(set) var interestTop: CGFloat = 0
    private var interestBottom: CGFloat { interestTop + 4 * frameHeight }
    private var scrollFocusNode: Element? = nil
    private var scrollTween: ScrollTween? = nil
    private var paintedBottom: CGFloat = 0
    private var zoom: CGFloat = 1.0

    var hasScrollElement: Bool { scrollFocusNode != nil }

    var maxScroll: CGFloat {
        let padded: CGFloat = (document?.height ?? 0) + 2 * VSTEP
        return max(max(padded, paintedBottom + VSTEP) - frameHeight, 0)
    }

    private var browser: Browser? { tab?.browser }

    init(tab: BrowserTab, parent: FrameParent?, frameWidth: CGFloat, frameHeight: CGFloat) {
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
            let images: [(index: Int, image: CGImage)] = await networkTaskRunner.schedule(name: "fetch-images") {
                await self.fetchImages(urls: resources.imageURLs)
            }
            self.applyImages(images)
            self.browser?.measure.stop("BrowserTab.load.images")

            self.browser?.measure.start("BrowserTab.load.iframes")
            self.loadIframes()
            self.browser?.measure.stop("BrowserTab.load.iframes")

            self.browser?.measure.start("BrowserTab.load.exec")
            self.execScripts(url: url, bodies: scriptBodies)
            self.browser?.measure.stop("BrowserTab.load.exec")

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
            nodes = profiler.measure("load.parse", {
                HTMLParser(body: body).parse()
            })

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
                let images: [ResourceLoad] = elements
                    .filter({ $0.tag == "img" })
                    .enumerated()
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
    ) async -> [(index: Int, image: CGImage)] {
        var result: [(index: Int, image: CGImage)] = []
        var allowed: [ResourceLoad] = []
        for entry in urls {
            guard allowedRequest(entry.url) else {
                print("Blocked image", entry.url.toString(), "due to CSP")
                continue
            }
            allowed.append(entry)
        }
        await withTaskGroup(of: (Int, CGImage).self) { group in
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

    private nonisolated func decodeImage(url: WebURL, referrer: WebURL?) async -> CGImage {
        guard let (_, _, data) = try? await url.requestRawBytes(referrer: referrer),
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let decoded = CGImageSourceCreateImageAtIndex(source, 0, nil)
            else {
            return BrokenImage.image
        }
        return decoded
    }

    private func applyImages(_ images: [(index: Int, image: CGImage)]) {
        let elements: [Element] = treeToList(nodes).compactMap({ $0 as? Element })
        let imgs: [Element] = elements.filter({ $0.tag == "img" })
        for (i, image) in images where i < imgs.count {
            imgs[i].image = image
        }
    }

    private func loadIframes() {
        guard let tab else { return }
        let iframes: [Element] = treeToList(nodes)
            .compactMap({ $0 as? Element })
            .filter({ $0.tag == "iframe" && $0.attributes["src"] != nil })

        for iframe in iframes {
            let documentURL: WebURL = url.resolve(iframe.attributes["src"]!)
            guard allowedRequest(documentURL) else {
                print("Blocked iframe", documentURL.toString(), "due to CSP")
                iframe.frame = nil
                continue
            }
            let parent: FrameParent = FrameParent(frame: self, element: iframe)
            let child: Frame = Frame(tab: tab, parent: parent, frameWidth: 0, frameHeight: 0)
            iframe.frame = child
            child.load(documentURL)
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
    }

    // MARK: - Render

    func render() {
        if needsStyle {
            browser?.measure.start("BrowserTab.style")
            profiler.reset()
            defer { profiler.emitProfile(into: browser?.measure, named: "profile.style") }
            defer { browser?.measure.stop("BrowserTab.style") }

            browser?.measure.start("BrowserTab.style.rules")
            let sortedRules: [(String?, any CSSSelector, [String : String])] = rules.sorted(by: { cascadePriority($0) < cascadePriority($1) })
            let ruleIndex: RuleIndex = RuleIndex(rules: sortedRules)
            profiler.count("style.rules", by: sortedRules.count)
            browser?.measure.stop("BrowserTab.style.rules")

            browser?.measure.start("BrowserTab.style.has")
            precomputeHas(node: nodes, rules: sortedRules)
            browser?.measure.stop("BrowserTab.style.has")

            browser?.measure.start("BrowserTab.style.snapshot")
            var oldStyles: [ObjectIdentifier: [String: String]] = [:]
            for node in treeToList(nodes) {
                oldStyles[ObjectIdentifier(node)] = node.style
            }
            browser?.measure.stop("BrowserTab.style.snapshot")

            browser?.measure.start("BrowserTab.style.apply")
            let media: MediaFeatures = MediaFeatures(
                preferences: ColorPreferences(
                    prefersDark: tab?.prefersDark ?? false,
                    usesForcedColors: tab?.forcedColors ?? false
                ),
                frameWidth: frameWidth / zoom
            )
            let ancestorKeys: AncestorSelectorKeys = AncestorSelectorKeys()
            applyStyle(
                node: nodes,
                index: ruleIndex,
                media: media,
                ancestorKeys: ancestorKeys
            )
            browser?.measure.stop("BrowserTab.style.apply")

            browser?.measure.start("BrowserTab.style.diff")
            for node in treeToList(nodes) {
                let old: [String : String] = oldStyles[ObjectIdentifier(node)] ?? [:]
                let newAnimations: [String : any Animation] = StyleTransitions.diff(node: node, oldStyle: old, newStyle: node.style)
                for (property, animation) in newAnimations {
                    node.animations[property] = animation
                }
            }
            browser?.measure.stop("BrowserTab.style.diff")

            browser?.measure.start("BrowserTab.style.keyframes")
            for node in treeToList(nodes) {
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
            browser?.measure.stop("BrowserTab.style.keyframes")

            browser?.measure.start("BrowserTab.style.visited")
            for node in treeToList(nodes) {
                guard let el = node as? Element, el.tag == "a",
                    let href = el.attributes["href"]
                else {
                    continue
                }
                if tab?.hasVisited(url.resolve(href).toString()) == true {
                    el.style["color"] = (tab?.forcedColors ?? false) ? ForcedColor.visitedText : "purple"
                }
            }
            browser?.measure.stop("BrowserTab.style.visited")

            needsStyle = false
            needsLayout = true
        }

        if needsLayout {
            browser?.measure.start("BrowserTab.layout")
            profiler.reset()
            defer { profiler.emitProfile(into: browser?.measure, named: "profile.layout") }
            defer { browser?.measure.stop("BrowserTab.layout") }
            let doc: DocumentLayout = DocumentLayout(node: nodes)
            doc.layout(availableWidth: frameWidth, zoom: zoom)
            document = doc

            needsLayout = false
            tab?.needsAccessibility = true
            needsPaint = true
        }

        requestAnimationFrame()
    }

    func paint() {
        guard needsPaint else { return }
        browser?.measure.start("BrowserTab.paint")
        profiler.reset()
        defer { profiler.emitProfile(into: browser?.measure, named: "profile.paint") }
        defer { browser?.measure.stop("BrowserTab.paint") }
        guard let doc = document else { return }
        var list: [any DisplayItem] = []
        paintTree(doc, into: &list)
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
        needsComposite = needsStyle || needsLayout || needsPaint
        var needsLayoutUpdate: Bool = false
        browser?.measure.start("BrowserTab.animScan")
        for node in treeToList(nodes) {
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
                    } else if property == "width" || property == "height" {
                        node.style[property] = value
                        needsLayoutUpdate = true
                    } else {
                        node.style[property] = value
                        needsCompositeForPaint = true
                        needsPaint = true
                    }
                } else {
                    node.animations.removeValue(forKey: key)
                    needsCompositeForPaint = true
                    needsPaint = true
                }
            }
        }
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
            scroll: scroll, interestTop: interestTop, interestBottom: interestBottom)
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
        return [bar]
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
        guard let doc = document else { return false }

        if let hit = doc.hitTest(x: x, y: adjustedY),
            let iframe = hit as? IframeLayout,
            let el = iframe.node as? Element,
            let child = el.frame, child.loaded {
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

        let scrollBlock: BlockLayout? = treeToList(doc)
            .compactMap({ $0 as? BlockLayout })
            .first(where: { block in
                guard block.node.style["overflow"] == "scroll" else { return false }
                let r: Rect = block.selfRect()
                return r.left <= x && x < r.right && r.top <= adjustedY && adjustedY < r.bottom
            })
        if let block = scrollBlock, let el = block.node as? Element {
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
        f.attributes["value", default: ""] += char

        setNeedsRender()
    }

    func blur() {
        focusElement(nil)
    }

    func clearFocus() {
        guard let previous = focus else { return }
        previous.isFocused = false
        previous.isFocusVisible = false
        _ = js?.dispatchEvent(type: "blur", elt: previous)
        focus = nil
        setNeedsRender()
    }

    func focusElement(_ node: Element?, showRing: Bool = true) {
        tab?.setFocusedFrame(self)
        if node === focus { return }
        if let previous = focus {
            previous.isFocused = false
            previous.isFocusVisible = false
            _ = js?.dispatchEvent(type: "blur", elt: previous)
        }
        focus = node
        if let node = node {
            node.isFocused = true
            node.isFocusVisible = showRing
            needsFocusScroll = true
            _ = js?.dispatchEvent(type: "focus", elt: node)
        }
        setNeedsRender()
    }

    @discardableResult
    func advanceTab() -> Bool {
        guard document != nil else { return false }
        let focusableElements: [Element] = treeToList(nodes)
            .compactMap({ $0 as? Element })
            .filter({ isFocusable($0) })
            .enumerated()
            .sorted{ (getTabIndex($0.element), $0.offset) < (getTabIndex($1.element), $1.offset) }
            .map(\.element)
        guard !focusableElements.isEmpty else { return false }
        if let current = focus, let idx = focusableElements.firstIndex(where: { $0 === current }) {
            let next: Int = idx + 1
            if next < focusableElements.count {
                focusElement(focusableElements[next])
                return true
            } else {
                focusElement(nil)
                return false
            }
        } else {
            focusElement(focusableElements[0])
            return true
        }
    }

    func click(x: CGFloat, y: CGFloat) {
        focusElement(nil)
        let clickY: CGFloat = y + scroll

        guard let source = document?.hitTest(x: x, y: clickY) else {
            setNeedsRender()
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
                    if parentFrame == nil {
                        if href.hasPrefix("#") {
                            tab?.navigateToFragment(url.resolve(href))
                        } else {
                            tab?.load(url.resolve(href))
                        }
                    } else {
                        load(resolved)
                    }
                    return
                } else if let el = node as? Element, el.tag == "input" {
                    if el.attributes["type"] == "checkbox" {
                        el.isChecked.toggle()
                        setNeedsRender()
                        return
                    }
                    el.attributes["value"] = ""
                    focusElement(el, showRing: true)
                    setNeedsRender()
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
        setNeedsRender()
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
            tab?.load(action, payload: body)
        } else {
            tab?.load(WebURL("\(action.toString())?\(body)"))
        }
    }

    // MARK: - Invalidation

    func setNeedsRender() {
        needsStyle = true
        needsRender = true
        parentFrame?.setNeedsLayout()
        requestAnimationFrame()
    }

    func setNeedsLayout() {
        needsLayout = true
        needsRender = true
        parentFrame?.setNeedsLayout()
        requestAnimationFrame()
    }

    func setNeedsPaint() {
        needsPaint = true
        needsRender = true
        parentFrame?.setNeedsPaint()
        requestAnimationFrame()
    }

    // MARK: - Zoom

    func zoomBy(_ increment: Bool) {
        if increment {
            zoom *= 1.1
            scroll *= 1.1
        } else {
            zoom *= 1 / 1.1
            scroll *= 1 / 1.1
        }
        setNeedsRender()
    }

    func resetZoom() {
        scroll /= zoom
        zoom = 1.0
        setNeedsRender()
    }
}

let defaultStyleSheet: [(String?, any CSSSelector, [String: String])] = {
    guard let url = Bundle.module.url(forResource: "browser", withExtension: "css"),
        let source = try? String(contentsOf: url, encoding: .utf8)
    else { return [] }
    return CSSParser(source).parse().rules
}()
