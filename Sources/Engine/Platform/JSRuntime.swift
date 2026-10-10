import Foundation
import JavaScriptCore

class JSRuntime: @unchecked Sendable {
    private let jsContext: JSContext
    private var nodeToHandle: [ObjectIdentifier: Int] = [:]
    private var handleToNode: [Int: any DOMNode] = [:]
    private var intervalTimes: [Int: DispatchSourceTimer] = [:]
    private weak var frame: Frame?

    private static let eventDispatchJS: String = "new Node(__handle).dispatchEvent(new Event(__type))"

    init(frame: Frame) {
        self.frame = frame
        self.jsContext = profiler.measure("jsc.context", { JSContext()! })
        profiler.measure("jsc.callbacks", { registerCallbacks() })
        profiler.measure("jsc.runtime", { loadRuntime() })
    }

    func run(script: String, code: String) {
        jsContext.exceptionHandler = { _, exception in
            print("Script", script, "crashed:", exception?.toString() ?? "unknown error")
        }
        jsContext.evaluateScript(code)
    }

    func dispatchEvent(type: String, elt: any DOMNode) -> Bool {
        let handle: Int = getHandle(elt)
        jsContext.setObject(handle, forKeyedSubscript: "__handle" as NSString)
        jsContext.setObject(type, forKeyedSubscript: "__type" as NSString)
        let result: JSValue? = jsContext.evaluateScript(Self.eventDispatchJS)
        return !(result?.toBool() ?? true)
    }

    func dispatchPostMessage(message: String) {
        jsContext.setObject(message, forKeyedSubscript: "__data" as NSString)
        jsContext.evaluateScript("window.dispatchEvent(new window.MessageEvent(__data))")
    }

    private func getHandle(_ elt: any DOMNode) -> Int {
        let id: ObjectIdentifier = ObjectIdentifier(elt)
        if let handle = nodeToHandle[id] { return handle }
        let handle: Int = nodeToHandle.count
        nodeToHandle[id] = handle
        handleToNode[handle] = elt
        return handle
    }

    private func serialize(_ node: any DOMNode) -> String {
        if let text = node as? TextNode {
            return text.text
        }
        guard let elt = node as? Element else { return "" }
        let attrs: String = elt.attributes.map { " \($0.key)=\($0.value)" }.joined()
        let inner: String = elt.children.map { serialize($0) }.joined()
        return "<\(elt.tag)\(attrs)>\(inner)</\(elt.tag)>"
    }

    private func textContent(of node: any DOMNode) -> String {
        if let text = node as? TextNode { return text.text }
        guard let elt = node as? Element else { return "" }
        return elt.children.map { self.textContent(of: $0) }.joined()
    }

    private func registerCallbacks() {
        jsContext.setObject(
            {
                (msg: String) in print(msg)
            } as @convention(block) (String) -> Void, forKeyedSubscript: "_log" as NSString)

        jsContext.setObject(
            {
                [weak self] (selectorText: String) -> [Int] in
                guard let self, let frame = self.frame else { return [] }
                return MainActor.assumeIsolated({
                    let selector: any CSSSelector = CSSParser(selectorText).selector()
                    let nodes: [any DOMNode] = treeToList(frame.nodes).filter { selector.matches($0) }
                    return nodes.map { self.getHandle($0) }
                })
            } as @convention(block) (String) -> [Int],
            forKeyedSubscript: "_querySelectorAll" as NSString
        )

        jsContext.setObject(
            {
                [weak self] () -> [String: Int] in
                guard let self, let frame = self.frame else { return [:] }
                return MainActor.assumeIsolated({
                    var result: [String: Int] = [:]
                    for node in treeToList(frame.nodes) {
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
                MainActor.assumeIsolated({
                    guard let self, let elt = self.handleToNode[handle] as? Element else { return }
                    elt.attributes[attr] = value
                    self.frame?.setNeedsRender()
                })
            } as @convention(block) (Int, String, String) -> Void,
            forKeyedSubscript: "_setAttribute" as NSString)

        jsContext.setObject(
            {
                [weak self] () -> String in
                guard let self, let frame = self.frame else { return "" }
                let host: String = MainActor.assumeIsolated({ frame.url?.host ?? "" })
                guard !host.isEmpty else { return "" }
                var result: String = ""
                let semaphore: DispatchSemaphore = DispatchSemaphore(value: 0)
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
                guard let self, let frame = self.frame else { return }
                let host: String = MainActor.assumeIsolated({ frame.url?.host ?? "" })
                guard !host.isEmpty else { return }
                let semaphore: DispatchSemaphore = DispatchSemaphore(value: 0)
                Task {
                    if let (_, params) = await CookieJar.shared.get(host) {
                        if params["httponly"] == "true" {
                            semaphore.signal()
                            return
                        }
                    }

                    var newCookieStr: String = cookieStr
                    var cookieParams: [String: String] = [:]
                    if cookieStr.contains(";") {
                        let parts: [String.SubSequence] = cookieStr.split(separator: ";", maxSplits: 1)
                        newCookieStr = String(parts[0])
                        if parts.count > 1 {
                            for param in String(parts[1]).split(separator: ";") {
                                let trimmed: String = param.trimmingCharacters(in: .whitespaces)
                                if trimmed.contains("=") {
                                    let kv: [String.SubSequence] = trimmed.split(separator: "=", maxSplits: 1)
                                    cookieParams[String(kv[0]).lowercased()] = String(kv[1])
                                        .lowercased()
                                } else {
                                    let key: String = trimmed.lowercased()
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

        jsContext.setObject({
            [weak self] (handle: Int) -> String in
            guard let self, let node = self.handleToNode[handle] else { return "" }
            return self.textContent(of: node)
        } as @convention(block) (Int) -> String,
        forKeyedSubscript: "_getTextContent" as NSString)

        jsContext.setObject({
            [weak self] (handle: Int, value: String) in
            MainActor.assumeIsolated({
                guard let self, let elt = self.handleToNode[handle] as? Element else { return }
                elt.children = [TextNode(text: value, parent: elt)]
                self.frame?.setNeedsRender()
            })
        } as @convention(block) (Int, String) -> Void,
        forKeyedSubscript: "_setTextContent" as NSString)

        jsContext.setObject(
            {
                [weak self] (handle: Int, s: String) in
                MainActor.assumeIsolated({
                    guard let self, let frame = self.frame,
                        let elt = self.handleToNode[handle] as? Element
                    else { return }
                    let doc: any DOMNode = HTMLParser(body: "<html><body>\(s)</body></html>").parse()
                    let newNodes: [any DOMNode]? = (doc.children.first as? Element)?.children
                    elt.children = newNodes ?? []
                    for child in elt.children { child.parent = elt }
                    frame.runNewScripts(in: elt)
                    frame.reloadStylesheets()
                    frame.setNeedsRender()
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
                let elt: Element = Element(tag: tag, attributes: [:], parent: nil)
                return self.getHandle(elt)
            } as @convention(block) (String) -> Int,
            forKeyedSubscript: "_createElement" as NSString)

        jsContext.setObject(
            {
                [weak self] (parentHandle: Int, childHandle: Int) in
                MainActor.assumeIsolated({
                    guard let self, let frame = self.frame,
                        let parent = self.handleToNode[parentHandle],
                        let child = self.handleToNode[childHandle]
                    else { return }
                    child.parent = parent
                    parent.children.append(child)
                    frame.runNewScripts(in: child)
                    frame.reloadStylesheets()
                    frame.setNeedsRender()
                })
            } as @convention(block) (Int, Int) -> Void,
            forKeyedSubscript: "_appendChild" as NSString)

        jsContext.setObject(
            {
                [weak self] (parentHandle: Int, childHandle: Int) -> Int in
                return MainActor.assumeIsolated({
                    guard let self, let frame = self.frame,
                        let parent = self.handleToNode[parentHandle],
                        let child = self.handleToNode[childHandle]
                    else { return -1 }
                    parent.children.removeAll { $0 === child }
                    child.parent = nil
                    frame.reloadStylesheets()
                    frame.setNeedsRender()
                    return childHandle
                })
            } as @convention(block) (Int, Int) -> Int,
            forKeyedSubscript: "_removeChild" as NSString)

        jsContext.setObject(
            {
                [weak self] (parentHandle: Int, childHandle: Int, refHandle: Int) in
                MainActor.assumeIsolated({
                    guard let self, let frame = self.frame,
                        let parent = self.handleToNode[parentHandle],
                        let child = self.handleToNode[childHandle],
                        let ref = self.handleToNode[refHandle],
                        let idx = parent.children.firstIndex(where: { $0 === ref })
                    else { return }
                    child.parent = parent
                    parent.children.insert(child, at: idx)
                    frame.runNewScripts(in: child)
                    frame.reloadStylesheets()
                    frame.render()
                })
            } as @convention(block) (Int, Int, Int) -> Void,
            forKeyedSubscript: "_insertBefore" as NSString)

        jsContext.setObject(
            {
                [weak self] (method: String, url: String, body: String?) -> String in
                return MainActor.assumeIsolated({
                    guard let self, let frame = self.frame else { return "" }
                    let fullURL: WebURL = frame.url.resolve(url)

                    guard frame.allowedRequest(fullURL) else {
                        print("Cross-origin XHR blocked by CSP")
                        return ""
                    }

                    if fullURL.origin() == frame.url.origin() {
                        guard let (_, _, out) = fullURL.requestSync(payload: body) else { return "" }
                        return out
                    }

                    let origin: String = frame.url.origin()
                    guard
                        let (_, headers, out) = fullURL.requestSync(
                            payload: body,
                            extraHeaders: ["Origin": origin]
                        )
                    else { return "" }
                    let allowed: String = headers["access-control-allow-origin"] ?? ""
                    guard allowed == "*" || allowed == origin else {
                        print("Cross-origin XHR request not allowed")
                        return ""
                    }
                    return out
                })
            } as @convention(block) (String, String, String?) -> String,
            forKeyedSubscript: "_XHRSend" as NSString)

        jsContext.setObject(
            {
                [weak self] in
                guard let frame = self?.frame else { return }
                Task { @MainActor in
                    guard let tab = frame.tab, tab.browser?.activeTab === tab else { return }
                    tab.browser?.setNeedsAnimationFrame(tab)
                }
            } as @convention(block) () -> Void,
            forKeyedSubscript: "_requestAnimationFrame" as NSString)

        jsContext.setObject(
            {
                [weak self] (handle: Int, time: Double) in
                guard let frame = self?.frame else { return }
                let delay: Double = time / 1000.0
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    Task { @MainActor in
                        guard let tab = frame.tab else { return }
                        let task: BrowserTask = BrowserTask(
                            name: "runSetTimeout", priority: .low, measure: tab.browser?.measure
                        ) {
                            frame.js.run(script: "setTimeout", code: "__runSetTimeout(\(handle))")
                        }
                        tab.taskRunner.scheduleTask(task)
                    }
                }
            } as @convention(block) (Int, Double) -> Void,
            forKeyedSubscript: "__setTimeout" as NSString)

        jsContext.setObject(
            {
                [weak self] (handle: Int, time: Double) in
                guard let frame = self?.frame else { return }
                let interval: Double = time / 1000.0
                let timer: any DispatchSourceTimer = DispatchSource.makeTimerSource(queue: .main)
                timer.schedule(deadline: .now() + interval, repeating: interval)
                timer.setEventHandler(handler: {
                    Task { @MainActor in
                        guard let tab = frame.tab, tab.browser?.activeTab === tab else { return }
                        let task: BrowserTask = BrowserTask(
                            name: "runSetInterval", priority: .low, measure: tab.browser?.measure
                        ) {
                            frame.js.run(script: "setInterval", code: "__runSetInterval(\(handle))")
                        }
                        tab.taskRunner.scheduleTask(task)
                    }
                })
                timer.resume()
                self?.intervalTimes[handle] = timer
            } as @convention(block) (Int, Double) -> Void,
            forKeyedSubscript: "__setInterval" as NSString)

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
                        let frame = self.frame
                    else { return }
                    elt.scrollOffsetY = CGFloat(value)
                    frame.setNeedsPaint()
                })
            } as @convention(block) (Int, Double) -> Void,
            forKeyedSubscript: "_setScrollTop" as NSString)

        jsContext.setObject({
            [weak self] (handle: Int) in
            MainActor.assumeIsolated({
                guard let self, let frame = self.frame,
                let elt = self.handleToNode[handle] as? Element,
                isFocusable(elt)
                else { return }
                frame.focusElement(elt)
            })
        } as @convention(block) (Int) -> Void,
        forKeyedSubscript: "_focusElement" as NSString)

        jsContext.setObject(
            {
                [weak self] (handle: Int, attr: String, value: String) in
                guard let self = self, let elt = self.handleToNode[handle] as? Element else {
                    return
                }
                Task {
                    @MainActor in
                    InlineStyle.set(elt, property: attr, value: value)
                    self.frame?.setNeedsRender()
                }
            } as @convention(block) (Int, String, String) -> Void,
            forKeyedSubscript: "__styleSet__" as NSString)

        jsContext.setObject(
            {
                [weak self] () -> Int in
                return MainActor.assumeIsolated { self?.frame?.windowID ?? -1 }
            } as @convention(block) () -> Int,
            forKeyedSubscript: "_getWindowID" as NSString)

        jsContext.setObject(
            {
                [weak self] (_: Int) -> Int in
                return MainActor.assumeIsolated { self?.frame?.parentFrame?.windowID ?? -1 }
            } as @convention(block) (Int) -> Int,
            forKeyedSubscript: "_parent" as NSString)

        jsContext.setObject(
            {
                [weak self] (targetID: Int, message: String, _: String) in
                MainActor.assumeIsolated {
                    self?.frame?.tab?.postMessage(message: message, targetWindowID: targetID)
                }
            } as @convention(block) (Int, String, String) -> Void,
            forKeyedSubscript: "_postMessage" as NSString)

        CanvasBridge(
            jsContext: jsContext,
            nodeForHandle: { [weak self] handle in self?.handleToNode[handle] },
            requestPaint: { [weak self] in self?.frame?.setNeedsPaint() },
            displayScale: { [weak self] in self?.frame?.tab?.browser?.displayScale ?? 1 }
        ).register()
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
        let source: String? = profiler.measure("jsc.runtimeHead", {
            guard let url = Bundle.module.url(forResource: "runtime", withExtension: "js") else { return nil }
            return try? String(contentsOf: url, encoding: .utf8)
        })
        guard let source else { fatalError("runtime.js not found in bundle") }
        profiler.measure("jsc.runtimeEval", { jsContext.evaluateScript(source) })
    }
}
