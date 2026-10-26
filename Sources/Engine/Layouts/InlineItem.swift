@MainActor
enum InlineItem {
    case text(InlineTextItem)
    case embed(Element)
    case lineBreak
}
