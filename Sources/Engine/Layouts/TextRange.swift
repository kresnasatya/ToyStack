// MARK: - TextRange

/// The text one press covers: a single gap, a word, or a paragraph. `start`
/// comes first in reading order; for a gap both ends are the same.
struct TextRange: Equatable {
    let start: TextPosition
    let end: TextPosition
}
