@MainActor
enum InlineItem {
    case text(TextLayout)
    case embed(Element)
    case lineBreak
}
