import CoreGraphics

// MARK: - ButtonLabelPiece

/// One unbreakable part of a button's label. `width` is what the piece itself
/// covers, and `spaceAfter` the room before the next piece on its line.
struct ButtonLabelPiece {
    enum Kind {
        case word(String, BrowserFont)
        case input
        case lineBreak
    }

    let kind: Kind
    let dom: NodeID
    let width: CGFloat
    var spaceAfter: CGFloat

    /// Where the next piece on the same line starts.
    func advance(from x: CGFloat) -> CGFloat {
        return x + width + spaceAfter
    }

    /// Adds `piece` to the end of the label. A word carries its own space, but
    /// the space after an input belongs to the text that follows, so it takes
    /// `textFont`, the font of that text.
    static func append(_ piece: ButtonLabelPiece, textFont: BrowserFont, to pieces: inout [ButtonLabelPiece]) {
        if let last: Int = pieces.indices.last, case .input = pieces[last].kind {
            pieces[last].spaceAfter = textFont.spaceWidth
        }
        pieces.append(piece)
    }

    /// CSS 2.1 §10.3.9: an inline-block with an auto width shrinks to fit, which
    /// §10.3.5 defines as min(max(preferred minimum width, available width),
    /// preferred width). CSS Text 3 §4.1.2 removes the space at the end of each
    /// line, so a line is as wide as the end of its last piece.
    static func shrinkToFit(_ pieces: [ButtonLabelPiece], available: CGFloat) -> CGFloat {
        var widths: IntrinsicWidths = .zero
        var cursorX: CGFloat = 0
        for piece in pieces {
            if case .lineBreak = piece.kind {
                cursorX = 0
                continue
            }
            widths.minContent = max(widths.minContent, piece.width)
            widths.maxContent = max(widths.maxContent, cursorX + piece.width)
            cursorX = piece.advance(from: cursorX)
        }
        return min(max(widths.minContent, available), widths.maxContent)
    }
}
