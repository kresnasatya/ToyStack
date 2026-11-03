import Foundation
import JavaScriptCore

class JSRuntime: @unchecked Sendable {
    private let jsContext: JSContext
    private var nodeToHandle: [NodeID: Int] = [:]
    private var handleToNode: [Int: NodeID] = [:]
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

    func dispatchEvent(type: String, el: DOMRef) -> Bool {
        let handle: Int = getHandle(el)
        jsContext.setObject(handle, forKeyedSubscript: "__handle" as NSString)
        jsContext.setObject(type, forKeyedSubscript: "__type" as NSString)
        let result: JSValue? = jsContext.evaluateScript(Self.eventDispatchJS)
        return !(result?.toBool() ?? true)
    }

    func dispatchPostMessage(message: String) {
        jsContext.setObject(message, forKeyedSubscript: "__data" as NSString)
        jsContext.evaluateScript("window.dispatchEvent(new window.MessageEvent(__data))")
    }

    func dispatchWindowLoad() {
        jsContext.evaluateScript("window.dispatchEvent(new Event(\"load\"))")
    }

    private func getHandle(_ node: DOMRef) -> Int {
        let id: NodeID = node.id
        if let handle = nodeToHandle[id] { return handle }
        let handle: Int = nodeToHandle.count
        nodeToHandle[id] = handle
        handleToNode[handle] = id
        return handle
    }

    @MainActor
    private func serialize(_ node: DOMRef) -> String {
        if let text = node.text {
            return text.text
        }
        guard let el = node.element else { return "" }
        let attrs: String = el.attributes.map { " \($0.key)=\($0.value)" }.joined()
        let inner: String = el.children.map { serialize($0) }.joined()
        return "<\(el.tag)\(attrs)>\(inner)</\(el.tag)>"
    }

    @MainActor
    private func textContent(of node: DOMRef) -> String {
        if let text = node.text { return text.text }
        guard let el = node.element else { return "" }
        return el.children.map { self.textContent(of: $0) }.joined()
    }

    private func registerCallbacks() {
        jsContext.setObject({
            (msg: String) in print(msg)
        } as @convention(block) (String) -> Void, forKeyedSubscript: "_log" as NSString)

        jsContext.setObject({
            [weak self] (selectorText: String) -> [Int] in
            guard let self, let frame = self.frame else { return [] }
            return MainActor.assumeIsolated({
                let selector: any CSSSelector = CSSParser(selectorText).selector()
                let snapshot: StyleSnapshot = StyleSnapshotBuilder.build(root: frame.nodes)
                let nodes: [DOMRef] = treeToList(frame.nodes).filter { node in
                    guard let index: Int = snapshot.index(of: node.id) else { return false }
                    return selector.matches(snapshot, index)
                }
                return nodes.map { self.getHandle($0) }
            })
        } as @convention(block) (String) -> [Int], forKeyedSubscript: "_querySelectorAll" as NSString)

        jsContext.setObject({
            [weak self] () -> [String: Int] in
            guard let self, let frame = self.frame else { return [:] }
            return MainActor.assumeIsolated({
                var result: [String: Int] = [:]
                for node in treeToList(frame.nodes) {
                    guard let el = node.element,
                        let id = el.attributes["id"]
                    else { continue }
                    result[id] = self.getHandle(node)
                }
                return result
            })
        } as @convention(block) () -> [String: Int], forKeyedSubscript: "_getIDs" as NSString)

        jsContext.setObject({
            [weak self] (handle: Int, attr: String) -> String in
            guard let self, let frame = self.frame,
                let id = self.handleToNode[handle]
            else { return "" }
            return MainActor.assumeIsolated {
                return frame.dom.attribute(attr, of: id) ?? ""
            }
        } as @convention(block) (Int, String) -> String, forKeyedSubscript: "_getAttribute" as NSString)

        jsContext.setObject({
            [weak self] (handle: Int, attr: String, value: String) in
            MainActor.assumeIsolated({
                guard let self, let frame = self.frame,
                    let id = self.handleToNode[handle],
                    frame.dom.isElement(id)
                else { return }
                frame.dom.setAttribute(attr, value, of: id)
                let ref: DOMRef = frame.dom.ref(id)
                LayoutInvalidation.attributesChanged(ref)
                if attr == "src", frame.dom.tag(of: id) == "iframe" {
                    frame.syncIframes()
                }
                frame.noteStyleInvalidation("style.invalidate.js.attribute")
                frame.setNeedsStyleSubtree(ref)
            })
        } as @convention(block) (Int, String, String) -> Void, forKeyedSubscript: "_setAttribute" as NSString)

        jsContext.setObject({
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
        } as @convention(block) () -> String, forKeyedSubscript: "_getCookie" as NSString)

        jsContext.setObject({
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

        jsContext.setObject({
            [weak self] (handle: Int) -> Int in
            guard let self, let frame = self.frame,
                let id = self.handleToNode[handle]
            else { return -1 }
            return MainActor.assumeIsolated {
                guard let parent = frame.dom.parent(of: id) else { return -1 }
                return self.getHandle(frame.dom.ref(parent))
            }
        } as @convention(block) (Int) -> Int, forKeyedSubscript: "_getParent" as NSString)

        jsContext.setObject({
            [weak self] (handle: Int) -> String in
            guard let self, let frame = self.frame,
                let id = self.handleToNode[handle]
            else { return "" }
            return MainActor.assumeIsolated({
                return frame.dom.children(of: id).map({ self.serialize(frame.dom.ref($0)) }).joined()
            })
        } as @convention(block) (Int) -> String, forKeyedSubscript: "_serializeInner" as NSString)

        jsContext.setObject({
            [weak self] (handle: Int) -> String in
            guard let self, let frame = self.frame,
                let id = self.handleToNode[handle]
            else { return "" }
            return MainActor.assumeIsolated({ self.serialize(frame.dom.ref(id)) })
        } as @convention(block) (Int) -> String, forKeyedSubscript: "_serializeOuter" as NSString)

        jsContext.setObject({
            [weak self] (handle: Int) -> String in
            guard let self, let frame = self.frame,
                let id = self.handleToNode[handle]
            else { return "" }
            return MainActor.assumeIsolated({ self.textContent(of: frame.dom.ref(id)) })
        } as @convention(block) (Int) -> String, forKeyedSubscript: "_getTextContent" as NSString)

        jsContext.setObject({
            [weak self] (handle: Int, value: String) in
            MainActor.assumeIsolated({
                guard let self, let frame = self.frame,
                    let id = self.handleToNode[handle], frame.dom.isElement(id)
                else { return }
                let text: NodeID = frame.dom.createText(value)
                frame.dom.setChildren([text], of: id)
                LayoutInvalidation.childrenChanged(frame.dom.ref(id))
                frame.syncIframes()
                frame.setNeedsStyle(frame.dom.ref(id))
            })
        } as @convention(block) (Int, String) -> Void, forKeyedSubscript: "_setTextContent" as NSString)

        jsContext.setObject({
            [weak self] (handle: Int, s: String) in
            MainActor.assumeIsolated({
                guard let self, let frame = self.frame,
                    let id = self.handleToNode[handle], frame.dom.isElement(id)
                else { return }
                let doc: DOMTree = HTMLParser(body: "<html><body>\(s)</body></html>").parse()
                let body: NodeID? = doc.children(of: doc.root).first(where: { doc.tag(of: $0) == "body" })
                frame.dom.setChildren([], of: id)
                if let body {
                    for child in doc.children(of: body) {
                        frame.dom.cloneSubtree(doc, child, into: id)
                    }
                }
                let ref: DOMRef = frame.dom.ref(id)
                LayoutInvalidation.childrenChanged(ref)
                frame.markStructureChanged()
                frame.runNewScripts(in: ref)
                frame.reloadStylesheets()
                frame.syncIframes()
                frame.setNeedsStyle(ref)
            })
        } as @convention(block) (Int, String) -> Void, forKeyedSubscript: "_innerHTML" as NSString)

        jsContext.setObject({
            [weak self] (handle: Int) -> [Int] in
            guard let self, let frame = self.frame,
                let id = self.handleToNode[handle]
            else { return [] }
            return MainActor.assumeIsolated({
                return frame.dom.children(of: id)
                    .filter({ frame.dom.isElement($0) })
                    .map({ self.getHandle(frame.dom.ref($0)) })
            })
        } as @convention(block) (Int) -> [Int], forKeyedSubscript: "_children" as NSString)

        jsContext.setObject({
            [weak self] (tag: String) -> Int in
            guard let self, let frame = self.frame else { return -1 }
            return MainActor.assumeIsolated {
                let id: NodeID = frame.dom.createElement(tag: tag, attributes: [:])
                return self.getHandle(frame.dom.ref(id))
            }
        } as @convention(block) (String) -> Int, forKeyedSubscript: "_createElement" as NSString)

        jsContext.setObject({
            [weak self] (parentHandle: Int, childHandle: Int) in
            MainActor.assumeIsolated({
                guard let self, let frame = self.frame,
                    let parent = self.handleToNode[parentHandle],
                    let child = self.handleToNode[childHandle]
                else { return }

                let oldParent: NodeID? = frame.dom.parent(of: child)
                let wasSameParent: Bool = oldParent == parent
                frame.dom.append(child, to: parent)
                if let oldParent, oldParent != parent {
                    LayoutInvalidation.childrenChanged(frame.dom.ref(oldParent))
                    frame.setNeedsStyle(frame.dom.ref(oldParent))
                }
                if wasSameParent {
                    LayoutInvalidation.childrenChanged(frame.dom.ref(parent))
                } else {
                    LayoutInvalidation.childrenAppend(frame.dom.ref(parent), frame.dom.ref(child))
                }
                frame.markStructureChanged()
                frame.runNewScripts(in: frame.dom.ref(child))
                frame.reloadStylesheets()
                frame.syncIframes()
                frame.setNeedsStyleSubtree(frame.dom.ref(child))
            })
        } as @convention(block) (Int, Int) -> Void, forKeyedSubscript: "_appendChild" as NSString)

        jsContext.setObject({
            [weak self] (parentHandle: Int, childHandle: Int) -> Int in
            return MainActor.assumeIsolated({
                guard let self, let frame = self.frame,
                    let parent = self.handleToNode[parentHandle],
                    let child = self.handleToNode[childHandle]
                else { return -1 }
                guard frame.dom.remove(child, from: parent) else { return -1 }
                LayoutInvalidation.childrenChanged(frame.dom.ref(parent))
                frame.markStructureChanged()
                frame.reloadStylesheets()
                frame.syncIframes()
                frame.setNeedsStyle(frame.dom.ref(parent))
                return childHandle
            })
        } as @convention(block) (Int, Int) -> Int, forKeyedSubscript: "_removeChild" as NSString)

        jsContext.setObject({
            [weak self] (handle: Int, childHandles: [Int]) in
            MainActor.assumeIsolated({
                guard let self, let frame = self.frame,
                    let el = self.handleToNode[handle], frame.dom.isElement(el)
                else { return }

                let newChildren: [NodeID] = childHandles.compactMap({ self.handleToNode[$0] })
                guard newChildren.allSatisfy({ !frame.dom.isInclusiveAncestor($0, of: el) }) else {
                    return
                }

                let oldParents: [NodeID] = newChildren.compactMap({ frame.dom.parent(of: $0) })
                frame.dom.setChildren(newChildren, of: el)

                for parent in oldParents where parent != el {
                    LayoutInvalidation.childrenChanged(frame.dom.ref(parent))
                }

                LayoutInvalidation.childrenChanged(frame.dom.ref(el))
                frame.markStructureChanged()
                for child in newChildren { frame.runNewScripts(in: frame.dom.ref(child)) }
                frame.reloadStylesheets()
                frame.syncIframes()
                frame.setNeedsStyle(frame.dom.ref(el))
                for child in newChildren {
                    frame.setNeedsStyleSubtree(frame.dom.ref(child))
                }
            })
        } as @convention(block) (Int, [Int]) -> Void, forKeyedSubscript: "_replaceChildren" as NSString)

        jsContext.setObject({
            [weak self] (parentHandle: Int, childHandle: Int, refHandle: Int) in
            MainActor.assumeIsolated({
                guard let self, let frame = self.frame,
                    let parent = self.handleToNode[parentHandle],
                    let child = self.handleToNode[childHandle],
                    let ref = self.handleToNode[refHandle],
                    child != ref,
                    !frame.dom.isInclusiveAncestor(child, of: parent),
                    frame.dom.children(of: parent).contains(ref)
                else { return }
                let oldParent: NodeID? = frame.dom.parent(of: child)
                let wasSameParent: Bool = oldParent == parent
                frame.dom.insert(child, before: ref, in: parent)
                if let oldParent, oldParent != parent {
                    LayoutInvalidation.childrenChanged(frame.dom.ref(oldParent))
                    frame.setNeedsStyle(frame.dom.ref(oldParent))
                }
                if wasSameParent {
                    LayoutInvalidation.childrenChanged(frame.dom.ref(parent))
                } else {
                    LayoutInvalidation.childrenInsert(
                        frame.dom.ref(parent),
                        frame.dom.ref(child),
                        before: frame.dom.ref(ref)
                    )
                }
                frame.markStructureChanged()
                frame.runNewScripts(in: frame.dom.ref(child))
                frame.reloadStylesheets()
                frame.syncIframes()
                frame.setNeedsStyleSubtree(frame.dom.ref(child))
            })
        } as @convention(block) (Int, Int, Int) -> Void, forKeyedSubscript: "_insertBefore" as NSString)

        jsContext.setObject({
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
        } as @convention(block) (String, String, String?) -> String, forKeyedSubscript: "_XHRSend" as NSString)

        jsContext.setObject({
            [weak self] in
            guard let frame = self?.frame else { return }
            MainActor.assumeIsolated({
                guard let tab = frame.tab, tab.browser?.activeTab === tab else { return }
                tab.browser?.setNeedsAnimationFrame(tab)
            })
        } as @convention(block) () -> Void, forKeyedSubscript: "_requestAnimationFrame" as NSString)

        jsContext.setObject({
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
        } as @convention(block) (Int, Double) -> Void, forKeyedSubscript: "__setTimeout" as NSString)

        jsContext.setObject({
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
        } as @convention(block) (Int, Double) -> Void, forKeyedSubscript: "__setInterval" as NSString)

        jsContext.setObject({
            [weak self] (handle: Int) in
            guard let self else { return }
            if let timer = self.intervalTimes[handle] {
                timer.setEventHandler(handler: nil)
                timer.cancel()
                self.intervalTimes.removeValue(forKey: handle)
            }
        } as @convention(block) (Int) -> Void, forKeyedSubscript: "__clearInterval" as NSString)

        jsContext.setObject({
            [weak self] (handle: Int, value: Double) in
            MainActor.assumeIsolated({
                guard let self, let id = self.handleToNode[handle],
                    let frame = self.frame, frame.dom.isElement(id)
                else { return }
                frame.dom.side.scrollOffsets[id] = CGFloat(value)
                frame.setNeedsPaint()
            })
        } as @convention(block) (Int, Double) -> Void, forKeyedSubscript: "_setScrollTop" as NSString)

        jsContext.setObject({
            [weak self] (handle: Int) in
            MainActor.assumeIsolated({
                guard let self, let frame = self.frame,
                let id = self.handleToNode[handle]
                else { return }
                let ref: DOMRef = frame.dom.ref(id)
                guard isFocusable(ref) else { return }
                frame.focusElement(ref.element)
            })
        } as @convention(block) (Int) -> Void, forKeyedSubscript: "_focusElement" as NSString)

        jsContext.setObject({
            [weak self] (handle: Int, attr: String, value: String) in
            guard let self, let id = self.handleToNode[handle] else {
                return
            }
            Task {
                @MainActor in
                guard let frame = self.frame, let el = frame.dom.ref(id).element else { return }
                InlineStyle.set(el, property: attr, value: value)
                frame.noteStyleInvalidation("style.invalidate.js.style")
                frame.setNeedsStyleSubtree(el.ref)
            }
        } as @convention(block) (Int, String, String) -> Void, forKeyedSubscript: "__styleSet__" as NSString)

        jsContext.setObject({
            [weak self] () -> Int in
            return MainActor.assumeIsolated { self?.frame?.windowID ?? -1 }
        } as @convention(block) () -> Int, forKeyedSubscript: "_getWindowID" as NSString)

        jsContext.setObject({
            [weak self] (_: Int) -> Int in
            return MainActor.assumeIsolated { self?.frame?.parentFrame?.windowID ?? -1 }
        } as @convention(block) (Int) -> Int, forKeyedSubscript: "_parent" as NSString)

        jsContext.setObject({
            [weak self] () -> String in
            MainActor.assumeIsolated({
                self?.frame?.url?.origin() ?? ""
            })
        } as @convention(block) () -> String, forKeyedSubscript: "_getOrigin" as NSString)

        jsContext.setObject({
            [weak self] () -> String in
            MainActor.assumeIsolated({ self?.frame?.url?.toString() ?? "" })
        } as @convention(block) () -> String, forKeyedSubscript: "_getLocationHref" as NSString)

        jsContext.setObject({
            [weak self] (raw: String) in
            MainActor.assumeIsolated({ self?.frame?.navigateToLocation(raw) })
        } as @convention(block) (String) -> Void, forKeyedSubscript: "_setLocationHref" as NSString)

        jsContext.setObject({
            [weak self] (targetID: Int, message: String, targetOrigin: String) in
            MainActor.assumeIsolated {
                self?.frame?.tab?.postMessage(
                    message: message,
                    targetWindowID: targetID,
                    targetOrigin: targetOrigin
                )
            }
        } as @convention(block) (Int, String, String) -> Void, forKeyedSubscript: "_postMessage" as NSString)

        CanvasBridge(
            jsContext: jsContext,
            elementForHandle: { [weak self] handle in
                guard let self, let frame = self.frame,
                    let id = self.handleToNode[handle]
                else { return nil }
                return frame.dom.ref(id).element
            },
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
            guard let url = EngineResources.bundle.url(forResource: "runtime", withExtension: "js") else { return nil }
            return try? String(contentsOf: url, encoding: .utf8)
        })
        guard let source else { fatalError("runtime.js not found in bundle") }
        profiler.measure("jsc.runtimeEval", { jsContext.evaluateScript(source) })
        if let exception = jsContext.exception {
            fatalError("runtime.js failed to evaluate: \(exception)")
        }
    }
}
