// MARK: - TextSelection

struct TextSelection: Equatable {
    let anchor: TextRange
    var focus: TextRange
    let unit: TextUnit

    var isCollapsed: Bool {
        return anchor == focus && anchor.start == anchor.end
    }
}
