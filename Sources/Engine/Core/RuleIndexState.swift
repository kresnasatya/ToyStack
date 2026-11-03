import Foundation

/// The sorted rule index and the media state it was built from.
struct RuleIndexState {
    var list: RuleList
    var media: MediaState

    init() {
        self.list = RuleList()
        self.media = MediaState()
    }
}
