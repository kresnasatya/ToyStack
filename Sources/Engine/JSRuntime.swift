import Foundation
import JavaScriptCore

class JSRuntime: @unchecked Sendable {
    private let jsContext = JSContext()!
    private var nodeToHandle: [ObjectIdentifier: Int] = [:]
    private var handleToNode: [Int: any DOMNode] = [:]
    private var intervalTimes: [Int: DispatchSourceTimer] = [:]
    private weak var tab: Engine.Tab?

    private static let eventDispatchJS = "new Node(__handle).dispatchEvent(new Event(__type))"

    init(tab: Engine.Tab) {
        self.tab = tab
        registerCallbacks()
        loadRuntime()
    }

    // MARK: - Public

    func run(script: String, code: String) {
        jsContext.exceptionHandler = { _, exception in
            print("Script", script, "crashed:", exception?.toString() ?? "unknown error")
        }
        jsContext.evaluateScript(code)
    }

    func dispatchEvent(type: String, elt: any DOMNode) -> Bool {
        let handle = nodeToHandle[ObjectIdentifier(elt)]
        jsContext.setObject(handle, forKeyedSubscript: "__handle" as NSString)
        jsContext.setObject(type, forKeyedSubscript: "__type" as NSString)
        let result = jsContext.evaluateScript(Self.eventDispatchJS)
        return !(result?.toBool() ?? true)
    }

    // MARK: - Private

    private func getHandle(_ elt: any DOMNode) -> Int {
        let id = ObjectIdentifier(elt)
        if let handle = nodeToHandle[id] { return handle }
        let handle = nodeToHandle.count
        nodeToHandle[id] = handle
        handleToNode[handle] = elt
        return handle
    }

    private func serialize(_ node: any DOMNode) -> String {
        if let text = node as? TextNode {
            return text.text
        }
        guard let elt = node as? Element else { return "" }
        let attrs = elt.attributes.map { " \($0.key)=\($0.value)" }.joined()
        let inner = elt.children.map { serialize($0) }.joined()
        return "<\(elt.tag)\(attrs)>\(inner)</\(elt.tag)>"
    }

    private func registerCallbacks() {
        jsContext.setObject(
            {
                (msg: String) in print(msg)
            } as @convention(block) (String) -> Void, forKeyedSubscript: "_log" as NSString)

        jsContext.setObject(
            {
                [weak self] (selectorText: String) -> [Int] in
                guard let self, let tab = self.tab else { return [] }
                return MainActor.assumeIsolated({
                    let selector = CSSParser(selectorText).selector()
                    let nodes = treeToList(tab.nodes).filter { selector.matches($0) }
                    return nodes.map { self.getHandle($0) }
                })
            } as @convention(block) (String) -> [Int],
            forKeyedSubscript: "_querySelectorAll" as NSString
        )

        jsContext.setObject(
            {
                [weak self] () -> [String: Int] in
                guard let self, let tab = self.tab else { return [:] }
                return MainActor.assumeIsolated({
                    var result: [String: Int] = [:]
                    for node in treeToList(tab.nodes) {
                        guard let elt = node as? Element,
                            let id = elt.attributes["id"]
                        else { continue }
                        result[id] = self.getHandle(elt)
                    }
                    return result
                })
            } as @convention(block) () -> [String: Int],
            forKeyedSubscript: "_getIDs" as NSString)

        jsContext.setObject(
            {
                [weak self] (handle: Int, attr: String) -> String in
                guard let self, let elt = self.handleToNode[handle] as? Element else { return "" }
                return elt.attributes[attr] ?? ""
            } as @convention(block) (Int, String) -> String,
            forKeyedSubscript: "_getAttribute" as NSString)

        jsContext.setObject(
            {
                [weak self] (handle: Int, attr: String, value: String) in
                guard let self, let elt = self.handleToNode[handle] as? Element else { return }
                elt.attributes[attr] = value
            } as @convention(block) (Int, String, String) -> Void,
            forKeyedSubscript: "_setAttribute" as NSString)

        jsContext.setObject(
            {
                [weak self] () -> String in
                guard let self, let tab = self.tab else { return "" }
                let host = MainActor.assumeIsolated({ tab.url?.host ?? "" })
                guard !host.isEmpty else { return "" }
                var result = ""
                let semaphore = DispatchSemaphore(value: 0)
                Task {
                    if let (cookie, params) = await CookieJar.shared.get(host) {
                        if params["httponly"] != "true" {
                            result = cookie
                        }
                    }
                    semaphore.signal()
                }
                semaphore.wait()
                return result
            } as @convention(block) () -> String,
            forKeyedSubscript: "_getCookie" as NSString)

        jsContext.setObject(
            {
                [weak self] (cookieStr: String) in
                guard let self, let tab = self.tab else { return }
                let host = MainActor.assumeIsolated({ tab.url?.host ?? "" })
                guard !host.isEmpty else { return }
                let semaphore = DispatchSemaphore(value: 0)
                Task {
                    // Block if existing cookie has HttpOnly
                    if let (_, params) = await CookieJar.shared.get(host) {
                        if params["httponly"] == "true" {
                            semaphore.signal()
                            return
                        }
                    }

                    // Parse the new cookie string (same logic as Set-Cookie header in WebURL.swift)
                    var newCookieStr = cookieStr
                    var cookieParams: [String: String] = [:]
                    if cookieStr.contains(";") {
                        let parts = cookieStr.split(separator: ";", maxSplits: 1)
                        newCookieStr = String(parts[0])
                        if parts.count > 1 {
                            for param in String(parts[1]).split(separator: ";") {
                                let trimmed = param.trimmingCharacters(in: .whitespaces)
                                if trimmed.contains("=") {
                                    let kv = trimmed.split(separator: "=", maxSplits: 1)
                                    cookieParams[String(kv[0]).lowercased()] = String(kv[1])
                                        .lowercased()
                                } else {
                                    // Js cannot set HttpOnly - silently ignore it
                                    let key = trimmed.lowercased()
                                    if key != "httponly" {
                                        cookieParams[key] = "true"
                                    }
                                }
                            }
                        }
                    }
                    await CookieJar.shared.set(host, cookie: newCookieStr, params: cookieParams)
                    semaphore.signal()
                }
                semaphore.wait()
            } as @convention(block) (String) -> Void, forKeyedSubscript: "_setCookie" as NSString)

        jsContext.setObject(
            {
                [weak self] (handle: Int) -> Int in
                guard let self, let node = self.handleToNode[handle] else { return -1 }
                guard let parent = node.parent else { return -1 }
                return self.getHandle(parent)
            } as @convention(block) (Int) -> Int,
            forKeyedSubscript: "_getParent" as NSString)

        jsContext.setObject(
            {
                [weak self] (handle: Int) -> String in
                guard let self, let node = self.handleToNode[handle] else { return "" }
                return node.children.map { self.serialize($0) }.joined()
            } as @convention(block) (Int) -> String,
            forKeyedSubscript: "_serializeInner" as NSString)

        jsContext.setObject(
            {
                [weak self] (handle: Int) -> String in
                guard let self, let node = self.handleToNode[handle] else { return "" }
                return self.serialize(node)
            } as @convention(block) (Int) -> String,
            forKeyedSubscript: "_serializeOuter" as NSString)

        jsContext.setObject(
            {
                [weak self] (handle: Int, s: String) in
                MainActor.assumeIsolated({
                    guard let self, let tab = self.tab,
                        let elt = self.handleToNode[handle] as? Element
                    else { return }
                    let doc = HTMLParser(body: "<html><body>\(s)</body></html>").parse()
                    let newNodes = (doc.children.first as? Element)?.children
                    elt.children = newNodes ?? []
                    for child in elt.children { child.parent = elt }
                    tab.runNewScripts(in: elt)
                    tab.reloadStylesheets()
                    tab.setNeedsRender()
                })
            } as @convention(block) (Int, String) -> Void,
            forKeyedSubscript: "_innerHTML" as NSString)

        jsContext.setObject(
            {
                [weak self] (handle: Int) -> [Int] in
                guard let self, let node = self.handleToNode[handle] else { return [] }
                return node.children
                    .compactMap({ $0 as? Element })
                    .map({ self.getHandle($0) })
            } as @convention(block) (Int) -> [Int],
            forKeyedSubscript: "_children" as NSString)

        jsContext.setObject(
            {
                [weak self] (tag: String) -> Int in
                guard let self else { return -1 }
                let elt = Element(tag: tag, attributes: [:], parent: nil)
                return self.getHandle(elt)
            } as @convention(block) (String) -> Int,
            forKeyedSubscript: "_createElement" as NSString)

        jsContext.setObject(
            {
                [weak self] (parentHandle: Int, childHandle: Int) in
                MainActor.assumeIsolated({
                    guard let self, let tab = self.tab,
                        let parent = self.handleToNode[parentHandle],
                        let child = self.handleToNode[childHandle]
                    else { return }
                    child.parent = parent
                    parent.children.append(child)
                    tab.runNewScripts(in: child)
                    tab.reloadStylesheets()
                    tab.setNeedsRender()
                })
            } as @convention(block) (Int, Int) -> Void,
            forKeyedSubscript: "_appendChild" as NSString)

        jsContext.setObject(
            {
                [weak self] (parentHandle: Int, childHandle: Int) -> Int in
                return MainActor.assumeIsolated({
                    guard let self, let tab = self.tab,
                        let parent = self.handleToNode[parentHandle],
                        let child = self.handleToNode[childHandle]
                    else { return -1 }
                    parent.children.removeAll { $0 === child }
                    child.parent = nil
                    tab.reloadStylesheets()
                    tab.setNeedsRender()
                    return childHandle
                })
            } as @convention(block) (Int, Int) -> Int,
            forKeyedSubscript: "_removeChild" as NSString)

        jsContext.setObject(
            {
                [weak self] (parentHandle: Int, childHandle: Int, refHandle: Int) in
                MainActor.assumeIsolated({
                    guard let self, let tab = self.tab,
                        let parent = self.handleToNode[parentHandle],
                        let child = self.handleToNode[childHandle],
                        let ref = self.handleToNode[refHandle],
                        let idx = parent.children.firstIndex(where: { $0 === ref })
                    else { return }
                    child.parent = parent
                    parent.children.insert(child, at: idx)
                    tab.runNewScripts(in: child)
                    tab.reloadStylesheets()
                    tab.render()
                })
            } as @convention(block) (Int, Int, Int) -> Void,
            forKeyedSubscript: "_insertBefore" as NSString)

        jsContext.setObject(
            {
                [weak self] (method: String, url: String, body: String?) -> String in
                return MainActor.assumeIsolated({
                    guard let self, let tab = self.tab else { return "" }
                    let fullURL = tab.url.resolve(url)
                    guard tab.allowedRequest(fullURL) else {
                        print("Cross-origin XHR blocked by CSP")
                        return ""
                    }
                    // Same-origin: proceed directly
                    if fullURL.origin() == tab.url.origin() {
                        guard let (_, out) = fullURL.requestSync(payload: body) else { return "" }
                        return out
                    }
                    // Cross-origin: send Origin header, check Access-Control-Allow-Origin
                    let origin = tab.url.origin()
                    guard
                        let (headers, out) = fullURL.requestSync(
                            payload: body,
                            extraHeaders: ["Origin": origin]
                        )
                    else { return "" }
                    let allowed = headers["access-control-allow-origin"] ?? ""
                    guard allowed == "*" || allowed == origin else {
                        print("Cross-origin XHR request not allowed")
                        return ""
                    }
                    return out
                })
            } as @convention(block) (String, String, String?) -> String,
            forKeyedSubscript: "_XHRSend" as NSString)

        // requestAnimationFrame - schedules one animation frame on the tab
        jsContext.setObject(
            {
                [weak self] in
                guard let tab = self?.tab else { return }
                Task { @MainActor in
                    guard tab.browser?.activeTab === tab else { return }
                    let task = BrowserTask(name: "runAnimationFrame", measure: tab.browser?.measure)
                    {
                        tab.runAnimationFrame()
                    }
                    tab.taskRunner.scheduleTask(task)
                }
            } as @convention(block) () -> Void,
            forKeyedSubscript: "requestAnimationFrame" as NSString)

        // __setTimeout - schedules a JS callback after a delay (milliseconds)
        jsContext.setObject(
            {
                [weak self] (handle: Int, time: Double) in
                guard let tab = self?.tab else { return }
                let delay = time / 1000.0
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    Task { @MainActor in
                        let task = BrowserTask(name: "runSetTimeout", measure: tab.browser?.measure)
                        {
                            tab.js.run(script: "setTimeout", code: "__runSetTimeout(\(handle))")
                        }
                        tab.taskRunner.scheduleTask(task)
                    }
                }
            } as @convention(block) (Int, Double) -> Void,
            forKeyedSubscript: "__setTimeout" as NSString)

        //  __setInterval - fires repeatly every `time` ms until clearInterval
        jsContext.setObject(
            {
                [weak self] (handle: Int, time: Double) in
                guard let tab = self?.tab else { return }
                let interval = time / 1000.0
                let timer = DispatchSource.makeTimerSource(queue: .main)
                timer.schedule(deadline: .now() + interval, repeating: interval)
                timer.setEventHandler(handler: {
                    Task { @MainActor in
                        guard tab.browser?.activeTab === tab else { return }
                        let task = BrowserTask(
                            name: "runSetInterval", measure: tab.browser?.measure
                        ) {
                            tab.js.run(script: "setInterval", code: "__runSetInterval(\(handle))")
                        }
                        tab.taskRunner.scheduleTask(task)
                    }
                })
                timer.resume()
                self?.intervalTimes[handle] = timer
            } as @convention(block) (Int, Double) -> Void,
            forKeyedSubscript: "__setInterval" as NSString)

        // __clearInterval - cancels a previously scheduled interval
        jsContext.setObject(
            {
                [weak self] (handle: Int) in
                guard let self else { return }
                if let timer = self.intervalTimes[handle] {
                    timer.setEventHandler(handler: nil)
                    timer.cancel()
                    self.intervalTimes.removeValue(forKey: handle)
                }
            } as @convention(block) (Int) -> Void, forKeyedSubscript: "__clearInterval" as NSString)

        jsContext.setObject(
            {
                [weak self] (handle: Int, value: Double) in
                MainActor.assumeIsolated({
                    guard let self, let elt = self.handleToNode[handle] as? Element,
                        let tab = self.tab
                    else { return }
                    elt.scrollOffsetY = CGFloat(value)
                    print(
                        "[scrollTop] elt=\(elt.tag)#\(elt.attributes["id"] ?? "?") value=\(value) stored=\(elt.scrollOffsetY)"
                    )
                    // For `_setScrollTop` — only scroll offset changed, no structure/style change, need paint only.
                    tab.setNeedsPaint()
                })
            } as @convention(block) (Int, Double) -> Void,
            forKeyedSubscript: "_setScrollTop" as NSString)

        // __styleSet__ - sets a CSS property on a node from JS, triggers re-render
        jsContext.setObject(
            {
                [weak self] (handle: Int, attr: String, value: String) in
                guard let self = self, let node = self.handleToNode[handle] else { return }
                Task {
                    @MainActor in
                    node.style[attr] = value
                    self.tab?.setNeedsRender()
                    self.tab?.render()
                }
            } as @convention(block) (Int, String, String) -> Void,
            forKeyedSubscript: "__styleSet__" as NSString)
    }

    deinit {
        for timer in intervalTimes.values {
            timer.setEventHandler(handler: nil)
            timer.cancel()
        }
    }

    func defineIDs() {
        jsContext.evaluateScript("__defineIDs()")
    }

    private func loadRuntime() {
        guard let url = Bundle.module.url(forResource: "runtime", withExtension: "js"),
            let source = try? String(contentsOf: url, encoding: .utf8)
        else {
            fatalError("runtime.js not found in bundle")
        }
        jsContext.evaluateScript(source)
    }
}
