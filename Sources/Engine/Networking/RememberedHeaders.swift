import Foundation

/// The headers a browser keeps for later requests to the host that sent
/// them: the HSTS rule and the cookie. Every response counts, including each
/// redirect along the way.
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
