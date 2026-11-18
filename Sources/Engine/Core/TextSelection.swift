// MARK: - TextSelection

/// What the reader has selected in one frame. `anchor` is the gap, word, or
/// paragraph the press landed on and never changes during a drag; `focus` is
/// the same kind of unit under the pointer now. The selection runs from the
/// first end of either to the last, so dragging back past the press keeps the
/// pressed word selected.
struct TextSelection: Equatable {
    let anchor: TextRange
    var focus: TextRange
    let unit: TextUnit

    var isCollapsed: Bool {
        return anchor == focus && anchor.start == anchor.end
    }
}
