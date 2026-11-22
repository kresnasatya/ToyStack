// MARK: - CanvasBackground

enum CanvasBackground {
    // CSS Backgrounds 3 §2.11.1 and §2.11.2: the canvas takes the root element's
    // background; when the root has none, it takes the background of <body>.
    @MainActor
    static func color(of root: DOMRef) -> BrowserColor? {
        if let color: BrowserColor = visible(root) { return color }
        guard let body: DOMRef = root.children.first(where: { $0.element?.tag == "body" }) else { return nil }
        return visible(body)
    }

    @MainActor
    private static func visible(_ node: DOMRef) -> BrowserColor? {
        guard let color: BrowserColor = node.style.computed.visual.background.color, color.alpha > 0 else { return nil }
        return color
    }
}
