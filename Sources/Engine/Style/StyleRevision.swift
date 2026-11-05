import Foundation

/// Monotonic epoch for computed-style writes.
@MainActor
enum StyleRevision {
    private(set) static var epoch: UInt64 = 0

    static func bump() {
        epoch &+= 1
    }
}
