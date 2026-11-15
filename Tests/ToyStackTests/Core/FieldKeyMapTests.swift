import Testing

@testable import Engine

@Suite
struct FieldKeyMapTests {
    private static let reader: FieldKey = .layout(LayoutID(raw: 9), .y)
    private static let otherReader: FieldKey = .layout(LayoutID(raw: 9), .height)

    @Test func everyFieldOfTwoNeighbouringNodesKeepsItsOwnReaders() {
        var map: FieldKeyMap = FieldKeyMap()
        var keys: [FieldKey] = []
        for raw in [4, 5] {
            for field in LayoutField.allCases {
                let key: FieldKey = .layout(LayoutID(raw: raw), field)
                map[key, default: []].insert(.layout(LayoutID(raw: raw + 100), field))
                keys.append(key)
            }
        }

        for case .layout(let id, let field) in keys {
            let reader: FieldKey = .layout(LayoutID(raw: id.raw + 100), field)
            #expect(map[.layout(id, field)] == [reader], "\(field) of node \(id.raw) shares a slot")
        }
        #expect(Set(map.pairs.map({ $0.key })) == Set(keys))
    }

    @Test func pairsListEveryKeyThatStillHasReaders() {
        var map: FieldKeyMap = FieldKeyMap()
        let width: FieldKey = .layout(LayoutID(raw: 3), .width)
        let removed: FieldKey = .layout(LayoutID(raw: 7), .descent)
        let display: FieldKey = .style(NodeID(raw: 2), .display)
        map[width, default: []].insert(Self.reader)
        map[removed, default: []].insert(Self.reader)
        map[display, default: []].insert(Self.otherReader)

        map[removed]?.remove(Self.reader)

        let keys: Set<FieldKey> = Set(map.pairs.map({ $0.key }))
        #expect(keys == [width, display])
    }

    @Test func readingANodeThatWasNeverWrittenFindsNothing() {
        let map: FieldKeyMap = FieldKeyMap()

        #expect(map[.layout(LayoutID(raw: 1_000_000), .y)] == nil)
        #expect(map.pairs.isEmpty)
    }

    @Test func removeAllForgetsLayoutAndStyleKeys() {
        var map: FieldKeyMap = FieldKeyMap()
        map[.layout(LayoutID(raw: 1), .x), default: []].insert(Self.reader)
        map[.style(NodeID(raw: 1), .position), default: []].insert(Self.reader)

        map.removeAll(keepingCapacity: true)

        #expect(map.pairs.isEmpty)
    }
}
