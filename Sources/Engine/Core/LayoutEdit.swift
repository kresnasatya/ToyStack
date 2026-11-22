enum LayoutEdit {
    case childrenChanged(NodeID)
    case imageChanged(NodeID)
    case layoutInputChanged(NodeID, affectsSiblings: Bool)
}
