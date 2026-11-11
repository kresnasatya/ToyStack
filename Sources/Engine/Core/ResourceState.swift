import Foundation

struct ResourceState {
    var network: NetworkPolicy
    var loadedScripts: Set<String>
    var images: ImageResourceState

    init() {
        self.network = NetworkPolicy()
        self.loadedScripts = []
        self.images = ImageResourceState()
    }
}
