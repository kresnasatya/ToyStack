import Foundation

private struct HistoryEntry {
    let url: WebURL
    let payload: String?
}

@MainActor
public class Tab {
    public nonisolated(unsafe) static var showAlert: (String, String) -> Void = { title, message in
        print("[alert] \(title): \(message)")
    }
    public nonisolated(unsafe) static var showConfirm: (String, String) -> Bool = { title, message in
        print("[confirm] \(title): \(message)")
        return true
    }
    public nonisolated(unsafe) static var pageSource: ((_ scheme: String, _ path: String) async -> (
        status: Int, headers: [String: String], content: String
    )?)? = nil
    public private(set) var url: WebURL!
    private nonisolated(unsafe) var visitedURL: Set<String> = []
    private(set) var nodes: any DOMNode = Element(tag: "html", attributes: [:], parent: nil)
    private(set) var document: DocumentLayout?
    private(set) var displayList: [any PaintItem] = []
    private var paintEpoch: UInt = 0
    public private(set) var title: String = "New Tab"
    public private(set) var isSecure: Bool = false

    private let SCROLL_STEP: CGFloat = 100
    private var scroll: CGFloat = 0
    public private(set) var tabHeight: CGFloat
    private var tabWidth: CGFloat
    private var history: [HistoryEntry] = []
    private var historyIndex: Int = -1
    private(set) var focus: Element?
    private var allowedOrigins: [String]?
    private var rules: [(String?, any CSSSelector, [String: String])] = []
    private(set) var keyframes: [String: [Keyframe]] = [:]
    var js: JSRuntime!
    private var loadedScriptURLs: Set<String> = []
    private var referrerPolicy: String = ""

    public var canGoBack: Bool { historyIndex > 0 }
    public var canGoForward: Bool { historyIndex < history.count - 1 }

    private(set) var taskRunner: TaskRunner = TaskRunner()
    var networkTaskRunner: NetworkTaskRunner?
    private(set) var accessibilityTree: AccessibilityNode? = nil
    private var compositedUpdates: [ObjectIdentifier: VisualEffect] = [:]

    private var needsRender: Bool = false
    private var needsStyle: Bool = false
    private var needsLayout: Bool = false
    private var needsAccessibility: Bool = false
    private var needsPaint: Bool = false
    private var needsCompositeForPaint: Bool = false
    private var needsFocusScroll: Bool = false

    var prefersDark: Bool = false {
        didSet {
            if oldValue != prefersDark { setNeedsRender() }
        }
    }

    var forcedColors: Bool = false {
        didSet {
            if oldValue != forcedColors { setNeedsRender() }
        }
    }

    private var zoom: CGFloat = 1.0

    private(set) var interestTop: CGFloat = 0
    private var interestBottom: CGFloat { interestTop + 4 * tabHeight }

    private var scrollFocusNode: Element? = nil
    private var scrollTween: ScrollTween? = nil
    private var paintedBottom: CGFloat = 0

    var maxScroll: CGFloat {
        let padded: CGFloat = (document?.height ?? 0) + 2 * VSTEP
        return max(max(padded, paintedBottom + VSTEP) - tabHeight, 0)
    }

    public var hasScrollElement: Bool { scrollFocusNode != nil }

    weak var browser: Browser?

    init(tabHeight: CGFloat, tabWidth: CGFloat) {
        self.tabHeight = tabHeight
        self.tabWidth = tabWidth
    }

    public func load(_ url: WebURL, payload: String? = nil) {
        history = Array(history.prefix(historyIndex + 1))
        history.append(HistoryEntry(url: url, payload: payload))
        historyIndex = history.count - 1
        performLoad(url, payload: payload)
    }

    private func performLoad(_ url: WebURL, payload: String? = nil) {
        guard let networkTaskRunner else { return }
        let referrer: WebURL? = effectiveReferrer(for: url)

        Task {
            self.browser?.measure.start("tab.load")
            defer { self.browser?.measure.stop("tab.load") }

            self.browser?.measure.start("tab.load.page")
            let result: Result<(status: Int, headers: [String : String], content: String), any Error> = await networkTaskRunner.schedule(name: "load\(url.toString())") {
                await self.fetchPage(url: url, referrer: referrer, payload: payload)
            }
            self.browser?.measure.stop("tab.load.page")

            self.browser?.measure.start("tab.load.parseHTML")
            profiler.reset()
            let parsedPage: PageResources? = self.parseHTML(url: url, result: result)
            self.browser?.measure.stop("tab.load.parseHTML")
            profiler.emitProfile(into: self.browser?.measure, named: "profile.load")
            guard let resources = parsedPage else { return }

            self.browser?.measure.start("tab.load.styles")
            let styleBodies: [(index: Int, body: String)] = await networkTaskRunner.schedule(name: "fetch-styles") {
                await self.fetchStyles(urls: resources.styleURLs)
            }
            self.browser?.measure.stop("tab.load.styles")

            self.browser?.measure.start("tab.load.applyStyles")
            self.applyStyles(bodies: styleBodies)
            self.browser?.measure.stop("tab.load.applyStyles")

            self.browser?.measure.start("tab.load.scripts")
            let scriptBodies: [(index: Int, url: WebURL, body: String)] = await networkTaskRunner.schedule(name: "fetch-scripts") {
                await self.fetchScripts(urls: resources.scriptURLs)
            }
            self.browser?.measure.stop("tab.load.scripts")

            self.browser?.measure.start("tab.load.exec")
            self.execScripts(url: url, bodies: scriptBodies)
            self.browser?.measure.stop("tab.load.exec")
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
    ) -> PageResources? {
        let certErrorCodes: [URLError.Code] = [
            .serverCertificateUntrusted, .serverCertificateHasBadDate,
            .serverCertificateNotYetValid, .serverCertificateHasUnknownRoot,
        ]

        switch result {
        case .failure(let error):
            if let urlError = error as? URLError, certErrorCodes.contains(urlError.code) {
                Tab.showAlert("Certificate Error", "The certificate for \(url.host) is invalid. " + "Your connection may not be private.")
            }
            return nil

        case .success(let (_, headers, body)):
            isSecure = url.scheme == "https"
            scroll = 0
            scrollTween = nil
            interestTop = 0
            self.url = url
            visitedURL.insert(url.toString())
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

            js = profiler.measure("load.jsInit", { JSRuntime(tab: self) })

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

            let (styleURLs, scriptURLs): ([ResourceURL], [ResourceURL]) =
            profiler.measure("load.resources", {
                let elements: [Element] = treeToList(nodes).compactMap({ $0 as? Element })
                let styles: [ResourceURL] = elements
                    .filter({ $0.tag == "link" && $0.attributes["rel"] == "stylesheet" && $0.attributes["href"] != nil })
                    .enumerated()
                    .map({ (i, link) in
                        let styleURL: WebURL = url.resolve(link.attributes["href"]!)
                        return (i, styleURL, self.effectiveReferrer(for: styleURL))
                    })
                let scripts: [ResourceURL] = elements
                    .filter({ $0.tag == "script" && $0.attributes["src"] != nil })
                    .enumerated()
                    .map({ (i, node) in
                        let scriptURL: WebURL = url.resolve(node.attributes["src"]!)
                        return (i, scriptURL, self.effectiveReferrer(for: scriptURL))
                    })
                return (styles, scripts)
            })

            return PageResources(styleURLs: styleURLs, scriptURLs: scriptURLs)
        }
    }

    private func fetchStyles(
        urls: [(index: Int, url: WebURL, ref: WebURL?)]
    ) async -> [(index: Int, body: String)] {
        typealias Response = (status: Int, headers: [String: String], content: String)
        var result: [(index: Int, body: String)] = []
        var allowed: [ResourceURL] = []
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
                    Tab.isUsableStylesheet(status: response.status, headers: response.headers, url: styleURL)
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
        var allowed: [ResourceURL] = []
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
                    Tab.isExecutableScript(status: response.status, headers: response.headers, url: scriptURL)
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

    nonisolated static func isExecutableScript(
    status: Int, headers: [String: String], url: WebURL
    ) -> Bool {
        guard status == 200 else {
            print("Refused execute script from", url.toString(), "- server replied", status)
            return false
        }
        guard let contentType = headers["content-type"] else { return true }
        guard MIMEType.isJavaScript(contentType) else {
            print(
                "Refused to execute script from", url.toString(),
                "because it's MIME type (\(MIMEType.essence(contentType))) is not executable"
            )
            return false
        }
        return true
    }

    nonisolated static func isUsableStylesheet(
    status: Int, headers: [String: String], url: WebURL
    ) -> Bool {
        guard status == 200 else {
            print("Refused to apply stylesheet from", url.toString(), "- server replied", status)
            return false
        }
        guard let contentType = headers["content-type"] else { return true }
        guard MIMEType.isCSS(contentType) else {
            print(
                "Refused to apply stylesheet from", url.toString(),
                "because it's MIME type (\(MIMEType.essence(contentType))) is not text/css"
            )
            return false
        }
        return true
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
            guard Tab.isExecutableScript(status: status, headers: headers, url: scriptURL) else { continue }
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
                guard Tab.isUsableStylesheet(status: status, headers: headers, url: styleURL) else { continue }
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

    func render() {
        if needsStyle {
            browser?.measure.start("tab.style")
            profiler.reset()
            defer { profiler.emitProfile(into: browser?.measure, named: "profile.style") }
            defer { browser?.measure.stop("tab.style") }

            browser?.measure.start("tab.style.rules")
            let sortedRules: [(String?, any CSSSelector, [String : String])] = rules.sorted(by: { cascadePriority($0) < cascadePriority($1) })
            let ruleIndex: RuleIndex = RuleIndex(rules: sortedRules)
            profiler.count("style.rules", by: sortedRules.count)
            browser?.measure.stop("tab.style.rules")

            browser?.measure.start("tab.style.has")
            precomputeHas(node: nodes, rules: sortedRules)
            browser?.measure.stop("tab.style.has")

            browser?.measure.start("tab.style.snapshot")
            var oldStyles: [ObjectIdentifier: [String: String]] = [:]
            for node in treeToList(nodes) {
                oldStyles[ObjectIdentifier(node)] = node.style
            }
            browser?.measure.stop("tab.style.snapshot")

            inheritedProperties["color"] = forcedColors ? ForcedColor.canvasText : (prefersDark ? "white" : "black")
            browser?.measure.start("tab.style.apply")
            let context: StyleContext = StyleContext(
                rules: ruleIndex,
                theme: ThemeState(prefersDark: prefersDark, forcedColors: forcedColors),
                frameWidth: tabWidth / zoom
            )
            applyStyle(
                node: nodes,
                context: context,
                ancestors: AncestorScope()
            )
            browser?.measure.stop("tab.style.apply")

            browser?.measure.start("tab.style.diff")
            for node in treeToList(nodes) {
                let old: [String : String] = oldStyles[ObjectIdentifier(node)] ?? [:]
                let newAnimations: [String : any Animation] = StyleTransitions.diff(node: node, oldStyle: old, newStyle: node.style)
                for (property, animation) in newAnimations {
                    node.animations[property] = animation
                }
            }
            browser?.measure.stop("tab.style.diff")

            browser?.measure.start("tab.style.keyframes")
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
            browser?.measure.stop("tab.style.keyframes")

            browser?.measure.start("tab.style.visited")
            for node in treeToList(nodes) {
                guard let el = node as? Element, el.tag == "a",
                    let href = el.attributes["href"]
                else {
                    continue
                }
                if visitedURL.contains(url.resolve(href).toString()) {
                    el.style["color"] = forcedColors ? ForcedColor.visitedText : "purple"
                }
            }
            browser?.measure.stop("tab.style.visited")

            needsStyle = false
            needsLayout = true
        }

        if needsLayout {
            browser?.measure.start("tab.layout")
            profiler.reset()
            defer { profiler.emitProfile(into: browser?.measure, named: "profile.layout") }
            defer { browser?.measure.stop("tab.layout") }
            let doc: DocumentLayout = DocumentLayout(node: nodes)
            doc.layout(availableWidth: tabWidth, zoom: zoom)
            document = doc

            needsLayout = false
            needsAccessibility = true
            needsPaint = true
        }

        if needsAccessibility {
            browser?.measure.start("tab.a11y")
            defer { browser?.measure.stop("tab.a11y") }
            let a11yTree: AccessibilityNode = AccessibilityNode(node: nodes)
            a11yTree.build()
            accessibilityTree = a11yTree

            needsAccessibility = false
        }

        if needsPaint {
            browser?.measure.start("tab.paint")
            profiler.reset()
            defer { profiler.emitProfile(into: browser?.measure, named: "profile.paint") }
            defer { browser?.measure.stop("tab.paint") }
            guard let doc = document else { return }
            var list: [any PaintItem] = []
            paintTree(doc, into: &list)
            displayList = list
            paintedBottom = maxRectBottom(list)
            paintEpoch += 1
            needsPaint = false
        }

        browser?.setNeedsAnimationFrame(self)
    }

    func runAnimationFrame() {
        guard js != nil else { return }
        browser?.measure.start("tab.animFrame")
        defer { browser?.measure.stop("tab.animFrame") }
        browser?.measure.start("tab.raf")
        js.run(script: "raf", code: "__runRAFHandlers()")
        browser?.measure.stop("tab.raf")
        var needsAnotherFrame: Bool = false
        let needsComposite: Bool = needsStyle || needsLayout || needsPaint
        var needsPaint: Bool = false
        var needsLayoutUpdate: Bool = false
        browser?.measure.start("tab.animScan")
        for node in treeToList(nodes) {
            for (key, animation) in node.animations {
                let property: String = animation.animatedProperty
                if let value = animation.nextValue() {
                    needsAnotherFrame = true
                    if property == "transform" || property == "opacity"
                    {
                        node.style[property] = value
                        if let rect = (node.layoutObject as? BlockLayout)?.selfRect(),
                            let effect = paintVisualEffects(node: node, items: [], rect: rect).first
                                as? VisualEffect
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
        browser?.measure.stop("tab.animScan")

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
            browser?.setNeedsAnimationFrame(self)
        }

        let updates: [ObjectIdentifier: VisualEffect]? =
            (needsComposite || needsCompositeForPaint) ? nil : compositedUpdates
        let data: CommitData = CommitData(
            scrollState: ScrollState(scroll: scroll, interestTop: interestTop, interestBottom: interestBottom, maxScroll: maxScroll),
            paint: PaintResult(displayList: displayList, compositedUpdates: updates, paintEpoch: paintEpoch),
            theme: ThemeState(prefersDark: prefersDark, forcedColors: forcedColors)
        )
        compositedUpdates = [:]
        needsCompositeForPaint = false
        browser?.commit(tab: self, data: data)
    }

    private func scrollTo(_ elt: Element) {
        scrollTween = nil
        guard let doc = document else { return }
        let objs: [any LayoutObject] = treeToList(doc).filter({ $0.node === elt || $0.node.parent === elt })
        guard let obj = objs.first else { return }
        if scroll < obj.y && obj.y + obj.height < scroll + tabHeight { return }
        scroll = max(0, min(obj.y - SCROLL_STEP, maxScroll))
        interestTop = max(0, scroll - tabHeight)
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

    public func linkURL(at x: CGFloat, y: CGFloat) -> WebURL? {
        guard let href = document?.linkElement(at: x, y: y + scroll)?.attributes["href"] else { return nil }
        return url?.resolve(href)
    }

    public func scrollbarCommands() -> [any PaintCommand] {
        guard let doc = document else { return [] }
        guard let bar = scrollbarBarRect(
            ScrollbarGeometry(
                docHeight: doc.height + 2 * VSTEP,
                contentHeight: tabHeight,
                contentWidth: tabWidth,
                scroll: scroll
            ),
            forcedColors: forcedColors
        ) else { return [] }
        return [bar]
    }

    public func resize(width: CGFloat, height: CGFloat) {
        tabWidth = width
        tabHeight = height

        setNeedsRender()
    }

    public func scrollDown() {
        if let tween = scrollTween {
            tween.aim(from: scroll, by: SCROLL_STEP, within: 0...maxScroll)
        } else {
            scrollTween = ScrollTween(from: scroll, to: min(scroll + SCROLL_STEP, maxScroll))
        }
        browser?.setNeedsAnimationFrame(self)
    }

    public func scrollUp() {
        if let tween = scrollTween {
            tween.aim(from: scroll, by: -SCROLL_STEP, within: 0...maxScroll)
        } else {
            scrollTween = ScrollTween(from: scroll, to: max(scroll - SCROLL_STEP, 0))
        }
        browser?.setNeedsAnimationFrame(self)
    }

    public func scrollAt(x: CGFloat, y: CGFloat, deltaY: CGFloat) {
        let adjustedY: CGFloat = y + scroll
        guard let doc = document else { return }
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
            el.scrollOffsetY = max(0, min(current - deltaY, maxScroll))
            block.scrollOffset = el.scrollOffsetY
            scrollFocusNode = el
            setNeedsPaint()
        } else {
            scrollBy(deltaY: deltaY)
        }
    }

    public func scrollBy(deltaY: CGFloat) {
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

    public func scrollElementDown() {
        guard let node = scrollFocusNode, let block = liveScrollBlock() else {
            return
        }
        let maxScroll: CGFloat = max(0, block.contentHeight - block.height)
        let current: CGFloat = min(node.scrollOffsetY, maxScroll)
        node.scrollOffsetY = min(current + SCROLL_STEP, maxScroll)
        block.scrollOffset = node.scrollOffsetY
        setNeedsPaint()
    }

    public func scrollElementUp() {
        guard let node = scrollFocusNode, let block = liveScrollBlock() else { return }
        let maxScroll: CGFloat = max(0, block.contentHeight - block.height)
        let current: CGFloat = min(node.scrollOffsetY, maxScroll)
        node.scrollOffsetY = max(current - SCROLL_STEP, 0)
        block.scrollOffset = node.scrollOffsetY
        setNeedsPaint()
    }

    @discardableResult
    private func checkInterestRegion() -> Bool {
        let interestBottom: CGFloat = interestTop + 4 * tabHeight
        if scroll < interestTop || scroll + tabHeight > interestBottom {
            interestTop = max(0, scroll - tabHeight)
            browser?.applyScrollAndUpdateInterest(scroll: scroll, interestTop: interestTop, interestBottom: interestBottom)
            return true
        }
        return false
    }

    private func isSameDocument(_ a: WebURL, _ b: WebURL) -> Bool {
        return a.scheme == b.scheme
            && a.host == b.host
            && a.port == b.port
            && a.path == b.path
    }

    public func goBack() {
        guard canGoBack else { return }
        historyIndex -= 1
        let entry: HistoryEntry = history[historyIndex]
        if let payload = entry.payload {
            if Tab.showConfirm("Resubmit form?", "This page was loaded by submitting a form. Do you want to resubmit it?") {
                performLoad(entry.url, payload: payload)
            } else {
                historyIndex += 1
            }
        } else if let currentURL = self.url, isSameDocument(currentURL, entry.url) {
            self.url = entry.url
            if let fragment = entry.url.fragment {
                scrollToFragment(fragment)
            } else {
                scroll = 0
            }
            interestTop = max(0, scroll - tabHeight)
            browser?.applyScrollAndUpdateInterest(scroll: scroll, interestTop: interestTop, interestBottom: interestBottom)
        } else {
            performLoad(entry.url)
        }
    }

    public func goForward() {
        guard canGoForward else { return }
        historyIndex += 1
        let entry: HistoryEntry = history[historyIndex]
        if let currentURL = self.url, isSameDocument(currentURL, entry.url) {
            self.url = entry.url
            if let fragment = entry.url.fragment {
                scrollToFragment(fragment)
            } else {
                scroll = 0
            }
            interestTop = max(0, scroll - tabHeight)
            browser?.applyScrollAndUpdateInterest(scroll: scroll, interestTop: interestTop, interestBottom: interestBottom)
        } else {
            performLoad(entry.url, payload: entry.payload)
        }
    }

    public func keypress(_ char: String) {
        guard let f = focus else { return }
        if js.dispatchEvent(type: "keydown", elt: f) { return }
        f.attributes["value", default: ""] += char

        setNeedsRender()
    }

    public func blur() {
        focusElement(nil)
    }

    func focusElement(_ node: Element?, showRing: Bool = true) {
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
    public func advanceTab() -> Bool {
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

    public func click(x: CGFloat, y: CGFloat) {
        focusElement(nil)

        guard let source = document?.hitTest(x: x, y: y + scroll) else {
            setNeedsRender()
            return
        }

        scrollFocusNode = scrollableAncestor(of: source)

        let prevented: Bool = js.dispatchEvent(type: "click", elt: source.node)

        if !prevented {
            var elt: (any DOMNode)? = source.node
            while let node = elt {
                if node is TextNode {

                } else if let el = node as? Element, el.tag == "a", let href = el.attributes["href"]
                {
                    if href.hasPrefix("#") {
                        let resolved: WebURL = url.resolve(href)
                        history = Array(history.prefix(historyIndex + 1))
                        history.append(HistoryEntry(url: resolved, payload: nil))
                        historyIndex = history.count - 1
                        self.url = resolved
                        scrollToFragment(String(href.dropFirst()))
                        interestTop = max(0, scroll - tabHeight)
                        browser?.applyScrollAndUpdateInterest(scroll: scroll, interestTop: interestTop, interestBottom: interestBottom)
                    } else {
                        load(url.resolve(href))
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

    public func enterKey() {
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
            load(action, payload: body)
        } else {
            load(WebURL("\(action.toString())?\(body)"))
        }
    }

    func setNeedsRender() {
        needsStyle = true
        needsRender = true
        browser?.setNeedsAnimationFrame(self)
    }

    func setNeedsLayout() {
        needsLayout = true
        needsRender = true
        browser?.setNeedsAnimationFrame(self)
    }

    func setNeedsPaint() {
        needsPaint = true
        needsRender = true
        browser?.setNeedsAnimationFrame(self)
    }

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

private let defaultStyleSheet: [(String?, any CSSSelector, [String: String])] = {
    guard let url = Bundle.module.url(forResource: "browser", withExtension: "css"),
        let source = try? String(contentsOf: url, encoding: .utf8)
    else { return [] }
    return CSSParser(source).parse().rules
}()

private func maxRectBottom(_ items: [any PaintItem]) -> CGFloat {
    var result: CGFloat = 0
    for item in items {
        if let cmd = item as? any PaintCommand {
            result = max(result, cmd.rect.bottom)
        } else if let ve = item as? Engine.VisualEffect {
            result = max(result, ve.rect.bottom)
            result = max(result, maxRectBottom(ve.children))
        }
    }
    return result
}
