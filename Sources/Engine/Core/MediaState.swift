import Foundation

/// Media queries mentioned by the current rules and their last verdicts.
struct MediaState {
    var queries: Set<String>
    var matches: [String: Bool]

    init() {
        self.queries = []
        self.matches = [:]
    }
}
