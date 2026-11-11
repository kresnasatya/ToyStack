import CoreGraphics
import Foundation

struct ImageResourceState {
    var requestedBackgrounds: Set<String>
    var backgroundCache: [String: CGImage]
    var lazy: [NodeID]

    init() {
        self.requestedBackgrounds = []
        self.backgroundCache = [:]
        self.lazy = []
    }
}
