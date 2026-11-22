import Foundation
import Testing

@testable import Engine

@Suite struct HTTPFallbackTests {
    @Test(arguments: [
        URLError.Code.secureConnectionFailed,
        .serverCertificateUntrusted,
        .serverCertificateHasBadDate,
        .serverCertificateNotYetValid,
        .serverCertificateHasUnknownRoot,
        .cannotConnectToHost,
        .networkConnectionLost,
        .timedOut,
    ])
    func httpsThatCouldNotConnectSecurelyFallsBack(_ code: URLError.Code) {
        #expect(HTTPFallback.applies(after: URLError(code)))
    }

    @Test(arguments: [
        URLError.Code.cannotFindHost,
        .dnsLookupFailed,
        .notConnectedToInternet,
        .cancelled,
        .badURL,
    ])
    func failureThatHTTPWouldShareDoesNotFallBack(_ code: URLError.Code) {
        #expect(HTTPFallback.applies(after: URLError(code)) == false)
    }

    @Test func failureThatIsNotAboutTheNetworkDoesNotFallBack() {
        #expect(HTTPFallback.applies(after: CocoaError(.fileReadNoSuchFile)) == false)
    }

    // MARK: - HTTPS-only hosts

    @Test func httpsOnlyHostIsNeitherRetriedOverHTTPNorRememberedAsHTTPOnly() async {
        let host: String = "hsts-\(UUID().uuidString.lowercased()).example"
        await HSTSStore.shared.note("max-age=600", from: WebURL("https://\(host)/"))

        let retry: WebURL? = await HTTPFallback.retry(
            after: URLError(.secureConnectionFailed),
            fallback: WebURL("http://\(host)/")
        )

        #expect(retry == nil)
        #expect(await !HTTPOnlyHosts.shared.contains(host))
        await HSTSStore.shared.note("max-age=0", from: WebURL("https://\(host)/"))
    }

    @Test func httpsOnlyHostStartsOverHTTPSEvenIfItOnceFellBack() async {
        let host: String = "hsts-\(UUID().uuidString.lowercased()).example"
        await HTTPOnlyHosts.shared.remember(host)
        await HSTSStore.shared.note("max-age=600", from: WebURL("https://\(host)/"))
        let secure: WebURL = WebURL("https://\(host)/")

        let first: WebURL = await HTTPFallback.firstAttempt(secure, fallback: WebURL("http://\(host)/"))

        #expect(first === secure)
        await HSTSStore.shared.note("max-age=0", from: WebURL("https://\(host)/"))
        await HTTPOnlyHosts.shared.forget(host)
    }

    @Test func ordinaryHostIsRetriedOverHTTPWithoutBeingRememberedYet() async {
        let host: String = "plain-\(UUID().uuidString.lowercased()).example"
        let fallback: WebURL = WebURL("http://\(host)/")

        let retry: WebURL? = await HTTPFallback.retry(after: URLError(.secureConnectionFailed), fallback: fallback)

        #expect(retry === fallback)
        #expect(await !HTTPOnlyHosts.shared.contains(host))
    }
}
