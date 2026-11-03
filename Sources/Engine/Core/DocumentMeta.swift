import Foundation

/// Identity and load status shown by the browser UI.
struct DocumentMeta {
    var url: WebURL!
    var title: String
    var isSecure: Bool
    var loaded: Bool

    init() {
        self.url = nil
        self.title = "New Tab"
        self.isSecure = false
        self.loaded = false
    }
}
