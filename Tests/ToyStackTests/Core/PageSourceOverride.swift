import Foundation

@testable import Engine

/// `BrowserTab.pageSource` is one global shared by every suite, and suites run
/// in parallel, so tests that replace it take turns instead of overwriting
/// each other's fake pages.
@MainActor
enum PageSourceOverride {
    typealias Source = @Sendable (_ scheme: String, _ path: String) async -> (
        status: Int, headers: [String: String], content: String
    )?

    private static var isTaken: Bool = false

    static func with<T>(_ source: @escaping Source, _ body: () async throws -> T) async rethrows -> T {
        while isTaken {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        isTaken = true
        let original: Source? = BrowserTab.pageSource
        BrowserTab.pageSource = source
        defer {
            BrowserTab.pageSource = original
            isTaken = false
        }
        return try await body()
    }
}
