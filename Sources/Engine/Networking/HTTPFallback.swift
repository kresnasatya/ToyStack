import Foundation

enum HTTPFallback {
    private static let secureConnectionFailures: Set<URLError.Code> = [
        .secureConnectionFailed,
        .serverCertificateUntrusted,
        .serverCertificateHasBadDate,
        .serverCertificateNotYetValid,
        .serverCertificateHasUnknownRoot,
        .cannotConnectToHost,
        .networkConnectionLost,
        .timedOut,
    ]

    static func applies(after error: any Error) -> Bool {
        guard let urlError: URLError = error as? URLError else { return false }
        return secureConnectionFailures.contains(urlError.code)
    }

    static func firstAttempt(_ url: WebURL, fallback: WebURL?) async -> WebURL {
        guard let fallback: WebURL, await HTTPOnlyHosts.shared.contains(fallback.host),
            await !HSTSStore.shared.isKnown(fallback.host)
        else {
            return url
        }
        return fallback
    }

    static func retry(after error: any Error, fallback: WebURL?) async -> WebURL? {
        guard let fallback: WebURL, applies(after: error), await !HSTSStore.shared.isKnown(fallback.host) else {
            return nil
        }
        return fallback
    }

    static func noteLoaded(_ fallback: WebURL) async {
        await HTTPOnlyHosts.shared.remember(fallback.host)
    }
}
