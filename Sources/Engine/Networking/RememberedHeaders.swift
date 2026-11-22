import Foundation

enum RememberedHeaders {
    static func record(from response: HTTPURLResponse) async {
        guard let address: URL = response.url else { return }
        let sender: WebURL = WebURL(address.absoluteString)
        if let rule: String = response.value(forHTTPHeaderField: "Strict-Transport-Security") {
            await HSTSStore.shared.note(rule, from: sender)
        }
        if let setCookie: String = response.value(forHTTPHeaderField: "Set-Cookie") {
            await CookieJar.shared.receive(setCookie, from: sender)
        }
    }
}
