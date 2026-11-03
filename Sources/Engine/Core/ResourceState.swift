import Foundation

/// Loaded external resources and the policy that decides what may load.
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
