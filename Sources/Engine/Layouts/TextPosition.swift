// MARK: - TextPosition

/// A gap between two characters of a text node. `offset` counts the node's
/// text as laid out, where a run of collapsed white space is one character.
/// Wrapping never changes it, so a selection keeps the same words when the
/// page is laid out again at another width.
struct TextPosition: Equatable {
    let node: NodeID
    let offset: Int
}
