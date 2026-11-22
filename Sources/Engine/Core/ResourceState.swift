import Foundation

struct ResourceState {
    var network: NetworkPolicy
    var loadedScripts: Set<String>
    var loadedStylesheets: [String: String]
    var images: ImageResourceState

    init() {
        self.network = NetworkPolicy()
        self.loadedScripts = []
        self.loadedStylesheets = [:]
        self.images = ImageResourceState()
    }
}
