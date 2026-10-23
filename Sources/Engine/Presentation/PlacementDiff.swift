public struct PlacementDiff {
    public let kept: Int
    let added: [LayerPlacementKey]
    public let removed: [LayerPlacementKey]

    public init(previous: Set<LayerPlacementKey>, current: [LayerPlacementKey]) {
        var seen: Set<LayerPlacementKey> = []
        seen.reserveCapacity(current.count)
        var added: [LayerPlacementKey] = []
        for key in current where seen.insert(key).inserted {
            if !previous.contains(key) { added.append(key) }
        }
        let removed: [LayerPlacementKey] = previous.filter({ !seen.contains($0) })
        self.kept = seen.count - added.count
        self.added = added
        self.removed = removed
    }
}
