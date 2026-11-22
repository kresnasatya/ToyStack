import CoreGraphics

// MARK: - PageText

struct PageText {
    private let tree: LayoutTree
    private let pieces: [TextPiece]
    private let piecesByNode: [NodeID: [Int]]

    @MainActor
    init(tree: LayoutTree) {
        var collector: TextPieceCollector = TextPieceCollector(tree: tree)
        collector.visit(tree.rootID, shift: Point(x: 0, y: 0))
        self.tree = tree
        self.pieces = collector.pieces
        self.piecesByNode = collector.piecesByNode
    }

    // MARK: - Points

    func range(of unit: TextUnit, atX x: CGFloat, y: CGFloat) -> TextRange? {
        guard let index: Int = nearestPiece(x: x, y: y) else { return nil }
        let piece: TextPiece = pieces[index]
        let offsets: [CGFloat] = piece.text.font.caretOffsets(piece.text.string)
        let localX: CGFloat = x - piece.bounds.shown.left
        switch unit {
        case .character:
            let gap: TextPosition = position(TextPlace(piece: index, offset: nearestGap(offsets, to: localX)))
            return TextRange(start: gap, end: gap)
        case .word:
            return wordRange(index, character: characterIndex(offsets, at: localX))
        case .paragraph:
            return paragraphRange(index)
        }
    }

    private func nearestPiece(x: CGFloat, y: CGFloat) -> Int? {
        var best: Int? = nil
        var bestVertical: CGFloat = .infinity
        var bestHorizontal: CGFloat = .infinity
        for (index, piece) in pieces.enumerated() {
            let rect: Rect = piece.bounds.shown
            let vertical: CGFloat = max(rect.top - y, y - rect.bottom, 0)
            let horizontal: CGFloat = max(rect.left - x, x - rect.right, 0)
            if vertical < bestVertical || (vertical == bestVertical && horizontal < bestHorizontal) {
                best = index
                bestVertical = vertical
                bestHorizontal = horizontal
            }
        }
        return best
    }

    private func nearestGap(_ offsets: [CGFloat], to x: CGFloat) -> Int {
        var best: Int = 0
        for index in offsets.indices where abs(offsets[index] - x) < abs(offsets[best] - x) {
            best = index
        }
        return best
    }

    private func characterIndex(_ offsets: [CGFloat], at x: CGFloat) -> Int? {
        let count: Int = offsets.count - 1
        guard count > 0 else { return nil }
        var index: Int = 0
        while index + 1 < count && offsets[index + 1] <= x {
            index += 1
        }
        return index
    }

    private func wordRange(_ index: Int, character: Int?) -> TextRange {
        let characters: [Character] = Array(pieces[index].text.string)
        guard let character else {
            let gap: TextPosition = position(TextPlace(piece: index, offset: 0))
            return TextRange(start: gap, end: gap)
        }
        let kind: CharacterKind = CharacterKind(characters[character])
        var lower: Int = character
        while lower > 0 && CharacterKind(characters[lower - 1]) == kind {
            lower -= 1
        }
        var upper: Int = character + 1
        while upper < characters.count && CharacterKind(characters[upper]) == kind {
            upper += 1
        }
        return TextRange(
            start: position(TextPlace(piece: index, offset: lower)),
            end: position(TextPlace(piece: index, offset: upper))
        )
    }

    private func paragraphRange(_ index: Int) -> TextRange {
        let block: LayoutID? = tree.parentID(of: pieces[index].line)
        var first: Int = index
        while first > 0 && tree.parentID(of: pieces[first - 1].line) == block {
            first -= 1
        }
        var last: Int = index
        while last + 1 < pieces.count && tree.parentID(of: pieces[last + 1].line) == block {
            last += 1
        }
        return TextRange(
            start: position(TextPlace(piece: first, offset: 0)),
            end: position(TextPlace(piece: last, offset: pieces[last].text.string.count))
        )
    }

    // MARK: - Positions

    func span(covering ranges: [TextRange]) -> TextSpan? {
        var places: [TextPlace] = []
        for range in ranges {
            guard let start: TextPlace = place(range.start), let end: TextPlace = place(range.end) else {
                return nil
            }
            places.append(start)
            places.append(end)
        }
        guard let first: TextPlace = places.min(), let last: TextPlace = places.max() else { return nil }
        return TextSpan(start: first, end: last)
    }

    private func position(_ place: TextPlace) -> TextPosition {
        let piece: TextPiece = pieces[place.piece]
        return TextPosition(node: piece.node, offset: piece.text.start + place.offset)
    }

    private func place(_ position: TextPosition) -> TextPlace? {
        guard let indices: [Int] = piecesByNode[position.node], var chosen: Int = indices.first else {
            return nil
        }
        for index in indices.dropFirst() {
            guard pieces[index].text.start <= position.offset else { break }
            chosen = index
        }
        let text: TextPieceText = pieces[chosen].text
        let offset: Int = min(max(position.offset - text.start, 0), text.string.count)
        return TextPlace(piece: chosen, offset: offset)
    }

    // MARK: - Text

    func string(in span: TextSpan) -> String {
        var result: String = ""
        for index in span.start.piece...span.end.piece {
            if index > span.start.piece {
                result += separator(before: index)
            }
            let characters: [Character] = Array(pieces[index].text.string)
            let lower: Int = index == span.start.piece ? span.start.offset : 0
            let upper: Int = index == span.end.piece ? span.end.offset : characters.count
            result += String(characters[lower..<upper])
        }
        return result
    }

    private func separator(before index: Int) -> String {
        let previous: TextPiece = pieces[index - 1]
        let current: TextPiece = pieces[index]
        if previous.line == current.line { return " " }
        guard let block: LayoutID = tree.parentID(of: current.line),
            tree.parentID(of: previous.line) == block
        else { return "\n" }
        let breaks: Bool = isForcedBreak(
            from: previous.node,
            to: current.node,
            within: tree.domID(of: block)
        )
        return breaks ? "\n" : " "
    }

    private func isForcedBreak(from earlier: NodeID, to later: NodeID, within block: NodeID) -> Bool {
        let inputs: LayoutInputs = tree.inputs
        let mode: WhiteSpaceMode = inputs.style(inputs.inheritedStyleOwner(earlier)).text.whiteSpace
        if !mode.wraps { return true }
        if earlier == later { return mode.keepSpaces }
        var current: NodeID? = nextInDocument(after: earlier, within: block)
        while let node = current, node != later {
            if inputs.tag(node) == "br" { return true }
            current = nextInDocument(after: node, within: block)
        }
        return false
    }

    private func nextInDocument(after node: NodeID, within root: NodeID) -> NodeID? {
        let inputs: LayoutInputs = tree.inputs
        if let child: NodeID = inputs.children(node).first {
            return child
        }
        var current: NodeID = node
        while current != root, let parent: NodeID = inputs.parent(current) {
            let siblings: [NodeID] = inputs.children(parent)
            if let index: Int = siblings.firstIndex(of: current), index + 1 < siblings.count {
                return siblings[index + 1]
            }
            current = parent
        }
        return nil
    }

    // MARK: - Paint

    func highlights(in span: TextSpan) -> [LayoutID: [Rect]] {
        var result: [LayoutID: [Rect]] = [:]
        guard span.start != span.end else { return result }
        for index in span.start.piece...span.end.piece {
            let piece: TextPiece = pieces[index]
            let rect: Rect = piece.bounds.layout
            let isFirst: Bool = index == span.start.piece
            let isLast: Bool = index == span.end.piece
            var left: CGFloat = rect.left
            var right: CGFloat = rect.right
            if isFirst || isLast {
                let offsets: [CGFloat] = piece.text.font.caretOffsets(piece.text.string)
                if isFirst { left += offsets[span.start.offset] }
                if isLast { right = rect.left + offsets[span.end.offset] }
            }
            guard right > left else { continue }
            result[piece.line, default: []].append(Rect(left: left, top: rect.top, right: right, bottom: rect.bottom))
        }
        return result
    }
}

// MARK: - TextPlace

struct TextPlace: Comparable {
    let piece: Int
    let offset: Int

    static func < (lhs: TextPlace, rhs: TextPlace) -> Bool {
        return (lhs.piece, lhs.offset) < (rhs.piece, rhs.offset)
    }
}

// MARK: - TextSpan

struct TextSpan: Equatable {
    let start: TextPlace
    let end: TextPlace
}

// MARK: - TextPiece

private struct TextPiece {
    let line: LayoutID
    let node: NodeID
    let text: TextPieceText
    let bounds: TextPieceBounds
}

private struct TextPieceText {
    let string: String
    let font: BrowserFont
    let start: Int
}

private struct TextPieceBounds {
    let layout: Rect
    let shown: Rect
}

// MARK: - TextPieceCollector

@MainActor
private struct TextPieceCollector {
    let tree: LayoutTree
    var pieces: [TextPiece] = []
    var piecesByNode: [NodeID: [Int]] = [:]
    var nextStart: [NodeID: Int] = [:]

    mutating func visit(_ id: LayoutID, shift: Point) {
        if tree.isEmbed(id) { return }
        var shift: Point = shift
        if !tree.isLine(id), let t: CGPoint = tree.inputs.style(tree.domID(of: id)).visual.effects.translation {
            shift = Point(x: shift.x + t.x, y: shift.y + t.y)
        }
        if tree.isText(id), let line: LayoutID = tree.parentID(of: id) {
            let node: NodeID = tree.domID(of: id)
            let rect: Rect = tree.textSelfRect(id)
            append(TextPiece(
                line: line,
                node: node,
                text: TextPieceText(string: tree.textString(id), font: tree.font(id), start: nextStart[node, default: 0]),
                bounds: TextPieceBounds(layout: rect, shown: rect.translated(dx: shift.x, dy: shift.y))
            ))
            return
        }
        if tree.isLine(id), let boxes: [InlineBox] = tree.currentInlineBoxes(id) {
            for box in boxes {
                addBox(box, on: id, shift: shift)
            }
            return
        }
        let scroll: CGFloat = tree.isBlock(id) ? tree.blockScrollOffset(id) : 0
        let childShift: Point = Point(x: shift.x, y: shift.y - scroll)
        for child in tree.childrenIDs(of: id) {
            visit(child, shift: childShift)
        }
    }

    private mutating func addBox(_ box: InlineBox, on line: LayoutID, shift: Point) {
        let top: CGFloat = tree.y(line) + box.geometry.y
        let rect: Rect = Rect(
            left: box.geometry.x,
            top: top,
            right: box.geometry.x + box.geometry.width,
            bottom: top + box.text.font.linespace
        )
        append(TextPiece(
            line: line,
            node: box.dom,
            text: TextPieceText(string: tree.inlineText(box), font: box.text.font, start: nextStart[box.dom, default: 0]),
            bounds: TextPieceBounds(layout: rect, shown: rect.translated(dx: shift.x, dy: shift.y))
        ))
    }

    private mutating func append(_ piece: TextPiece) {
        guard !piece.text.string.isEmpty else { return }
        nextStart[piece.node] = piece.text.start + piece.text.string.count + 1
        piecesByNode[piece.node, default: []].append(pieces.count)
        pieces.append(piece)
    }
}

// MARK: - CharacterKind

private enum CharacterKind {
    case space
    case word
    case symbol

    init(_ character: Character) {
        if character.isWhitespace {
            self = .space
        } else if character.isLetter || character.isNumber || character == "_" {
            self = .word
        } else {
            self = .symbol
        }
    }
}
