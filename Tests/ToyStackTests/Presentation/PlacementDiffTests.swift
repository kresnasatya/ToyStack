import Testing

@testable import Engine

@Suite
struct PlacementDiffTests {

    @Test func stableSetHasNoChurn() {
        let keys: [LayerPlacementKey] = [
            .tile(zIndex: 0, col: 0, row: 0),
            .tile(zIndex: 0, col: 1, row: 0)
        ]
        let diff: PlacementDiff = PlacementDiff(previous: Set(keys), current: keys)
        #expect(diff.added.isEmpty)
        #expect(diff.removed.isEmpty)
        #expect(diff.kept == 2)
    }

    @Test func removedKeyIsReported() {
        let diff: PlacementDiff = PlacementDiff(
            previous: [.tile(zIndex: 0, col: 0, row: 0)],
            current: [.tile(zIndex: 0, col: 1, row: 0)]
        )
        #expect(diff.added.count == 1)
        #expect(diff.removed.count == 1)
    }

    @Test func keyRemovedAndReturnedIsAddedAgain() {
        let key: LayerPlacementKey = .tile(zIndex: 0, col: 0, row: 0)

        let afterRemoval: PlacementDiff = PlacementDiff(previous: [key], current: [])
        #expect(afterRemoval.removed == [key])
        #expect(afterRemoval.added.isEmpty)
        #expect(afterRemoval.kept == 0)

        let afterReturn: PlacementDiff = PlacementDiff(previous: [], current: [key])
        #expect(afterReturn.added == [key])
        #expect(afterReturn.removed.isEmpty)
        #expect(afterReturn.kept == 0)
    }
}
