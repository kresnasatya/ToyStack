import Foundation
import JavaScriptCore

class JSRuntime: @unchecked Sendable {
    private let jsContext = JSContext()!
    private var nodeToHandle: [ObjectIdentifier: Int] = [:]
    private var handleToNode: [Int: any DOMNode] = [:]
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
                [weak self] (handle: Int, attr: String) -> String in
                guard let self, let elt = self.handleToNode[handle] as? Element else { return "" }
                return elt.attributes[attr] ?? ""
            } as @convention(block) (Int, String) -> String,
            forKeyedSubscript: "_getAttribute" as NSString)

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
                    tab.render()
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
                    tab.render()
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
                    tab.render()
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
                    guard fullURL.origin() == tab.url.origin() else {
                        print("Cross-origin XHR request not allowed")
                        return ""
                    }
                    guard let (_, out) = fullURL.requestSync(payload: body) else { return "" }
                    return out
                })
            } as @convention(block) (String, String, String?) -> String,
            forKeyedSubscript: "_XHRSend" as NSString)
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
