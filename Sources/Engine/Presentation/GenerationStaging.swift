import Foundation

/// Which layer generation the presenter is uploading, and which frame waits
/// behind it.
///
/// A new generation is uploaded in budgeted chunks behind the layers on
/// screen and only replaces them once complete. While a resize is moving, a
/// started upload is always finished: a newer layout arrives every few
/// presents, so restarting on each one would leave the stale layers on screen
/// for the whole drag. Only the newest frame waits; an older waiting frame
/// would only delay it. Once the resize settles, `skipStale` drops an upload
/// laid out for a width the window no longer has.
public struct GenerationStaging<Frame> {
    public struct Entry {
        public let generation: UInt64
        public let frame: Frame
    }

    public enum Offer: Equatable {
        case started
        case refreshed
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

    public mutating func finish() -> Frame? {
        current = waiting
        waiting = nil
        return current?.frame
    }

    /// Drops the current upload for the waiting frame once the resize has
    /// settled at the waiting frame's width. The current generation was laid
    /// out for a width the window no longer has, so finishing it would only
    /// delay the final image. The started upload is kept while the width
    /// still moves, when the current frame fits the view (new content at an
    /// unchanged width), or when this present finishes it
    /// (`currentFinishesNow`): dropping an upload one present from done saves
    /// no more than that present, and keeps an older image on screen while
    /// the waiting frame uploads from scratch. `currentFinishesNow` is only
    /// asked when every other condition holds. Returns true when it skipped.
    public mutating func skipStale(
        settled: Bool,
        currentFinishesNow: (Frame) -> Bool,
        fits: (Frame) -> Bool
    ) -> Bool {
        guard settled, let current, let waiting,
            !fits(current.frame), fits(waiting.frame),
            !currentFinishesNow(current.frame)
        else {
            return false
        }
        self.current = waiting
        self.waiting = nil
        return true
    }

    public mutating func cancel() {
        current = nil
        waiting = nil
    }
}
