public enum LayerPlacementKey: Hashable, Sendable {
    case tile(zIndex: Int, col: Int, row: Int)
    case composited(zIndex: Int)
}
