import CoreGraphics

// MARK: - EmbedLayoutPass

extension LayoutTree {
    mutating func makeEmbed(
        dom: NodeID,
        data: EmbedData,
        parent: LayoutID,
        previous: LayoutID?
    ) -> LayoutID {
        let id: LayoutID = append(kind: .embed(data), dom: dom, parent: parent, previous: previous)
        setPrimary(id, for: dom)

        setChildrenClean([], of: id)
        setFontClean(inlineDefaultFont, for: id)
        setFieldClean(.ascent, inlineDefaultFont.ascent, for: id)
        setFieldClean(.descent, inlineDefaultFont.descent, for: id)
        for field in [
            LayoutField.zoom, .x, .y, .width, .height,
        ] {
            markUsed(field, at: id)
        }
        markAncestorsDirty(from: id)
        markField(.font, at: id)

        if case .button = data {
            // The first inner-line pass runs before the containing line can
            // place this button. Seed a known position so that pass does not
            // read a dirty field.
            setField(.x, 0, for: id)
            setField(.y, 0, for: id)
        }
        return id
    }

    func embedLayoutNeeded(_ id: LayoutID) -> Bool {
        if hasDirtyDescendants(at: id) {
            profiler.count("layout.dirtyDescendants")
            return true
        }
        let state: FieldState = self[node: id].state.fields.state
        return state.isDirty(.zoom) || state.isDirty(.width) || state.isDirty(.height)
            || state.isDirty(.font) || state.isDirty(.ascent) || state.isDirty(.descent)
    }

    mutating func layoutEmbedCommon(_ id: LayoutID) {
        if isDirty(.zoom, at: id) {
            setField(.zoom, resolvedZoom(id), for: id)
        }
        if isDirty(.font, at: id) {
            setFont(fontFor(domID(of: id), zoom: zoom(id)), for: id)
        }
    }

    /// CSS 2.1 §10.8.1: a replaced element sits on the baseline by the bottom
    /// of its margin box, so padding and border lift it and widen the line.
    mutating func embedSetAscentFromHeight(_ id: LayoutID) {
        setField(.ascent, height(id) + embedEdges(id).vertical, for: id)
        setField(.descent, 0, for: id)
    }

    mutating func layoutEmbed(_ id: LayoutID) {
        guard embedLayoutNeeded(id) else { return }
        switch self[embed: id] {
        case .image:
            layoutImage(id)
        case .input:
            layoutInput(id)
        case .button:
            layoutButton(id)
        case .iframe:
            layoutIframe(id)
        case .canvas:
            layoutCanvas(id)
        }
    }

    // MARK: - Image

    mutating func layoutImage(_ id: LayoutID) {
        let sizeDirty: Bool = isDirty(.width, at: id)
            || isDirty(.height, at: id)
            || isDirty(.zoom, at: id)
            || isDirty(.font, at: id)
        setDirtyDescendants(false, at: id)
        layoutEmbedCommon(id)
        guard sizeDirty else { return }
        guard let el = domView(id).element else { return }
        let size: (width: CGFloat, height: CGFloat) = imageUsedSize(
            EmbedMetrics(el),
            available: embedContainingWidth(id),
            zoom: zoom(id),
            edges: embedEdges(id)
        )
        let usedHeight: CGFloat = size.height
        setField(.width, size.width, for: id)
        var data: ImageData
        if case .image(let current) = self[embed: id] {
            data = current
        } else {
            data = ImageData(imageHeight: 0)
        }
        data.imageHeight = usedHeight
        self[embed: id] = .image(data)
        setField(.height, max(usedHeight, font(id).linespace), for: id)
        embedSetAscentFromHeight(id)
    }

    // MARK: - Input

    mutating func layoutInput(_ id: LayoutID) {
        let sizeDirty: Bool = isDirty(.width, at: id)
            || isDirty(.height, at: id)
            || isDirty(.zoom, at: id)
            || isDirty(.font, at: id)
        setDirtyDescendants(false, at: id)
        layoutEmbedCommon(id)
        guard sizeDirty else { return }
        let isCheckbox: Bool = domView(id).element?.attributes["type"] == "checkbox"
        if isCheckbox {
            setField(.width, font(id).linespace, for: id)
        } else {
            setField(.width, inputWidthPx * zoom(id), for: id)
        }
        setField(.height, font(id).linespace, for: id)
        embedSetAscentFromHeight(id)
    }

    // MARK: - Button

    mutating func layoutButton(_ id: LayoutID) {
        guard embedLayoutNeeded(id) else { return }
        let descendantsDirty: Bool = hasDirtyDescendants(at: id)
        defer { setDirtyDescendants(false, at: id) }
        // The containing line places this button after its children lay out.
        // Seed a known position so the inner line can lay out before that.
        if isDirty(.x, at: id) {
            setField(.x, 0, for: id)
        }
        if isDirty(.y, at: id) {
            setField(.y, 0, for: id)
        }
        let contentDirty: Bool = descendantsDirty
            || isDirty(.width, at: id)
            || isDirty(.height, at: id)
            || isDirty(.zoom, at: id)
            || isDirty(.font, at: id)
        layoutEmbedCommon(id)
        guard contentDirty else { return }

        let pieces: [ButtonLabelPiece] = buttonLabelPieces(domView(id), zoom: zoom(id))
        let available: CGFloat = embedContainingWidth(id) - embedEdges(id).horizontal
        setField(.width, ButtonLabelPiece.shrinkToFit(pieces, available: available), for: id)

        setChildrenField([], of: id)
        newButtonLine(id)
        for piece in pieces {
            addButtonPiece(id, piece)
        }
        for child in childrenIDs(of: id) {
            layout(child)
        }

        let contentHeight: CGFloat = childrenIDs(of: id).reduce(0) { $0 + height($1) }
        setField(.height, contentHeight == 0 ? font(id).linespace : contentHeight, for: id)

        // A button is an inline container: its baseline stays the font
        // baseline, moved down by its top padding and border.
        let edges: EdgeInsets = embedEdges(id)
        setField(.ascent, font(id).ascent + edges.top, for: id)
        setField(.descent, font(id).descent + edges.bottom, for: id)
    }

    mutating private func newButtonLine(_ id: LayoutID) {
        var data: ButtonData
        if case .button(let current) = self[embed: id] {
            data = current
        } else {
            data = ButtonData(cursorX: 0)
        }
        data.cursorX = 0
        self[embed: id] = .button(data)
        let previous: LayoutID? = childrenIDs(of: id).last
        let line: LayoutID = makeLine(dom: domID(of: id), parent: id, previous: previous)
        self[line: line].content.centered = true
        var children: [LayoutID] = childrenIDs(of: id)
        children.append(line)
        setChildrenField(children, of: id)
    }

    /// The label's words, line breaks, and inputs in order, each measured at
    /// `zoom`, so sizing the button and filling its lines see the same pieces.
    func buttonLabelPieces(_ node: LayoutDOMView, zoom: CGFloat) -> [ButtonLabelPiece] {
        var pieces: [ButtonLabelPiece] = []
        collectButtonPieces(node.children, zoom: zoom, into: &pieces)
        return pieces
    }

    private func collectButtonPieces(_ nodes: [LayoutDOMView], zoom: CGFloat, into pieces: inout [ButtonLabelPiece]) {
        for node in nodes {
            if let textNode = node.text {
                let font: BrowserFont = fontFor(node.id, zoom: zoom)
                for word in textNode.text.split(whereSeparator: { $0.isWhitespace }) {
                    let text: String = String(word)
                    let piece: ButtonLabelPiece = ButtonLabelPiece(
                        kind: .word(text, font),
                        dom: node.id,
                        width: font.measure(text),
                        spaceAfter: font.spaceWidth
                    )
                    ButtonLabelPiece.append(piece, textFont: font, to: &pieces)
                }
            } else if let el = node.element {
                if el.tag == "br" {
                    pieces.append(ButtonLabelPiece(kind: .lineBreak, dom: node.id, width: 0, spaceAfter: 0))
                } else if el.tag == "input" {
                    let isCheckbox: Bool = el.attributes["type"] == "checkbox"
                    let content: CGFloat = isCheckbox ? fontFor(node.id, zoom: zoom).linespace : inputWidthPx * zoom
                    let edges: EdgeInsets = el.style.computed.box.paddingAndBorder.scaled(by: zoom)
                    let piece: ButtonLabelPiece = ButtonLabelPiece(
                        kind: .input,
                        dom: node.id,
                        width: content + edges.horizontal,
                        spaceAfter: 0
                    )
                    ButtonLabelPiece.append(piece, textFont: surroundingTextFont(of: node.id, zoom: zoom), to: &pieces)
                } else {
                    collectButtonPieces(node.children, zoom: zoom, into: &pieces)
                }
            }
        }
    }

    mutating private func addButtonPiece(_ id: LayoutID, _ piece: ButtonLabelPiece) {
        switch piece.kind {
        case .lineBreak:
            newButtonLine(id)
        case .word(let word, let font):
            placeButtonPiece(id, piece) { tree, line, previous in
                tree.makeText(
                    TextData(
                        payload: TextPayload(word: word, display: nil, fontOverride: font),
                        fragment: nil,
                        metrics: TextMetrics(width: 0, whiteSpace: .normal)
                    ),
                    dom: piece.dom,
                    parent: line,
                    previous: previous
                )
            }
        case .input:
            placeButtonPiece(id, piece) { tree, line, previous in
                tree.makeEmbed(dom: piece.dom, data: .input, parent: line, previous: previous)
            }
        }
    }

    mutating private func placeButtonPiece(
        _ id: LayoutID,
        _ piece: ButtonLabelPiece,
        make: (inout LayoutTree, LayoutID, LayoutID?) -> LayoutID
    ) {
        if buttonCursorX(id) + piece.width > width(id) { newButtonLine(id) }
        guard let line: LayoutID = childrenIDs(of: id).last else { return }
        let previous: LayoutID? = childrenIDs(of: line).last
        let child: LayoutID = make(&self, line, previous)
        var lineChildren: [LayoutID] = childrenIDs(of: line)
        lineChildren.append(child)
        setChildrenField(lineChildren, of: line)
        setButtonCursorX(id, piece.advance(from: buttonCursorX(id)))
    }

    private func buttonCursorX(_ id: LayoutID) -> CGFloat {
        guard case .button(let data) = self[embed: id] else { return 0 }
        return data.cursorX
    }

    mutating private func setButtonCursorX(_ id: LayoutID, _ value: CGFloat) {
        guard case .button(var data) = self[embed: id] else { return }
        data.cursorX = value
        self[embed: id] = .button(data)
    }

    // MARK: - Iframe

    mutating func layoutIframe(_ id: LayoutID) {
        let sizeDirty: Bool = isDirty(.width, at: id)
            || isDirty(.height, at: id)
            || isDirty(.zoom, at: id)
            || isDirty(.font, at: id)
        setDirtyDescendants(false, at: id)
        layoutEmbedCommon(id)
        guard sizeDirty else { return }
        guard let el = domView(id).element else { return }

        let metrics: EmbedMetrics = EmbedMetrics(el)
        let size: (width: CGFloat, height: CGFloat) = replacedUsedSize(
            iframeDisplaySize(metrics),
            metrics: metrics,
            zoom: zoom(id),
            edges: embedEdges(id)
        )
        setField(.width, size.width, for: id)
        setField(.height, size.height, for: id)
        embedSetAscentFromHeight(id)

        note(.iframeViewport(node: domID(of: id), width: width(id), height: height(id)))
    }

    // MARK: - Canvas

    mutating func layoutCanvas(_ id: LayoutID) {
        let sizeDirty: Bool = isDirty(.width, at: id)
            || isDirty(.height, at: id)
            || isDirty(.zoom, at: id)
            || isDirty(.font, at: id)
        setDirtyDescendants(false, at: id)
        layoutEmbedCommon(id)
        guard sizeDirty else { return }
        guard let el = domView(id).element else { return }
        let size: (width: CGFloat, height: CGFloat) = canvasContentSize(attributes: el.attributes)
        let used: (width: CGFloat, height: CGFloat) = replacedUsedSize(
            size,
            metrics: EmbedMetrics(el),
            zoom: zoom(id),
            edges: embedEdges(id)
        )
        setField(.width, used.width, for: id)
        setField(.height, used.height, for: id)
        embedSetAscentFromHeight(id)

        note(.canvasSize(
            node: domID(of: id),
            width: size.width,
            height: size.height,
            scale: pageZoom(id) * zoom(id)
        ))
    }
}

// MARK: - Embed metrics

struct EmbedMetrics {
    let image: CGImage?
    let style: ComputedStyle
    let attributes: [String: String]
}

extension EmbedMetrics {
    init(_ el: LayoutElementView) {
        self.init(image: el.image, style: el.style.computed, attributes: el.attributes)
    }
}

extension EmbedMetrics {
    /// HTML's width and height attributes are presentational hints for the CSS
    /// properties, so CSS Sizing 3 §3.3 box-sizing applies to them too.
    func specifiedContent(_ size: CGFloat, attribute: String, paddingAndBorder: CGFloat) -> CGFloat {
        guard attributes[attribute] != nil else { return size }
        return style.box.size.boxSizing.contentSize(specified: size, paddingAndBorder: paddingAndBorder)
    }
}

extension LayoutTree {
    /// Edges scale with the line's zoom, the same zoom the block used to
    /// reserve the embed's room on that line.
    private func embedEdgeZoom(_ id: LayoutID) -> CGFloat {
        return parentID(of: id).map({ zoom($0) }) ?? 1
    }

    /// Padding plus used border around an embed's content box: the room it
    /// takes on its line beyond its content size.
    func embedEdges(_ id: LayoutID) -> EdgeInsets {
        return inputs.style(domID(of: id)).box.paddingAndBorder.scaled(by: embedEdgeZoom(id))
    }

    func embedBorderWidths(_ id: LayoutID) -> EdgeInsets {
        return inputs.style(domID(of: id)).box.decoration.border.usedWidths.scaled(by: embedEdgeZoom(id))
    }

    /// The font text gets next to an embed: its parent's, since the embed's
    /// own font only reaches the text inside it.
    func surroundingTextFont(of embed: NodeID, zoom: CGFloat) -> BrowserFont {
        return fontFor(inputs.parent(embed) ?? embed, zoom: zoom)
    }

    /// CSS 2.1 §10.1: percentages resolve against the containing block, the
    /// block that owns the line, not the line, which floats may shorten.
    private func embedContainingWidth(_ id: LayoutID) -> CGFloat {
        guard let line: LayoutID = parentID(of: id) else { return 0 }
        return width(parentID(of: line) ?? line)
    }

    /// The room an embed takes on a line: its content width, after
    /// box-sizing, plus its horizontal padding and border.
    func embedLineWidth(_ node: LayoutElementView, available: CGFloat, zoom: CGFloat) -> CGFloat {
        let metrics: EmbedMetrics = EmbedMetrics(node)
        let edges: EdgeInsets = metrics.style.box.paddingAndBorder.scaled(by: zoom)
        let content: CGFloat
        switch node.tag {
        case "img":
            content = imageUsedWidth(metrics, available: available, zoom: zoom)
        case "input":
            content = node.attributes["type"] == "checkbox"
                ? fontFor(node.ref.id, zoom: zoom).linespace
                : inputWidthPx * zoom
        case "button":
            // `layoutButton` measures the label at the button's own zoom.
            let labelZoom: CGFloat = zoom * (metrics.style.box.zoom ?? 1)
            content = ButtonLabelPiece.shrinkToFit(
                buttonLabelPieces(node.ref, zoom: labelZoom),
                available: available - edges.horizontal
            )
        case "iframe":
            content = iframeDisplaySize(metrics).width * zoom
        case "canvas":
            content = canvasContentSize(attributes: node.attributes).width * zoom
        default:
            return 0
        }
        let used: CGFloat = metrics.specifiedContent(content, attribute: "width", paddingAndBorder: edges.horizontal)
        return used + edges.horizontal
    }

    /// The ascent and descent `layoutEmbed` will give this element on a line
    /// of `block`, so line breaking can know a line's height before layout.
    func embedExtent(_ node: LayoutElementView, in block: LayoutID) -> InlineExtent {
        let lineZoom: CGFloat = zoom(block)
        let style: ComputedStyle = node.style.computed
        let embedZoom: CGFloat = lineZoom * (style.box.zoom ?? 1)
        let edges: EdgeInsets = style.box.paddingAndBorder.scaled(by: lineZoom)
        let font: BrowserFont = fontFor(node.ref.id, zoom: embedZoom)
        let metrics: EmbedMetrics = EmbedMetrics(node)
        switch node.tag {
        case "img":
            let size: (width: CGFloat, height: CGFloat) = imageUsedSize(
                metrics,
                available: width(block),
                zoom: embedZoom,
                edges: edges
            )
            return InlineExtent(ascent: max(size.height, font.linespace) + edges.vertical, descent: 0)
        case "input":
            return InlineExtent(ascent: font.linespace + edges.vertical, descent: 0)
        case "button":
            return InlineExtent(ascent: font.ascent + edges.top, descent: font.descent + edges.bottom)
        case "iframe":
            let size: (width: CGFloat, height: CGFloat) = replacedUsedSize(
                iframeDisplaySize(metrics),
                metrics: metrics,
                zoom: embedZoom,
                edges: edges
            )
            return InlineExtent(ascent: size.height + edges.vertical, descent: 0)
        case "canvas":
            let size: (width: CGFloat, height: CGFloat) = replacedUsedSize(
                canvasContentSize(attributes: node.attributes),
                metrics: metrics,
                zoom: embedZoom,
                edges: edges
            )
            return InlineExtent(ascent: size.height + edges.vertical, descent: 0)
        default:
            return .zero
        }
    }
}

// MARK: - Shared embed measurements

let inputWidthPx: CGFloat = 200

func imageDisplaySize(_ metrics: EmbedMetrics) -> (width: Double, height: Double) {
    let intrinsicW: Double = metrics.image.map { Double($0.width) } ?? 0
    let intrinsicH: Double = metrics.image.map { Double($0.height) } ?? 0
    let ratio: AspectRatio? = metrics.style.box.size.constraints.aspectRatio
        ?? AspectRatio(intrinsicWidth: intrinsicW, intrinsicHeight: intrinsicH)
    let wAttr: Double? = metrics.attributes["width"].flatMap({ Double($0) })
    let hAttr: Double? = metrics.attributes["height"].flatMap({ Double($0) })
    if let w = wAttr, let h = hAttr { return (w, h) }
    else if let w = wAttr { return (w, ratio?.height(forWidth: w) ?? w) }
    else if let h = hAttr { return (ratio?.width(forHeight: h) ?? h, h) }
    return (intrinsicW, intrinsicH)
}

func imageUsedWidth(_ metrics: EmbedMetrics, available: CGFloat, zoom: CGFloat) -> CGFloat {
    let intrinsic: CGFloat = CGFloat(imageDisplaySize(metrics).width) * zoom
    guard let maxWidth: Length = metrics.style.box.size.constraints.maxWidth else {
        return intrinsic
    }
    let limit: CGFloat = maxWidth.resolved(available: available, zoom: zoom)
    return min(intrinsic, limit)
}

func imageUsedHeight(_ metrics: EmbedMetrics, usedWidth: CGFloat, zoom: CGFloat) -> CGFloat {
    let size: (width: Double, height: Double) = imageDisplaySize(metrics)
    let ratio: AspectRatio? = metrics.style.box.size.constraints.aspectRatio
        ?? AspectRatio(intrinsicWidth: size.width, intrinsicHeight: size.height)
    guard let height = ratio?.height(forWidth: Double(usedWidth / zoom)) else {
        return CGFloat(size.height) * zoom
    }
    return CGFloat(height) * zoom
}

/// A height attribute sizes the same box as the width attribute; without one,
/// the ratio applies to the content width.
func imageUsedSize(
    _ metrics: EmbedMetrics,
    available: CGFloat,
    zoom: CGFloat,
    edges: EdgeInsets
) -> (width: CGFloat, height: CGFloat) {
    let specifiedWidth: CGFloat = imageUsedWidth(metrics, available: available, zoom: zoom)
    let usedWidth: CGFloat = metrics.specifiedContent(
        specifiedWidth,
        attribute: "width",
        paddingAndBorder: edges.horizontal
    )
    let usedHeight: CGFloat = metrics.attributes["height"] != nil
        ? metrics.specifiedContent(
            imageUsedHeight(metrics, usedWidth: specifiedWidth, zoom: zoom),
            attribute: "height",
            paddingAndBorder: edges.vertical
        )
        : imageUsedHeight(metrics, usedWidth: usedWidth, zoom: zoom)
    return (usedWidth, usedHeight)
}

/// Iframes and canvases: a fixed size in CSS pixels, after box-sizing.
func replacedUsedSize(
    _ size: (width: CGFloat, height: CGFloat),
    metrics: EmbedMetrics,
    zoom: CGFloat,
    edges: EdgeInsets
) -> (width: CGFloat, height: CGFloat) {
    return (
        metrics.specifiedContent(size.width * zoom, attribute: "width", paddingAndBorder: edges.horizontal),
        metrics.specifiedContent(size.height * zoom, attribute: "height", paddingAndBorder: edges.vertical)
    )
}

let iframeDefaultWidthPx: CGFloat = 300
let iframeDefaultHeightPx: CGFloat = 150

func iframeDisplaySize(_ metrics: EmbedMetrics) -> (width: CGFloat, height: CGFloat) {
    let ratio: AspectRatio? = metrics.style.box.size.constraints.aspectRatio
    let widthAttr: Double? = metrics.attributes["width"].flatMap({ Double($0) })
    let heightAttr: Double? = metrics.attributes["height"].flatMap({ Double($0) })
    let content: (width: Double, height: Double)
    if let w = widthAttr, let h = heightAttr {
        content = (w, h)
    } else if let w = widthAttr {
        content = (w, ratio?.height(forWidth: w) ?? Double(iframeDefaultHeightPx))
    } else if let h = heightAttr {
        content = (ratio?.width(forHeight: h) ?? Double(iframeDefaultWidthPx), h)
    } else if let ratio {
        content = (Double(iframeDefaultWidthPx), ratio.height(forWidth: Double(iframeDefaultWidthPx)))
    } else {
        content = (Double(iframeDefaultWidthPx), Double(iframeDefaultHeightPx))
    }
    return (CGFloat(content.width), CGFloat(content.height))
}

let canvasDefaultWidthPx: CGFloat = 300
let canvasDefaultHeightPx: CGFloat = 150

func canvasContentSize(attributes: [String: String]) -> (width: CGFloat, height: CGFloat) {
    let width: CGFloat = attributes["width"].flatMap({ Double($0) }).map({ CGFloat($0) }) ?? canvasDefaultWidthPx
    let height: CGFloat = attributes["height"].flatMap({ Double($0) }).map({ CGFloat($0) }) ?? canvasDefaultHeightPx
    return (width, height)
}

extension LayoutTree {
    mutating func attachEmbed(_ id: LayoutID, to line: LayoutID, previous: LayoutID?) {
        setPrevious(previous, of: id)
    }
}
