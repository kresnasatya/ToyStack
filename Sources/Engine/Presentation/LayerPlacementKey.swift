public enum LayerPlacementKey: Hashable {
    case tile(zIndex: Int, col: Int, row: Int)
    case composited(zIndex: Int)
}
