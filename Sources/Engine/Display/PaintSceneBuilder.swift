import CoreGraphics
import Foundation

// MARK: - PaintBuildSink

/// Frames discovered while building one scene. `owners[i]` owns `scenes[i]`,
/// so paint results can be handed back after the pass.
struct PaintBuildSink {
    var owners: [Frame] = []
    var scenes: [PaintFrame] = []
}

// MARK: - PaintSceneBuilder

/// Copies everything paint reads out of the live trees.
///
/// This is the only paint code that touches the layout tree and `DOMRef`. It
/// also collects the few DOM facts that decide ops (focus rings, caret, iframe
/// scrollbars), so the pass itself stays on values.
@MainActor
struct PaintSceneBuilder {
    private(set) var sink: PaintBuildSink = PaintBuildSink()
    /// Nodes outside this window are not copied into the scene.
    private var window: PaintWindow = .full

    mutating func build(
        root: LayoutID,
        tree: LayoutTree,
        frame: Frame,
        window: PaintWindow = .full
    ) -> Int {
        self.window = window
        let index: Int = sink.scenes.count
        sink.owners.append(frame)
        sink.scenes.append(PaintFrame(nodes: [], epoch: frame.paintEpoch))

        var nodes: [PaintNode] = []
        nodes.reserveCapacity(64)
        _ = appendNode(tree, root, parent: nil, nodes: &nodes)
        sink.scenes[index] = PaintFrame(nodes: nodes, epoch: frame.paintEpoch)
        return index
    }

    // MARK: - Nodes

    /// Returns `nil` when the node is culled, so the parent skips it entirely.
    private mutating func appendNode(
        _ tree: LayoutTree,
        _ id: LayoutID,
        parent: Int?,
        nodes: inout [PaintNode]
    ) -> Int? {
        guard !culledAtBuild(tree, id) else { return nil }
        let index: Int = nodes.count
        nodes.append(placeholder(id: id, dom: tree.domID(of: id)))
        var children: [Int] = []
        var childIDs: [LayoutID] = tree.childrenIDs(of: id)
        if tree.isLine(id), tree.currentInlineBoxes(id) != nil {
            childIDs.removeAll(where: { tree.isText($0) })
        }
        children.reserveCapacity(childIDs.count)
        for child in childIDs {
            if let childIndex: Int = appendNode(tree, child, parent: index, nodes: &nodes) {
                children.append(childIndex)
            }
        }
        nodes[index] = makeNode(tree, id, parent: parent, children: children)
        return index
    }

    /// The same rule the paint pass applies: only line and text nodes are
    /// window-culled, so absolute and fixed blocks keep their parent chain.
    private func culledAtBuild(_ tree: LayoutTree, _ id: LayoutID) -> Bool {
        guard window != .full else { return false }
        switch tree.kind(id) {
        case .line, .text:
            return !window.intersects(tree.selfRect(id))
        default:
            return false
        }
    }

    private mutating func makeNode(
        _ tree: LayoutTree,
        _ id: LayoutID,
        parent: Int?,
        children: [Int]
    ) -> PaintNode {
        let node: DOMRef = tree.domRef(id)
        let style: ComputedStyle = node.style.computed
        let animatedTransform: Bool = node.animations[.property(.transform)] != nil
        let animatedOpacity: Bool = node.animations[.property(.opacity)] != nil
        return PaintNode(
            geometry: PaintGeometry(
                rect: tree.selfRect(id),
                frame: Rect(
                    left: tree.x(id),
                    top: tree.y(id),
                    right: tree.x(id) + tree.width(id),
                    bottom: tree.y(id) + tree.height(id)
                ),
                zoom: tree.zoom(id)
            ),
            surface: PaintSurface(
                style: style,
                font: font(of: tree, id),
                effects: PaintEffects(
                    style: paintEffectStyle(
                        style,
                        animated: animatedTransform || animatedOpacity
                    ),
                    animatedTransform: animatedTransform
                ),
                state: PaintState(
                    forcedColors: usesForcedColors(node),
                    isFocusVisible: node.isFocusVisible,
                    isFocused: node.element?.isFocused ?? false
                )
            ),
            content: makeContent(tree, id),
            links: PaintLinks(
                id: id,
                dom: node.id,
                parent: parent,
                children: children
            )
        )
    }

    /// `.font` traps when the field is dirty; only text and input paint it.
    private func font(of tree: LayoutTree, _ id: LayoutID) -> BrowserFont {
        switch tree.kind(id) {
        case .text, .embed(.input):
            return tree.font(id)
        default:
            return inlineDefaultFont
        }
    }

    private mutating func makeContent(_ tree: LayoutTree, _ id: LayoutID) -> PaintContent {
        switch tree.kind(id) {
        case .document:
            return .document
        case .block:
            var trailing: [DisplayOp] = tree.blockPaintScrollbar(id)
            tree.blockPaintCaret(id, into: &trailing)
            let node: DOMRef = tree.domRef(id)
            return .block(PaintBlock(
                shouldPaint: tree.blockShouldPaint(id),
                isListItem: node.element?.tag == "li",
                scrollOffset: tree.blockScrollOffset(id),
                extras: PaintBlockExtras(
                    backgroundImage: node.element?.backgroundImage,
                    trailing: trailing
                )
            ))
        case .line:
            let boxes: [InlineBox]? = tree.currentInlineBoxes(id)
            return .line(PaintLine(
                canCache: tree.lineCanCachePaint(id) && tree.currentInlineBoxes(id) != nil,
                generation: tree.lineData(id).paint.generation,
                focusRing: lineFocusRing(tree, id),
                inlineText: boxes.map({ lineInlineText(tree, id, $0) }) ?? []
            ))
        case .text:
            return .text(PaintText(
                string: tree.textString(id),
                width: tree.textTextWidth(id),
                top: tree.textAbsoluteY(id),
                color: tree.domRef(id).inheritedStyleOwner.style.computed.text.color
            ))
        case .embed(let data):
            return .embed(makeEmbed(tree, id, data))
        }
    }

    private func lineInlineText(
        _ tree: LayoutTree,
        _ id: LayoutID,
        _ boxes: [InlineBox]
    ) -> [PaintInlineText] {
        return boxes.map { box in
            let ref: DOMRef = DOMRef(id: box.dom, dom: tree.dom)
            return PaintInlineText(
                string: tree.inlineText(box),
                font: box.text.font,
                color: ref.inheritedStyleOwner.style.computed.text.color,
                rect: Rect(
                    left: box.geometry.x,
                    top: tree.y(id) + box.geometry.y,
                    right: box.geometry.x + box.geometry.width,
                    bottom: tree.y(id) + box.geometry.y + box.text.font.linespace
                )
            )
        }
    }

    // MARK: - Embeds

    private mutating func makeEmbed(
        _ tree: LayoutTree,
        _ id: LayoutID,
        _ data: EmbedData
    ) -> PaintEmbed {
        let element: ElementRef? = tree.domRef(id).element
        switch data {
        case .image(let image):
            return .image(PaintImage(
                image: element?.image,
                height: image.imageHeight
            ))
        case .input:
            return .input(PaintInput(
                text: inputText(element),
                isCheckbox: element?.attributes["type"] == "checkbox",
                isChecked: element?.isChecked ?? false
            ))
        case .button:
            return .button
        case .iframe:
            return .iframe(makeIframe(tree, id, element))
        case .canvas:
            let context: CanvasRenderingContext2D? = element?.canvasContext
            return .canvas(PaintCanvas(
                image: context?.image(),
                revision: context?.revision ?? 0
            ))
        }
    }

    private func inputText(_ element: ElementRef?) -> String {
        guard let element else { return "" }
        if element.tag == "input" {
            let value: String = element.attributes["value"] ?? ""
            if element.attributes["type"] == "password" {
                return String(repeating: "*", count: value.count)
            }
            return value
        }
        if element.tag == "button", element.children.count == 1,
            let textNode = element.children[0].text
        {
            return textNode.text
        }
        return ""
    }

    private mutating func makeIframe(
        _ tree: LayoutTree,
        _ id: LayoutID,
        _ element: ElementRef?
    ) -> PaintIframe {
        let diff: CGFloat = tree.zoom(id)
        let x: CGFloat = tree.x(id)
        let y: CGFloat = tree.y(id)
        let inner: Rect = Rect(
            left: x + diff,
            top: y + diff,
            right: x + tree.width(id) - diff,
            bottom: y + tree.height(id) - diff
        )
        guard let child: Frame = element?.frame, child.loaded, let doc = child.document else {
            return PaintIframe(frame: nil, inner: inner, scroll: 0, bar: nil)
        }
        let index: Int = build(root: doc.rootID, tree: doc, frame: child, window: window)
        return PaintIframe(
            frame: index,
            inner: inner,
            scroll: child.scroll,
            bar: iframeScrollbar(child, inner: inner)
        )
    }

    // MARK: - DOM-derived ops

    private func lineFocusRing(_ tree: LayoutTree, _ id: LayoutID) -> [DisplayOp] {
        var outlineRect: Rect? = nil
        var focused: DOMRef? = nil
        for child in tree.childrenIDs(of: id) {
            guard let ancestor: DOMRef = focusVisibleInlineAncestor(
                tree.domRef(child),
                line: id,
                tree: tree
            ) else {
                continue
            }
            focused = ancestor
            let childRect: Rect = tree.selfRect(child)
            outlineRect = outlineRect?.union(childRect) ?? childRect
        }
        guard let rect: Rect = outlineRect, let focused else { return [] }
        if let outline: DisplayOp = DisplayOp.fromStyle(focused.style.computed, rect: rect) {
            return [outline]
        }
        let ring: (outer: String, inner: String) = focusRingColors(
            forcedColors: usesForcedColors(tree.domRef(id))
        )
        return [
            .outline(rect: rect, color: BrowserColor(cssName: ring.outer), width: 4),
            .outline(rect: rect, color: BrowserColor(cssName: ring.inner), width: 2),
        ]
    }

    private func focusVisibleInlineAncestor(
        _ start: DOMRef,
        line: LayoutID,
        tree: LayoutTree
    ) -> DOMRef? {
        var current: DOMRef? = start.parent
        while let ancestor = current, ancestor.id != tree.domID(of: line) {
            if ancestor.isFocusVisible { return ancestor }
            current = ancestor.parent
        }
        return nil
    }

    private func iframeScrollbar(_ frame: Frame, inner: Rect) -> DisplayOp? {
        guard let doc: LayoutTree = frame.document else { return nil }
        let contentWidth: CGFloat = inner.right - inner.left
        let contentHeight: CGFloat = inner.bottom - inner.top
        guard let bar: DisplayOp = scrollbarBarRect(
            ScrollbarGeometry(
                docHeight: doc.height(doc.rootID) + 2 * VSTEP,
                contentHeight: contentHeight,
                contentWidth: contentWidth,
                scroll: frame.scroll
            ),
            forcedColors: frame.tab?.forcedColors ?? false
        ) else { return nil }
        guard case .rrect(let rect, let radii, let color) = bar else { return nil }
        return .rrect(
            rect: rect.translated(dx: inner.left, dy: inner.top),
            radii: radii,
            color: color
        )
    }
}

// MARK: - Placeholder

private func placeholder(id: LayoutID, dom: NodeID) -> PaintNode {
    return PaintNode(
        geometry: PaintGeometry(
            rect: Rect(left: 0, top: 0, right: 0, bottom: 0),
            frame: Rect(left: 0, top: 0, right: 0, bottom: 0),
            zoom: 1
        ),
        surface: PaintSurface(
            style: .initial,
            font: inlineDefaultFont,
            effects: PaintEffects(style: nil, animatedTransform: false),
            state: PaintState(forcedColors: false, isFocusVisible: false, isFocused: false)
        ),
        content: .document,
        links: PaintLinks(id: id, dom: dom, parent: nil, children: [])
    )
}
