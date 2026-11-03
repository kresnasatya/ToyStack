import CoreGraphics

// MARK: - EmbedLayoutPass

extension LayoutTree {
    func makeEmbed(
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
        addDependencyEdges(for: id)
        return id
    }

    func embedLayoutNeeded(_ id: LayoutID) -> Bool {
        if hasDirtyDescendants(at: id) {
            profiler.count("layout.dirtyDescendants")
            return true
        }
        let state: LayoutFieldStore = node(id).state.fields
        return state.isDirty(.zoom) || state.isDirty(.width) || state.isDirty(.height)
            || state.isDirty(.font) || state.isDirty(.ascent) || state.isDirty(.descent)
    }

    /// Shared embed body: resolve zoom and baseline font.
    func layoutEmbedCommon(_ id: LayoutID) {
        if isDirty(.zoom, at: id) {
            setField(.zoom, resolvedZoom(id), for: id)
        }
        if isDirty(.font, at: id) {
            setFont(fontForElement(domRef(id), zoom: zoom(id)), for: id)
        }
    }

    func embedSetAscentFromHeight(_ id: LayoutID) {
        setField(.ascent, height(id), for: id)
        setField(.descent, 0, for: id)
    }

    func layoutEmbed(_ id: LayoutID) {
        guard embedLayoutNeeded(id) else { return }
        switch embedData(id) {
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

    func layoutImage(_ id: LayoutID) {
        let sizeDirty: Bool = isDirty(.width, at: id)
            || isDirty(.height, at: id)
            || isDirty(.zoom, at: id)
            || isDirty(.font, at: id)
        setDirtyDescendants(false, at: id)
        layoutEmbedCommon(id)
        guard sizeDirty else { return }
        guard let el = domRef(id).element else { return }
        let available: CGFloat = width(parentID(of: id)!)
        let elementZoom: CGFloat = zoom(id)
        let usedWidth: CGFloat = imageUsedWidth(for: el, available: available, zoom: elementZoom)
        setField(.width, usedWidth, for: id)
        let usedHeight: CGFloat = imageUsedHeight(
            for: el,
            usedWidth: width(id),
            zoom: zoom(id)
        )
        var data: ImageData
        if case .image(let current) = embedData(id) {
            data = current
        } else {
            data = ImageData(imageHeight: 0)
        }
        data.imageHeight = usedHeight
        setKind(.embed(.image(data)), at: id)
        setField(.height, max(usedHeight, font(id).linespace), for: id)
        embedSetAscentFromHeight(id)
    }

    // MARK: - Input

    func layoutInput(_ id: LayoutID) {
        let sizeDirty: Bool = isDirty(.width, at: id)
            || isDirty(.height, at: id)
            || isDirty(.zoom, at: id)
            || isDirty(.font, at: id)
        setDirtyDescendants(false, at: id)
        layoutEmbedCommon(id)
        guard sizeDirty else { return }
        let isCheckbox: Bool = domRef(id).element?.attributes["type"] == "checkbox"
        if isCheckbox {
            setField(.width, font(id).linespace, for: id)
        } else {
            setField(.width, inputWidthPx * zoom(id), for: id)
        }
        setField(.height, font(id).linespace, for: id)
        embedSetAscentFromHeight(id)
    }

    // MARK: - Button

    func layoutButton(_ id: LayoutID) {
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

        setField(.width, inputWidthPx * zoom(id), for: id)

        setChildrenField([], of: id)
        newButtonLine(id)
        for child in domRef(id).children {
            recurseButton(id, child)
        }
        for child in childrenIDs(of: id) {
            layout(child)
        }

        let contentHeight: CGFloat = childrenIDs(of: id).reduce(0) { $0 + height($1) }
        setField(.height, contentHeight == 0 ? font(id).linespace : contentHeight, for: id)

        // A button is an inline container: its baseline stays the font baseline.
        setField(.ascent, font(id).ascent, for: id)
        setField(.descent, font(id).descent, for: id)
    }

    private func newButtonLine(_ id: LayoutID) {
        var data: ButtonData
        if case .button(let current) = embedData(id) {
            data = current
        } else {
            data = ButtonData(cursorX: 0)
        }
        data.cursorX = 0
        setKind(.embed(.button(data)), at: id)
        let previous: LayoutID? = childrenIDs(of: id).last
        let line: LayoutID = makeLine(dom: domID(of: id), parent: id, previous: previous)
        var children: [LayoutID] = childrenIDs(of: id)
        children.append(line)
        setChildrenField(children, of: id)
    }

    private func recurseButton(_ id: LayoutID, _ node: DOMRef) {
        if let textNode = node.text {
            for word in textNode.text.split(whereSeparator: { $0.isWhitespace }) {
                addButtonWord(id, node: node, word: String(word))
            }
        } else if let el = node.element {
            if el.tag == "br" {
                newButtonLine(id)
            } else if el.tag == "input" {
                addButtonInput(id, el)
            } else {
                for child in node.children { recurseButton(id, child) }
            }
        }
    }

    private func addButtonWord(_ id: LayoutID, node: DOMRef, word: String) {
        let font: BrowserFont = fontForElement(node, zoom: zoom(id))
        let w: CGFloat = font.measure(word)
        let cursorX: CGFloat = buttonCursorX(id)
        if cursorX + w > width(id) { newButtonLine(id) }
        guard let line: LayoutID = childrenIDs(of: id).last else { return }
        let prev: LayoutID? = childrenIDs(of: line).last
        let text: LayoutID = makeText(
            TextData(
                word: word,
                display: nil,
                fontOverride: font,
                metrics: TextMetrics(width: 0, whiteSpace: .normal)
            ),
            dom: node.id,
            parent: line,
            previous: prev
        )
        var lineChildren: [LayoutID] = childrenIDs(of: line)
        lineChildren.append(text)
        setChildrenField(lineChildren, of: line)
        setButtonCursorX(id, buttonCursorX(id) + w)
    }

    private func addButtonInput(_ id: LayoutID, _ node: ElementRef) {
        let font: BrowserFont = fontForElement(node.ref, zoom: zoom(id))
        let isCheckbox: Bool = node.attributes["type"] == "checkbox"
        let w: CGFloat = isCheckbox ? font.linespace : inputWidthPx * zoom(id)
        let cursorX: CGFloat = buttonCursorX(id)
        if cursorX + w > width(id) { newButtonLine(id) }
        guard let line: LayoutID = childrenIDs(of: id).last else { return }
        let prev: LayoutID? = childrenIDs(of: line).last
        let input: LayoutID = makeEmbed(
            dom: node.ref.id,
            data: .input,
            parent: line,
            previous: prev
        )
        var lineChildren: [LayoutID] = childrenIDs(of: line)
        lineChildren.append(input)
        setChildrenField(lineChildren, of: line)
        setButtonCursorX(id, buttonCursorX(id) + w)
    }

    private func buttonCursorX(_ id: LayoutID) -> CGFloat {
        guard case .button(let data) = embedData(id) else { return 0 }
        return data.cursorX
    }

    private func setButtonCursorX(_ id: LayoutID, _ value: CGFloat) {
        guard case .button(var data) = embedData(id) else { return }
        data.cursorX = value
        setKind(.embed(.button(data)), at: id)
    }

    // MARK: - Iframe

    func layoutIframe(_ id: LayoutID) {
        let sizeDirty: Bool = isDirty(.width, at: id)
            || isDirty(.height, at: id)
            || isDirty(.zoom, at: id)
            || isDirty(.font, at: id)
        setDirtyDescendants(false, at: id)
        layoutEmbedCommon(id)
        guard sizeDirty else { return }
        guard let el = domRef(id).element else { return }

        let size: (width: CGFloat, height: CGFloat) = iframeDisplaySize(for: el)
        setField(.width, size.width * zoom(id), for: id)
        setField(.height, size.height * zoom(id), for: id)
        embedSetAscentFromHeight(id)

        guard let frame: Frame = el.frame, frame.loaded else { return }
        let innerWidth: CGFloat = width(id) - 2 * zoom(id)
        let innerHeight: CGFloat = height(id) - 2 * zoom(id)
        if frame.frameWidth != innerWidth {
            frame.setViewport(width: innerWidth, height: innerHeight)
            frame.setNeedsRender()
        } else if frame.frameHeight != innerHeight {
            frame.setViewport(width: innerWidth, height: innerHeight)
            frame.setNeedsLayout()
        }
    }

    // MARK: - Canvas

    private func canvasDisplayScale(_ id: LayoutID) -> CGFloat {
        return domRef(id).element?.frame?.tab?.browser?.displayScale ?? 1
    }

    func layoutCanvas(_ id: LayoutID) {
        let sizeDirty: Bool = isDirty(.width, at: id)
            || isDirty(.height, at: id)
            || isDirty(.zoom, at: id)
            || isDirty(.font, at: id)
        setDirtyDescendants(false, at: id)
        layoutEmbedCommon(id)
        guard sizeDirty else { return }
        guard let el = domRef(id).element else { return }
        let size: (width: CGFloat, height: CGFloat) = canvasContentSize(for: el)

        setField(.width, size.width * zoom(id), for: id)
        setField(.height, size.height * zoom(id), for: id)
        embedSetAscentFromHeight(id)

        el.canvasContext?.resize(width: size.width, height: size.height)
        el.canvasContext?.setScale(canvasDisplayScale(id) * pageZoom(id) * zoom(id))
    }
}

// MARK: - Shared embed measurements

let inputWidthPx: CGFloat = 200

@MainActor
func imageDisplaySize(for el: ElementRef) -> (width: Double, height: Double) {
    let intrinsicW: Double = el.image.map { Double($0.width) } ?? 0
    let intrinsicH: Double = el.image.map { Double($0.height) } ?? 0
    let ratio: AspectRatio? = el.style.computed.box.size.aspectRatio
        ?? AspectRatio(intrinsicWidth: intrinsicW, intrinsicHeight: intrinsicH)
    let wAttr: Double? = el.attributes["width"].flatMap({ Double($0) })
    let hAttr: Double? = el.attributes["height"].flatMap({ Double($0) })
    if let w = wAttr, let h = hAttr { return (w, h) }
    else if let w = wAttr { return (w, ratio?.height(forWidth: w) ?? w) }
    else if let h = hAttr { return (ratio?.width(forHeight: h) ?? h, h) }
    return (intrinsicW, intrinsicH)
}

@MainActor
func imageUsedWidth(for el: ElementRef, available: CGFloat, zoom: CGFloat) -> CGFloat {
    let intrinsic: CGFloat = CGFloat(imageDisplaySize(for: el).width) * zoom
    guard let maxWidth: Length = el.style.computed.box.size.maxWidth else {
        return intrinsic
    }
    let limit: CGFloat = maxWidth.resolved(available: available, zoom: zoom)
    return min(intrinsic, limit)
}

@MainActor
func imageUsedHeight(for el: ElementRef, usedWidth: CGFloat, zoom: CGFloat) -> CGFloat {
    let size: (width: Double, height: Double) = imageDisplaySize(for: el)
    let ratio: AspectRatio? = el.style.computed.box.size.aspectRatio
        ?? AspectRatio(intrinsicWidth: size.width, intrinsicHeight: size.height)
    guard let height = ratio?.height(forWidth: Double(usedWidth / zoom)) else {
        return CGFloat(size.height) * zoom
    }
    return CGFloat(height) * zoom
}

let iframeDefaultWidthPx: CGFloat = 300
let iframeDefaultHeightPx: CGFloat = 150

@MainActor
func iframeDisplaySize(for el: ElementRef) -> (width: CGFloat, height: CGFloat) {
    let ratio: AspectRatio? = el.style.computed.box.size.aspectRatio
    let widthAttr: Double? = el.attributes["width"].flatMap({ Double($0) })
    let heightAttr: Double? = el.attributes["height"].flatMap({ Double($0) })
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
    return (CGFloat(content.width) + 2, CGFloat(content.height) + 2)
}

let canvasDefaultWidthPx: CGFloat = 300
let canvasDefaultHeightPx: CGFloat = 150

@MainActor
func canvasContentSize(for el: ElementRef) -> (width: CGFloat, height: CGFloat) {
    let width: CGFloat = el.attributes["width"].flatMap({ Double($0) }).map({ CGFloat($0) }) ?? canvasDefaultWidthPx
    let height: CGFloat = el.attributes["height"].flatMap({ Double($0) }).map({ CGFloat($0) }) ?? canvasDefaultHeightPx
    return (width, height)
}

extension LayoutTree {
    func attachEmbed(_ id: LayoutID, to line: LayoutID, previous: LayoutID?) {
        setPrevious(previous, of: id)
    }
}
