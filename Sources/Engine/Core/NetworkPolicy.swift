import Foundation

/// Origins and referrer policy derived from response headers.
struct NetworkPolicy {
    var allowedOrigins: [String]?
    var referrerPolicy: String

    init() {
        self.allowedOrigins = nil
        self.referrerPolicy = ""
    }
}
