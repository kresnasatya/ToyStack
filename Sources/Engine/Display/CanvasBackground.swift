// MARK: - CanvasBackground

enum CanvasBackground {
    // CSS Backgrounds 3 §2.11.1 and §2.11.2: the canvas takes the root element's
    // background; only when the root's background-image is none and its
    // background-color is transparent does it take the background of <body>.
    @MainActor
    static func color(of root: DOMRef) -> BrowserColor? {
        if hasBackground(root) { return visible(root) }
        guard let body: DOMRef = root.children.first(where: { $0.element?.tag == "body" }) else { return nil }
        return visible(body)
    }

    @MainActor
    private static func hasBackground(_ node: DOMRef) -> Bool {
        let background: VisualStyle.Background = node.style.computed.visual.background
        return background.image != nil || visible(node) != nil
    }

    @MainActor
    private static func visible(_ node: DOMRef) -> BrowserColor? {
        guard let color: BrowserColor = node.style.computed.visual.background.color, color.alpha > 0 else { return nil }
        return color
    }
}
