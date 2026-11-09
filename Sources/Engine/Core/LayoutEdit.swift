/// A change that DOM-side code marks on the installed layout tree, kept by
/// DOM node id. While a background pass lays out a copy of that tree, the
/// installed tree is replaced when the pass finishes, so every edit made in
/// between is applied again to the pass's tree (`LayoutBox.takeRecordedEdits`).
enum LayoutEdit {
    /// The nearest block rebuilds its children from the DOM.
    case childrenChanged(NodeID)
    /// An image's intrinsic size changed; its block rebuilds its children too.
    case imageChanged(NodeID)
    /// A layout input changed without marking a field: the nearest block
    /// rebuilds its children, and its parent block too when siblings move.
    case layoutInputChanged(NodeID, affectsSiblings: Bool)
}
