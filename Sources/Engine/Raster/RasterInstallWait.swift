import Foundation

final class RasterInstallWait: @unchecked Sendable {
    private let lock: NSLock = NSLock()
    private var installEnd: UInt64?

    func noteInstallEnd(_ timestamp: UInt64) {
        lock.lock()
        installEnd = timestamp
        lock.unlock()
    }

    func takeWait(endedAt timestamp: UInt64) -> (start: UInt64, end: UInt64)? {
        lock.lock()
        defer { lock.unlock() }
        guard let start: UInt64 = installEnd else { return nil }
        installEnd = nil
        return (start, timestamp)
    }
}
