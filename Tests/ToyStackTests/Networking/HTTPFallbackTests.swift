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
}
