@MainActor
enum InlineItem {
    case text(InlineTextItem)
    case embed(ElementRef)
    case lineBreak
}
