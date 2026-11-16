enum InlineItem {
    case text(InlineTextItem)
    case embed(LayoutElementView)
    case boxEdge(InlineBoxEdge)
    case lineBreak
}
