import Foundation

struct StylesheetState {
    var rules: [RuleIndex.Rule]
    var keyframes: [String: [Keyframe]]
    var index: RuleIndexState
    var pending: StylePendingState

    init() {
        self.rules = []
        self.keyframes = [:]
        self.index = RuleIndexState()
        self.pending = StylePendingState()
    }
}
