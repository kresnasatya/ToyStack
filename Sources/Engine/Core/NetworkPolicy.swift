import Foundation

struct NetworkPolicy {
    var allowedOrigins: [String]?
    var referrerPolicy: String

    init() {
        self.allowedOrigins = nil
        self.referrerPolicy = ""
    }
}
