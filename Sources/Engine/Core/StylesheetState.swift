import Foundation

/// Parsed style sheets and the state of the current style pass.
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
