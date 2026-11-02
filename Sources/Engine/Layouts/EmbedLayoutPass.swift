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
        let ref: LayoutRef = LayoutRef(id: id, tree: self)
        let parentRef: LayoutRef = LayoutRef(id: parent, tree: self)

        ref.childrenField.setClean([])
        ref.childrenField.setDependencies([])
        ref.fontField.setClean(inlineDefaultFont)
        ref.ascentField.setClean(inlineDefaultFont.ascent)
        ref.descentField.setClean(inlineDefaultFont.descent)
        ref.markAncestorsDirty()

        ref.zoomField.setDependencies([parentRef.zoomField, ref.node.style.field(.zoom)])
        ref.fontField.setDependencies([ref.zoomField] + fontInputs(for: ref.node))
        ref.fontField.mark()
        ref.ascentField.setDependencies([ref.heightField])
        ref.descentField.setDependencies([])
        // Position is assigned by the containing line; there are no inputs.
        ref.xField.setDependencies([])
        ref.yField.setDependencies([])

        switch data {
        case .image:
            ref.widthField.setDependencies([
                parentRef.widthField,
                ref.zoomField,
                ref.node.style.field(.aspectRatio),
                ref.node.style.field(.maxWidth),
            ])
            ref.heightField.setDependencies([
                ref.widthField,
                ref.zoomField,
                ref.fontField,
                ref.node.style.field(.aspectRatio),
            ])
        case .input:
            ref.widthField.setDependencies([ref.fontField, ref.zoomField])
            ref.heightField.setDependencies([ref.fontField])
        case .button:
            // The first inner-line pass runs before the containing line can
            // place this button. Seed a known position so that pass does not
            // read a dirty field.
            ref.xField.set(0)
            ref.yField.set(0)
            ref.widthField.setDependencies([ref.zoomField])
            ref.heightField.setDependencies([ref.fontField])
            ref.ascentField.setDependencies([ref.fontField])
            ref.descentField.setDependencies([ref.fontField])
        case .iframe:
            ref.widthField.setDependencies([
                ref.zoomField,
                ref.node.style.field(.aspectRatio),
            ])
            ref.heightField.setDependencies([
                ref.zoomField,
                ref.node.style.field(.aspectRatio),
            ])
        case .canvas:
            ref.widthField.setDependencies([ref.zoomField])
            ref.heightField.setDependencies([ref.zoomField])
        }
        return id
    }

    func embedLayoutNeeded(_ ref: LayoutRef) -> Bool {
        if ref.hasDirtyDescendants {
            profiler.count("layout.dirtyDescendants")
            return true
        }
        let state: LayoutFieldStore = node(ref.id).state.fields
        return state.isDirty(.zoom) || state.isDirty(.width) || state.isDirty(.height)
            || state.isDirty(.font) || state.isDirty(.ascent) || state.isDirty(.descent)
    }

    /// Shared embed body: resolve zoom and baseline font.
    func layoutEmbedCommon(_ ref: LayoutRef) {
        if ref.tree.isDirty(.zoom, at: ref.id) {
            ref.zoomField.set(ref.resolvedZoom())
        }
        if ref.tree.isDirty(.font, at: ref.id) {
            ref.font = fontForElement(
                ref.node,
                zoom: ref.zoomField.read(notify: ref.fontField),
                notify: ref.fontField
            )
        }
    }

    func embedSetAscentFromHeight(_ ref: LayoutRef) {
        ref.ascent = ref.heightField.read(notify: ref.ascentField)
        ref.descent = 0
    }

    func layoutEmbed(_ ref: LayoutRef) {
        guard embedLayoutNeeded(ref) else { return }
        switch ref.embedData {
        case .image:
            layoutImage(ref)
        case .input:
            layoutInput(ref)
        case .button:
            layoutButton(ref)
        case .iframe:
            layoutIframe(ref)
        case .canvas:
            layoutCanvas(ref)
        }
    }

    // MARK: - Image

    func layoutImage(_ ref: LayoutRef) {
        let sizeDirty: Bool = ref.tree.isDirty(.width, at: ref.id)
            || ref.tree.isDirty(.height, at: ref.id)
            || ref.tree.isDirty(.zoom, at: ref.id)
            || ref.tree.isDirty(.font, at: ref.id)
        ref.hasDirtyDescendants = false
        layoutEmbedCommon(ref)
        guard sizeDirty else { return }
        guard let el = ref.node.element else { return }
        let available: CGFloat = ref.parent!.widthField.read(notify: ref.widthField)
        let zoom: CGFloat = ref.zoomField.read(notify: ref.widthField)
        let usedWidth: CGFloat = imageUsedWidth(
            for: el,
            available: available,
            zoom: zoom,
            notify: ref.widthField
        )
        ref.width = usedWidth
        let usedHeight: CGFloat = imageUsedHeight(
            for: el,
            usedWidth: ref.widthField.read(notify: ref.heightField),
            zoom: ref.zoomField.read(notify: ref.heightField),
            notify: ref.heightField
        )
        var data: ImageData
        if case .image(let current) = ref.embedData {
            data = current
        } else {
            data = ImageData(imageHeight: 0)
        }
        data.imageHeight = usedHeight
        ref.embedData = .image(data)
        ref.height = max(usedHeight, ref.fontField.read(notify: ref.heightField).linespace)
        embedSetAscentFromHeight(ref)
    }

    func paintImage(_ ref: LayoutRef, into items: inout [DisplayOp]) {
        guard let image = ref.node.element?.image else { return }
        guard case .image(let data) = ref.embedData else { return }
        let box = Rect(
            left: ref.x,
            top: ref.y + ref.height - data.imageHeight,
            right: ref.x + ref.width,
            bottom: ref.y + ref.height
        )
        let computed: ComputedStyle = ref.node.style.computed
        let content: Rect = ObjectFit(
            box: box,
            intrinsicWidth: ref.scaled(CGFloat(image.width)),
            intrinsicHeight: ref.scaled(CGFloat(image.height)),
            fit: computed.visual.image.fit
        ).contentRect
        items.append(.clippedImage(
            image: image,
            rendering: computed.visual.image.rendering,
            rect: content,
            clip: box
        ))
    }

    func attachImage(_ ref: LayoutRef, to line: LayoutID) {
        let lineRef: LayoutRef = LayoutRef(id: line, tree: self)
        ref.widthField.setDependencies([
            lineRef.widthField,
            ref.zoomField,
            ref.node.style.field(.aspectRatio),
            ref.node.style.field(.maxWidth),
        ])
        ref.heightField.setDependencies([
            ref.widthField,
            ref.zoomField,
            ref.fontField,
            ref.node.style.field(.aspectRatio),
        ])
    }

    // MARK: - Input

    func layoutInput(_ ref: LayoutRef) {
        let sizeDirty: Bool = ref.tree.isDirty(.width, at: ref.id)
            || ref.tree.isDirty(.height, at: ref.id)
            || ref.tree.isDirty(.zoom, at: ref.id)
            || ref.tree.isDirty(.font, at: ref.id)
        ref.hasDirtyDescendants = false
        layoutEmbedCommon(ref)
        guard sizeDirty else { return }
        let isCheckbox: Bool = ref.node.element?.attributes["type"] == "checkbox"
        if isCheckbox {
            ref.width = ref.fontField.read(notify: ref.widthField).linespace
        } else {
            ref.width = inputWidthPx * ref.zoomField.read(notify: ref.widthField)
        }
        ref.height = ref.fontField.read(notify: ref.heightField).linespace
        embedSetAscentFromHeight(ref)
    }

    func paintInput(_ ref: LayoutRef, into items: inout [DisplayOp]) {
        guard let element = ref.node.element else { return }
        let computed: ComputedStyle = element.style.computed
        if let bgcolor: BrowserColor = computed.visual.background.color {
            let radii: CornerRadii = computed.box.decoration.border.radii
            if !radii.isZero {
                items.append(.rrect(rect: ref.selfRect(), radii: radii, color: bgcolor))
            } else {
                items.append(.rect(rect: ref.selfRect(), color: bgcolor))
            }
        }

        if element.attributes["type"] == "checkbox" {
            items.append(.rect(rect: ref.selfRect(), color: BrowserColor(cssName: usesForcedColors(ref.node) ? ForcedColor.buttonFace : "white")))
            items.append(.outline(rect: ref.selfRect(), color: BrowserColor(cssName: usesForcedColors(ref.node) ? ForcedColor.buttonBorder : "black"), width: 1))
            if element.isChecked {
                items.append(
                    .text(
                        text: "X",
                        font: ref.font,
                        color: BrowserColor(cssName: usesForcedColors(ref.node) ? ForcedColor.buttonText : "black"),
                        rect: Rect(
                            left: ref.x,
                            top: ref.y,
                            right: ref.x + ref.font.measure("X"),
                            bottom: ref.y + ref.font.linespace
                        )
                    )
                )
            }
            let outline: DisplayOp? = DisplayOp.fromStyle(ref.node, rect: ref.selfRect())
            if element.isFocusVisible && outline == nil {
                items.append(.outline(rect: ref.selfRect(), color: BrowserColor(cssName: focusRingColors(ref.node).outer), width: 2))
                items.append(.outline(rect: ref.selfRect(), color: BrowserColor(cssName: focusRingColors(ref.node).inner), width: 4))
            }
            if let outline = outline { items.append(outline) }
        }

        var text: String = ""
        if element.tag == "input" {
            let value: String = element.attributes["value"] ?? ""
            if element.attributes["type"] == "password" {
                text = String(repeating: "*", count: value.count)
            } else {
                text = value
            }
        } else if element.tag == "button" {
            if element.children.count == 1,
                let textNode = element.children[0].text
            {
                text = textNode.text
            }
        }
        items.append(.text(text: text, font: ref.font, color: computed.text.color, rect: Rect(left: ref.x, top: ref.y, right: ref.font.measure(text), bottom: ref.y + ref.font.linespace)))

        if element.isFocused {
            items.append(drawCursor(ref, offset: ref.font.measure(text)))
        }
        let outline: DisplayOp? = DisplayOp.fromStyle(ref.node, rect: ref.selfRect())
        if element.isFocusVisible && outline == nil {
            items.append(.outline(rect: ref.selfRect(), color: BrowserColor(cssName: focusRingColors(ref.node).outer), width: 4))
            items.append(.outline(rect: ref.selfRect(), color: BrowserColor(cssName: focusRingColors(ref.node).inner), width: 2))
        }
        if let outline = outline { items.append(outline) }
    }

    // MARK: - Button

    func layoutButton(_ ref: LayoutRef) {
        guard embedLayoutNeeded(ref) else { return }
        let descendantsDirty: Bool = ref.hasDirtyDescendants
        defer { ref.hasDirtyDescendants = false }
        // The containing line places this button after its children lay out.
        // Seed a known position so the inner line can lay out before that.
        if ref.tree.isDirty(.x, at: ref.id) {
            ref.xField.set(0)
        }
        if ref.tree.isDirty(.y, at: ref.id) {
            ref.yField.set(0)
        }
        let contentDirty: Bool = descendantsDirty
            || ref.tree.isDirty(.width, at: ref.id)
            || ref.tree.isDirty(.height, at: ref.id)
            || ref.tree.isDirty(.zoom, at: ref.id)
            || ref.tree.isDirty(.font, at: ref.id)
        layoutEmbedCommon(ref)
        guard contentDirty else { return }

        ref.width = inputWidthPx * ref.zoomField.read(notify: ref.widthField)

        ref.children = []
        newButtonLine(ref)
        for child in ref.node.children {
            recurseButton(ref, child)
        }
        for child in ref.children {
            child.layout()
        }

        ref.heightField.setDependencies([ref.fontField] + ref.children.map({ $0.heightField }))
        let contentHeight: CGFloat = ref.children.reduce(0) { $0 + $1.height }
        ref.height = contentHeight == 0
            ? ref.fontField.read(notify: ref.heightField).linespace
            : contentHeight

        // A button is an inline container: its baseline stays the font baseline.
        ref.ascent = ref.fontField.read(notify: ref.ascentField).ascent
        ref.descent = ref.fontField.read(notify: ref.descentField).descent
    }

    private func newButtonLine(_ ref: LayoutRef) {
        var data: ButtonData
        if case .button(let current) = ref.embedData {
            data = current
        } else {
            data = ButtonData(cursorX: 0)
        }
        data.cursorX = 0
        ref.embedData = .button(data)
        let previous: LayoutID? = ref.children.last?.id
        let line: LayoutID = makeLine(dom: ref.domNode, parent: ref.id, previous: previous)
        var children: [LayoutID] = ref.children.map({ $0.id })
        children.append(line)
        ref.children = children.map({ LayoutRef(id: $0, tree: self) })
    }

    private func recurseButton(_ ref: LayoutRef, _ node: DOMRef) {
        if let textNode = node.text {
            for word in textNode.text.split(whereSeparator: { $0.isWhitespace }) {
                addButtonWord(ref, node: node, word: String(word))
            }
        } else if let el = node.element {
            if el.tag == "br" {
                newButtonLine(ref)
            } else if el.tag == "input" {
                addButtonInput(ref, el)
            } else {
                for child in node.children { recurseButton(ref, child) }
            }
        }
    }

    private func addButtonWord(_ ref: LayoutRef, node: DOMRef, word: String) {
        let font: BrowserFont = fontForElement(node, zoom: ref.zoom, notify: ref.fontField)
        let w: CGFloat = font.measure(word)
        let cursorX: CGFloat = buttonCursorX(ref)
        if cursorX + w > ref.width { newButtonLine(ref) }
        guard let line: LayoutRef = ref.children.last else { return }
        let prev: LayoutID? = line.children.last?.id
        let text: LayoutID = makeText(
            TextData(
                word: word,
                display: nil,
                fontOverride: font,
                metrics: TextMetrics(width: 0, whiteSpace: .normal)
            ),
            dom: node.id,
            parent: line.id,
            previous: prev
        )
        var lineChildren: [LayoutRef] = line.children
        lineChildren.append(LayoutRef(id: text, tree: self))
        line.children = lineChildren
        setButtonCursorX(ref, buttonCursorX(ref) + w)
    }

    private func addButtonInput(_ ref: LayoutRef, _ node: ElementRef) {
        let font: BrowserFont = fontForElement(node.ref, zoom: ref.zoom, notify: ref.fontField)
        let isCheckbox: Bool = node.attributes["type"] == "checkbox"
        let w: CGFloat = isCheckbox ? font.linespace : ref.scaled(inputWidthPx)
        let cursorX: CGFloat = buttonCursorX(ref)
        if cursorX + w > ref.width { newButtonLine(ref) }
        guard let line: LayoutRef = ref.children.last else { return }
        let prev: LayoutID? = line.children.last?.id
        let input: LayoutID = makeEmbed(
            dom: node.ref.id,
            data: .input,
            parent: line.id,
            previous: prev
        )
        var lineChildren: [LayoutRef] = line.children
        lineChildren.append(LayoutRef(id: input, tree: self))
        line.children = lineChildren
        setButtonCursorX(ref, buttonCursorX(ref) + w)
    }

    private func buttonCursorX(_ ref: LayoutRef) -> CGFloat {
        guard case .button(let data) = ref.embedData else { return 0 }
        return data.cursorX
    }

    private func setButtonCursorX(_ ref: LayoutRef, _ value: CGFloat) {
        guard case .button(var data) = ref.embedData else { return }
        data.cursorX = value
        ref.embedData = .button(data)
    }

    func paintButton(_ ref: LayoutRef, into items: inout [DisplayOp]) {
        guard let element = ref.node.element else { return }
        let computed: ComputedStyle = element.style.computed
        let displayColor: BrowserColor = computed.visual.background.color
            ?? BrowserColor(cssName: usesForcedColors(ref.node) ? ForcedColor.buttonFace : "white")
        items.append(.rect(rect: ref.selfRect(), color: displayColor))
        items.append(.outline(rect: ref.selfRect(), color: BrowserColor(cssName: usesForcedColors(ref.node) ? ForcedColor.buttonBorder : "black"), width: 1))

        let outline: DisplayOp? = DisplayOp.fromStyle(ref.node, rect: ref.selfRect())
        if element.isFocusVisible && outline == nil {
            items.append(.outline(rect: ref.selfRect(), color: BrowserColor(cssName: focusRingColors(ref.node).outer), width: 4))
            items.append(.outline(rect: ref.selfRect(), color: BrowserColor(cssName: focusRingColors(ref.node).inner), width: 2))
        }
        if let outline = outline { items.append(outline) }
    }

    // MARK: - Iframe

    func layoutIframe(_ ref: LayoutRef) {
        let sizeDirty: Bool = ref.tree.isDirty(.width, at: ref.id)
            || ref.tree.isDirty(.height, at: ref.id)
            || ref.tree.isDirty(.zoom, at: ref.id)
            || ref.tree.isDirty(.font, at: ref.id)
        ref.hasDirtyDescendants = false
        layoutEmbedCommon(ref)
        guard sizeDirty else { return }
        guard let el = ref.node.element else { return }

        let size: (width: CGFloat, height: CGFloat) = iframeDisplaySize(for: el, notify: ref.widthField)
        ref.width = size.width * ref.zoomField.read(notify: ref.widthField)
        ref.height = size.height * ref.zoomField.read(notify: ref.heightField)
        embedSetAscentFromHeight(ref)

        guard let frame: Frame = el.frame, frame.loaded else { return }
        let innerWidth: CGFloat = ref.widthField.get() - ref.scaled(2)
        let innerHeight: CGFloat = ref.heightField.get() - ref.scaled(2)
        if frame.frameWidth != innerWidth {
            frame.frameWidth = innerWidth
            frame.frameHeight = innerHeight
            frame.setNeedsRender()
        } else if frame.frameHeight != innerHeight {
            frame.frameHeight = innerHeight
            frame.setNeedsLayout()
        }
    }

    func paintIframe(_ ref: LayoutRef, into items: inout [DisplayOp]) {
        let computed: ComputedStyle = ref.node.style.computed
        guard let bgColor: BrowserColor = computed.visual.background.color else { return }
        let radii: CornerRadii = computed.box.decoration.border.radii
        items.append(.rrect(rect: ref.selfRect(), radii: radii, color: bgColor))
    }

    // MARK: - Canvas

    func layoutCanvas(_ ref: LayoutRef) {
        let sizeDirty: Bool = ref.tree.isDirty(.width, at: ref.id)
            || ref.tree.isDirty(.height, at: ref.id)
            || ref.tree.isDirty(.zoom, at: ref.id)
            || ref.tree.isDirty(.font, at: ref.id)
        ref.hasDirtyDescendants = false
        layoutEmbedCommon(ref)
        guard sizeDirty else { return }
        guard let el = ref.node.element else { return }
        let size: (width: CGFloat, height: CGFloat) = canvasContentSize(for: el)

        ref.width = size.width * ref.zoomField.read(notify: ref.widthField)
        ref.height = size.height * ref.zoomField.read(notify: ref.heightField)
        embedSetAscentFromHeight(ref)

        el.canvasContext?.resize(width: size.width, height: size.height)
        el.canvasContext?.setScale(canvasDisplayScale(ref) * ref.pageZoom * ref.zoomField.get())
    }

    func paintCanvas(_ ref: LayoutRef, into items: inout [DisplayOp]) {
        guard let ctx = ref.node.element?.canvasContext,
            let image: CGImage = ctx.image()
        else { return }
        items.append(.image(image: image, rendering: .auto, rect: ref.selfRect(), version: ctx.revision))
    }
}

// MARK: - Shared embed measurements

let inputWidthPx: CGFloat = 200

@MainActor
func imageDisplaySize(
    for el: ElementRef,
    notify: any InvalidatableField
) -> (width: Double, height: Double) {
    let intrinsicW: Double = el.image.map { Double($0.width) } ?? 0
    let intrinsicH: Double = el.image.map { Double($0.height) } ?? 0
    el.style.field(.aspectRatio).touch(notify)
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
func imageUsedWidth(
    for el: ElementRef,
    available: CGFloat,
    zoom: CGFloat,
    notify: any InvalidatableField
) -> CGFloat {
    let intrinsic: CGFloat = CGFloat(imageDisplaySize(for: el, notify: notify).width) * zoom
    el.style.field(.maxWidth).touch(notify)
    guard let maxWidth: Length = el.style.computed.box.size.maxWidth else {
        return intrinsic
    }
    let limit: CGFloat = maxWidth.resolved(available: available, zoom: zoom)
    return min(intrinsic, limit)
}

@MainActor
func imageUsedHeight(
    for el: ElementRef,
    usedWidth: CGFloat,
    zoom: CGFloat,
    notify: any InvalidatableField
) -> CGFloat {
    let size: (width: Double, height: Double) = imageDisplaySize(for: el, notify: notify)
    el.style.field(.aspectRatio).touch(notify)
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
func iframeDisplaySize(
    for el: ElementRef,
    notify: any InvalidatableField
) -> (width: CGFloat, height: CGFloat) {
    el.style.field(.aspectRatio).touch(notify)
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

@MainActor
private func canvasDisplayScale(_ ref: LayoutRef) -> CGFloat {
    return ref.node.element?.frame?.tab?.browser?.displayScale ?? 1
}


extension LayoutTree {
    func attachEmbed(_ ref: LayoutRef, to line: LayoutID, previous: LayoutID?) {
        embedDetach(ref)
        setPrevious(previous, of: ref.id)
        let lineRef: LayoutRef = LayoutRef(id: line, tree: self)
        ref.zoomField.setDependencies([lineRef.zoomField, ref.node.style.field(.zoom)])
    }

    private func embedDetach(_ ref: LayoutRef) {
        if let oldParent: LayoutRef = ref.parent {
            oldParent.xField.removeInvalidation(ref.xField)
            oldParent.yField.removeInvalidation(ref.yField)
            oldParent.zoomField.removeInvalidation(ref.zoomField)
            if oldParent.isLine {
                oldParent.ascentField.removeInvalidation(ref.yField)
            }
        }
        if let oldPrevious: LayoutRef = ref.previous {
            oldPrevious.xField.removeInvalidation(ref.xField)
            oldPrevious.widthField.removeInvalidation(ref.xField)
            if oldPrevious.isText || oldPrevious.isEmbed {
                oldPrevious.fontField.removeInvalidation(ref.xField)
            }
        }
    }
}
