import Foundation

struct MediaState {
    var queries: Set<String>
    var matches: [String: Bool]

    init() {
        self.queries = []
        self.matches = [:]
    }
}
