import CoreGraphics
import Foundation

// MARK: - PaintBuildSink

/// `owners[i]` owns `scenes[i]`, so paint results can be handed back after
/// the pass.
struct PaintBuildSink {
    var owners: [Frame] = []
    var scenes: [PaintFrame] = []
}

// MARK: - PaintSceneBuilder

/// This is the only paint code that touches the layout tree and `DOMRef`. It
/// also collects the few DOM facts that decide ops (focus rings, caret, iframe
/// scrollbars), so the pass itself stays on values.
@MainActor
struct PaintSceneBuilder {
    private(set) var sink: PaintBuildSink = PaintBuildSink()
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
        sink.scenes.append(PaintFrame(nodes: [], epoch: frame.paintEpoch, revisions: []))

        var nodes: [PaintNode] = []
        nodes.reserveCapacity(64)
        // A local array: an iframe scene is built recursively while this one
        // is still in progress, so a builder-wide array would be reset.
        var revisions: [UInt64] = []
        revisions.reserveCapacity(64)
        _ = appendNode(tree, root, parent: nil, nodes: &nodes, revisions: &revisions)
        sink.scenes[index] = PaintFrame(
            nodes: nodes,
            epoch: frame.paintEpoch,
            revisions: revisions
        )
        return index
    }

    // MARK: - Nodes

    private mutating func appendNode(
        _ tree: LayoutTree,
        _ id: LayoutID,
        parent: Int?,
        nodes: inout [PaintNode],
        revisions: inout [UInt64]
    ) -> Int? {
        guard !culledAtBuild(tree, id) else { return nil }
        let boxes: [InlineBox]? = tree.isLine(id) ? tree.currentInlineBoxes(id) : nil
        let index: Int = nodes.count
        nodes.append(placeholder(id: id, dom: tree.domID(of: id)))
        revisions.append(0)
        var children: [Int] = []
        var childIDs: [LayoutID] = tree.childrenIDs(of: id)
        if boxes != nil {
            childIDs.removeAll(where: { tree.isText($0) })
        }
        children.reserveCapacity(childIDs.count)
        for child in childIDs {
            if let childIndex: Int = appendNode(
                tree,
                child,
                parent: index,
                nodes: &nodes,
                revisions: &revisions
            ) {
                children.append(childIndex)
            }
        }
        nodes[index] = makeNode(tree, id, parent: parent, children: children, boxes: boxes)
        revisions[index] = paintRevision(tree, id, boxes: boxes)
        return index
    }

    /// A block caches its own emitted ops, so its own style revision is the
    /// whole input. A line caches its text ops, whose colours come from the
    /// inherited style owner of each box; the line generation is compared
    /// separately in `LinePaintVersion`. Using the global paint epoch here
    /// made one hovered link re-emit every line and block on the page.
    private func paintRevision(
        _ tree: LayoutTree,
        _ id: LayoutID,
        boxes: [InlineBox]?
    ) -> UInt64 {
        guard tree.isLine(id), let boxes else {
            return tree.domRef(id).style.revision
        }
        var style: UInt64 = 0xcbf2_9ce4_8422_2325
        for (index, box) in boxes.enumerated() {
            let owner: DOMRef = DOMRef(id: box.dom, dom: tree.dom).inheritedStyleOwner
            style ^= owner.style.revision &+ UInt64(index) &* 0x9E37_79B9_7F4A_7C15
            style = style &* 0x0000_0100_0000_01B3
        }
        return style
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
        children: [Int],
        boxes: [InlineBox]?
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
                zoom: tree.zoom(id),
                border: tree.borderWidths(id)
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
            content: makeContent(tree, id, boxes: boxes),
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

    private mutating func makeContent(
        _ tree: LayoutTree,
        _ id: LayoutID,
        boxes: [InlineBox]?
    ) -> PaintContent {
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
            let inlineBoxes: [DisplayOp] = lineInlineBoxes(tree, id, boxes)
            return .line(PaintLine(
                canCache: tree.lineCanCachePaint(id) && boxes != nil && inlineBoxes.isEmpty,
                generation: tree[line: id].paint.generation,
                decorations: inlineBoxes + lineFocusRing(tree, id),
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
        let inner: Rect = tree.contentRect(id)
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

    // MARK: - Inline boxes

    /// Backgrounds and borders of the inline elements on one line, outer
    /// elements first so inner ones paint over them. An element with padding
    /// or border has a fragment from layout; one with only a background covers
    /// whatever of its contents landed on this line, up to its last letter.
    private func lineInlineBoxes(_ tree: LayoutTree, _ id: LayoutID, _ boxes: [InlineBox]?) -> [DisplayOp] {
        var areas: [NodeID: InlineArea] = [:]
        for fragment in tree[line: id].inlineBoxes.fragments {
            let rect: Rect = fragment.rect.translated(dx: tree.x(id), dy: tree.y(id))
            let node: DOMRef = DOMRef(id: fragment.dom, dom: tree.dom)
            areas[fragment.dom] = InlineArea(rect: rect, depth: inlineDepth(node, line: id, tree: tree), fragment: fragment)
            coverBackgrounds(rect, from: node.parent, line: (id, tree), into: &areas)
        }
        if let boxes {
            for box in boxes {
                // A word's measured width carries the space after it, which
                // belongs to whatever comes next.
                let rect: Rect = Rect(
                    left: box.geometry.x,
                    top: tree.y(id) + box.geometry.y,
                    right: max(box.geometry.x, box.geometry.x + box.geometry.width - box.text.font.spaceWidth),
                    bottom: tree.y(id) + box.geometry.y + box.text.font.linespace
                )
                coverBackgrounds(rect, from: DOMRef(id: box.dom, dom: tree.dom).parent, line: (id, tree), into: &areas)
            }
        } else {
            for child in tree.childrenIDs(of: id) where tree.isText(child) || tree.isEmbed(child) {
                var rect: Rect = tree.selfRect(child)
                if tree.isText(child) {
                    rect.right = max(rect.left, rect.right - tree.font(child).spaceWidth)
                }
                coverBackgrounds(rect, from: tree.domRef(child).parent, line: (id, tree), into: &areas)
            }
        }
        guard !areas.isEmpty else { return [] }

        var ops: [DisplayOp] = []
        let zoom: CGFloat = tree.zoom(id)
        for (dom, area) in areas.sorted(by: { $0.value.depth < $1.value.depth }) {
            let style: ComputedStyle = DOMRef(id: dom, dom: tree.dom).style.computed
            if let color: BrowserColor = style.visual.background.color {
                ops.append(.rect(rect: area.rect, color: color))
            }
            guard let fragment: InlineBoxFragment = area.fragment else { continue }
            let border: EdgeInsets = style.box.decoration.border.usedWidths.scaled(by: zoom)
            BorderPainter(
                box: area.rect,
                border: style.box.decoration.border,
                widths: fragment.ownEdges(border, direction: style.text.direction)
            ).emit(into: &ops)
        }
        return ops
    }

    /// Grows the background of every inline ancestor that has one but no
    /// padding or border of its own to also cover `rect`.
    private func coverBackgrounds(
        _ rect: Rect,
        from start: DOMRef?,
        line: (id: LayoutID, tree: LayoutTree),
        into areas: inout [NodeID: InlineArea]
    ) {
        let block: NodeID = line.tree.domID(of: line.id)
        var current: DOMRef? = start
        while let ancestor = current, ancestor.id != block {
            let style: ComputedStyle = ancestor.style.computed
            guard style.layout.display == .inline else { return }
            if style.visual.background.color != nil, style.box.paddingAndBorder == .zero {
                if let area: InlineArea = areas[ancestor.id] {
                    areas[ancestor.id] = InlineArea(rect: area.rect.union(rect), depth: area.depth, fragment: nil)
                } else {
                    let depth: Int = inlineDepth(ancestor, line: line.id, tree: line.tree)
                    areas[ancestor.id] = InlineArea(rect: rect, depth: depth, fragment: nil)
                }
            }
            current = ancestor.parent
        }
    }

    private func inlineDepth(_ node: DOMRef, line: LayoutID, tree: LayoutTree) -> Int {
        let block: NodeID = tree.domID(of: line)
        var depth: Int = 0
        var current: DOMRef? = node.parent
        while let ancestor = current, ancestor.id != block {
            depth += 1
            current = ancestor.parent
        }
        return depth
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
            zoom: 1,
            border: .zero
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

// MARK: - InlineArea

/// Where one inline element paints on one line, and how deep it sits under
/// the block so outer elements paint first.
private struct InlineArea {
    let rect: Rect
    let depth: Int
    let fragment: InlineBoxFragment?
}
