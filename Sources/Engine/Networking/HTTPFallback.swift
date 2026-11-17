import Foundation

/// When a typed address had its https guessed, these decide whether the page
/// is tried, or retried, over http.
enum HTTPFallback {
    // Only failures to set up the secure connection. A missing host or no
    // internet would fail the same way over http, and an HTTP error status
    // means https works and the server answered.
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

    /// The http address when this host already failed over https recently.
    static func firstAttempt(_ url: WebURL, fallback: WebURL?) async -> WebURL {
        guard let fallback: WebURL, await HTTPOnlyHosts.shared.contains(fallback.host),
            await !HSTSStore.shared.isKnown(fallback.host)
        else {
            return url
        }
        return fallback
    }

    /// An https-only host never falls back. Its retry would be upgraded back
    /// to https anyway, so falling back would only repeat the failed (maybe
    /// timed-out) attempt.
    static func retry(after error: any Error, fallback: WebURL?) async -> WebURL? {
        guard let fallback: WebURL, applies(after: error), await !HSTSStore.shared.isKnown(fallback.host) else {
            return nil
        }
        return fallback
    }

    /// Only a page that really loaded over http proves the host has no https.
    /// A dropped connection or timeout fails http as well, and must not pin
    /// a working https site to plain http.
    static func noteLoaded(_ fallback: WebURL) async {
        await HTTPOnlyHosts.shared.remember(fallback.host)
    }
}
