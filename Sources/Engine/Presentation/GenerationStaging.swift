import Foundation

/// Which layer generation the presenter is uploading, and which frame waits
/// behind it.
///
/// A new generation is uploaded in budgeted chunks behind the layers on
/// screen and only replaces them once complete. A started upload is always
/// finished: during a resize a newer layout arrives every few presents, so
/// restarting on each one would leave the stale layers on screen for the
/// whole drag. Only the newest frame waits; an older waiting frame would only
/// delay it.
public struct GenerationStaging<Frame> {
    public struct Entry {
        public let generation: UInt64
        public let frame: Frame
    }

    public enum Offer: Equatable {
        /// Nothing was uploading; this generation starts now.
        case started
        /// The generation being uploaded arrived again; the upload continues
        /// with the newer frame.
        case refreshed
        /// Another generation is uploading; this frame waits for it.
        case queued
    }

    public private(set) var current: Entry?
    public private(set) var waiting: Entry?

    public init() {}

    public mutating func offer(_ frame: Frame, generation: UInt64) -> Offer {
        let entry: Entry = Entry(generation: generation, frame: frame)
        guard let current else {
            self.current = entry
            return .started
        }
        if current.generation == generation {
            self.current = entry
            return .refreshed
        }
        waiting = entry
        return .queued
    }

    /// The current generation is on screen. Starts the waiting frame, if any,
    /// and returns it.
    public mutating func finish() -> Frame? {
        current = waiting
        waiting = nil
        return current?.frame
    }

    public mutating func cancel() {
        current = nil
        waiting = nil
    }
}
