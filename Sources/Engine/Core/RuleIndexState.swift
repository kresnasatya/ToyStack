import Foundation

struct RuleIndexState {
    var list: RuleList
    var media: MediaState

    init() {
        self.list = RuleList()
        self.media = MediaState()
    }
}
