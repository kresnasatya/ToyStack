import Foundation

/// Sorted rules plus the revisions that decide when the index is rebuilt.
struct RuleList {
    var sorted: [RuleIndex.Rule]
    var index: RuleIndex
    var rulesRevision: Int
    var indexedRevision: Int

    init() {
        self.sorted = []
        self.index = RuleIndex(rules: [])
        self.rulesRevision = 0
        self.indexedRevision = -1
    }
}
