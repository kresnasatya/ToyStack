import os

/// Lets the main thread tell a background layout pass that its result will be
/// thrown away, so the pass can stop instead of finishing useless work.
final class LayoutCancellation: Sendable {
    private let flag: OSAllocatedUnfairLock<Bool> = OSAllocatedUnfairLock(initialState: false)

    var isCancelled: Bool {
        return flag.withLock({ $0 })
    }

    func cancel() {
        flag.withLock({ $0 = true })
    }
}
