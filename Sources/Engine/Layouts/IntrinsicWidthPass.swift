import CoreGraphics

// MARK: - IntrinsicWidthPass

extension LayoutTree {
    func intrinsicWidths(of node: LayoutDOMView, zoom: CGFloat, available: CGFloat) -> IntrinsicWidths {
        if let element: LayoutElementView = node.element {
            let embedWidth: CGFloat = embedLineWidth(element, available: available, zoom: zoom)
            if embedWidth > 0 {
                return IntrinsicWidths(minContent: embedWidth, maxContent: embedWidth)
            }
        }
        var widths: IntrinsicWidths = .zero
        var line: IntrinsicLine = IntrinsicLine()
        for child in node.children {
            let layout: LayoutStyle = child.style.computed.layout
            if layout.position.kind == .absolute { continue }
            if layout.display == .block {
                widths = widths.stacked(with: line.finish())
                widths = widths.stacked(with: blockWidths(child, zoom: zoom, available: available))
            } else {
                addInline(child, zoom: zoom, available: available, to: &line)
            }
        }
        return widths.stacked(with: line.finish())
    }

    // MARK: - Helpers

    private func blockWidths(_ node: LayoutDOMView, zoom: CGFloat, available: CGFloat) -> IntrinsicWidths {
        let style: ComputedStyle = node.style.computed
        let ownZoom: CGFloat = zoom * (style.box.zoom ?? 1)
        let margin: EdgeInsets = style.box.spacing.margin.scaled(by: ownZoom)
        let edges: EdgeInsets = style.box.paddingAndBorder.scaled(by: ownZoom)
        var outside: CGFloat = margin.horizontal + edges.horizontal
        if node.element?.tag == "li" {
            outside += liIndent
        }
        if let width: CGFloat = style.box.size.width {
            let content: CGFloat = style.box.size.boxSizing.contentSize(
                specified: width * ownZoom,
                paddingAndBorder: edges.horizontal
            )
            return IntrinsicWidths(minContent: content, maxContent: content).widened(by: outside)
        }
        return intrinsicWidths(of: node, zoom: ownZoom, available: available).widened(by: outside)
    }

    private func addInline(
        _ node: LayoutDOMView,
        zoom: CGFloat,
        available: CGFloat,
        to line: inout IntrinsicLine
    ) {
        if let text: LayoutTextView = node.text {
            addText(text, zoom: zoom, to: &line)
            return
        }
        guard let element: LayoutElementView = node.element else { return }
        if element.tag == "br" {
            line.breakLine()
            return
        }
        let width: CGFloat = embedLineWidth(element, available: available, zoom: zoom)
        if width > 0 {
            line.addEmbed(width, textFont: surroundingTextFont(of: element.id, zoom: zoom))
            return
        }
        let edges: EdgeInsets = element.style.computed.box.paddingAndBorder.scaled(by: zoom)
        line.addEdge(edges.left)
        for child in node.children {
            addInline(child, zoom: zoom, available: available, to: &line)
        }
        line.addEdge(edges.right)
    }

    private func addText(_ text: LayoutTextView, zoom: CGFloat, to line: inout IntrinsicLine) {
        let owner: NodeID = inputs.inheritedStyleOwner(text.ref.id)
        let mode: WhiteSpaceMode = inputs.style(owner).text.whiteSpace
        let font: BrowserFont = fontFor(text.ref.id, zoom: zoom)
        let segments: [String] = mode.keepsNewlines
            ? text.text.components(separatedBy: "\n")
            : [text.text]
        for (index, segment) in segments.enumerated() {
            if index > 0 {
                line.breakLine()
            }
            let words: [Substring] = mode.keepSpaces
                ? (segment.isEmpty ? [] : [Substring(segment)])
                : segment.split(whereSeparator: { $0.isWhitespace })
            for word in words {
                line.addPiece(font.measure(String(word)) + font.spaceWidth, breaks: mode.wraps, textFont: font)
            }
        }
    }
}

// MARK: - IntrinsicLine

private struct IntrinsicLine {
    var current: CGFloat = 0
    var widths: IntrinsicWidths = .zero
    var followsEmbed: Bool = false

    mutating func addPiece(_ width: CGFloat, breaks: Bool, textFont: BrowserFont) {
        if followsEmbed {
            current += textFont.spaceWidth
            followsEmbed = false
        }
        current += width
        let unbreakable: CGFloat = breaks ? width : current
        widths.minContent = max(widths.minContent, unbreakable)
    }

    mutating func addEmbed(_ width: CGFloat, textFont: BrowserFont) {
        addPiece(width, breaks: true, textFont: textFont)
        followsEmbed = true
    }

    mutating func addEdge(_ width: CGFloat) {
        current += width
    }

    mutating func breakLine() {
        widths.maxContent = max(widths.maxContent, current)
        current = 0
        followsEmbed = false
    }

    mutating func finish() -> IntrinsicWidths {
        breakLine()
        let result: IntrinsicWidths = widths
        widths = .zero
        return result
    }
}
