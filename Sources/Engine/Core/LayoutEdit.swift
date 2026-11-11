/// A change that DOM-side code marks on the installed layout tree, kept by
/// DOM node id. While a background pass lays out a copy of that tree, the
/// installed tree is replaced when the pass finishes, so every edit made in
/// between is applied again to the pass's tree (`LayoutBox.takeRecordedEdits`).
enum LayoutEdit {
    case childrenChanged(NodeID)
    case imageChanged(NodeID)
    case layoutInputChanged(NodeID, affectsSiblings: Bool)
}
