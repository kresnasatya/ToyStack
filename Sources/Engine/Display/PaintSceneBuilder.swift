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
/// This is the only paint code that touches `LayoutRef` and `DOMRef`. It also
/// collects the few DOM facts that decide ops (focus rings, caret, iframe
/// scrollbars), so the pass itself stays on values.
@MainActor
struct PaintSceneBuilder {
    private(set) var sink: PaintBuildSink = PaintBuildSink()

    mutating func build(root: LayoutRef, frame: Frame) -> Int {
        let index: Int = sink.scenes.count
        sink.owners.append(frame)
        sink.scenes.append(PaintFrame(nodes: [], epoch: frame.paintEpoch))

        var nodes: [PaintNode] = []
        nodes.reserveCapacity(64)
        _ = appendNode(root, parent: nil, nodes: &nodes)
        sink.scenes[index] = PaintFrame(nodes: nodes, epoch: frame.paintEpoch)
        return index
    }

    // MARK: - Nodes

    private mutating func appendNode(
        _ ref: LayoutRef,
        parent: Int?,
        nodes: inout [PaintNode]
    ) -> Int {
        let index: Int = nodes.count
        nodes.append(placeholder(id: ref.id, dom: ref.node.id))
        var children: [Int] = []
        children.reserveCapacity(ref.children.count)
        for child in ref.children {
            children.append(appendNode(child, parent: index, nodes: &nodes))
        }
        nodes[index] = makeNode(ref, parent: parent, children: children)
        return index
    }

    private mutating func makeNode(
        _ ref: LayoutRef,
        parent: Int?,
        children: [Int]
    ) -> PaintNode {
        let style: ComputedStyle = ref.node.style.computed
        let animatedTransform: Bool = ref.node.animations[.property(.transform)] != nil
        let animatedOpacity: Bool = ref.node.animations[.property(.opacity)] != nil
        return PaintNode(
            geometry: PaintGeometry(
                rect: ref.selfRect(),
                frame: Rect(
                    left: ref.x,
                    top: ref.y,
                    right: ref.x + ref.width,
                    bottom: ref.y + ref.height
                ),
                zoom: ref.zoom
            ),
            surface: PaintSurface(
                style: style,
                font: font(of: ref),
                effects: PaintEffects(
                    style: paintEffectStyle(
                        style,
                        animated: animatedTransform || animatedOpacity
                    ),
                    animatedTransform: animatedTransform
                ),
                state: PaintState(
                    forcedColors: usesForcedColors(ref.node),
                    isFocusVisible: ref.node.isFocusVisible,
                    isFocused: ref.node.element?.isFocused ?? false
                )
            ),
            content: makeContent(ref),
            links: PaintLinks(id: ref.id, dom: ref.node.id, parent: parent, children: children)
        )
    }

    /// `.font` traps when the field is dirty; only text and input paint it.
    private func font(of ref: LayoutRef) -> BrowserFont {
        switch ref.kind {
        case .text, .embed(.input):
            return ref.font
        default:
            return inlineDefaultFont
        }
    }

    private mutating func makeContent(_ ref: LayoutRef) -> PaintContent {
        switch ref.kind {
        case .document:
            return .document
        case .block:
            var trailing: [DisplayOp] = ref.tree.blockPaintScrollbar(ref.id)
            ref.tree.blockPaintCaret(ref.id, into: &trailing)
            return .block(PaintBlock(
                shouldPaint: ref.tree.blockShouldPaint(ref.id),
                isListItem: ref.node.element?.tag == "li",
                scrollOffset: ref.tree.blockScrollOffset(ref.id),
                extras: PaintBlockExtras(
                    backgroundImage: ref.node.element?.backgroundImage,
                    trailing: trailing
                )
            ))
        case .line:
            return .line(PaintLine(
                canCache: ref.tree.lineCanCachePaint(ref.id),
                generation: ref.lineData.paint.generation,
                focusRing: lineFocusRing(ref)
            ))
        case .text:
            let data: TextData = ref.textData
            return .text(PaintText(
                string: data.display ?? data.word,
                width: data.metrics.width,
                top: ref.tree.textAbsoluteY(ref.id),
                color: ref.node.inheritedStyleOwner.style.computed.text.color
            ))
        case .embed(let data):
            return .embed(makeEmbed(ref, data))
        }
    }

    // MARK: - Embeds

    private mutating func makeEmbed(_ ref: LayoutRef, _ data: EmbedData) -> PaintEmbed {
        let element: ElementRef? = ref.node.element
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
            return .iframe(makeIframe(ref, element))
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

    private mutating func makeIframe(_ ref: LayoutRef, _ element: ElementRef?) -> PaintIframe {
        let diff: CGFloat = ref.scaled(1)
        let inner: Rect = Rect(
            left: ref.x + diff,
            top: ref.y + diff,
            right: ref.x + ref.width - diff,
            bottom: ref.y + ref.height - diff
        )
        guard let child: Frame = element?.frame, child.loaded, let doc = child.document else {
            return PaintIframe(frame: nil, inner: inner, scroll: 0, bar: nil)
        }
        let index: Int = build(root: doc.root, frame: child)
        return PaintIframe(
            frame: index,
            inner: inner,
            scroll: child.scroll,
            bar: iframeScrollbar(child, inner: inner)
        )
    }

    // MARK: - DOM-derived ops

    private func lineFocusRing(_ ref: LayoutRef) -> [DisplayOp] {
        var outlineRect: Rect? = nil
        var focused: DOMRef? = nil
        for child in ref.children {
            guard let ancestor: DOMRef = focusVisibleInlineAncestor(child.node, line: ref) else {
                continue
            }
            focused = ancestor
            let childRect: Rect = child.selfRect()
            outlineRect = outlineRect?.union(childRect) ?? childRect
        }
        guard let rect: Rect = outlineRect, let focused else { return [] }
        if let outline: DisplayOp = DisplayOp.fromStyle(focused.style.computed, rect: rect) {
            return [outline]
        }
        let ring: (outer: String, inner: String) = focusRingColors(
            forcedColors: usesForcedColors(ref.node)
        )
        return [
            .outline(rect: rect, color: BrowserColor(cssName: ring.outer), width: 4),
            .outline(rect: rect, color: BrowserColor(cssName: ring.inner), width: 2),
        ]
    }

    private func focusVisibleInlineAncestor(_ start: DOMRef, line: LayoutRef) -> DOMRef? {
        var current: DOMRef? = start.parent
        while let ancestor = current, ancestor.id != line.domNode {
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
                docHeight: doc.root.height + 2 * VSTEP,
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
