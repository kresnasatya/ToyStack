enum InlineItem {
    case text(InlineTextItem)
    case embed(LayoutElementView)
    /// CSS 2.1 §9.5: a float inside inline content is placed while its lines
    /// are broken, at the top of the line it appears on.
    case float(LayoutElementView)
    case boxEdge(InlineBoxEdge)
    case lineBreak
}
