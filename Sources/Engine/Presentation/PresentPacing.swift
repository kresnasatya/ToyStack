import Foundation

/// When the presenter runs its next follow-up present.
///
/// Follow-up presents finish a staged layer generation or deferred tile
/// binds without waiting for the engine to send another frame. They are one
/// display frame apart, counted from the start of the previous present.
/// Counting from its end would add the commit (6-14 ms for a 30-tile chunk)
/// to every gap.
public enum PresentPacing {
    /// One display frame.
    public static let interval: TimeInterval = 1.0 / 60.0

    /// Seconds to wait at `now` before the next follow-up present, when the
    /// previous present started at `lastStart`. A present that took longer
    /// than a frame is followed at once.
    public static func delay(lastStart: TimeInterval, now: TimeInterval) -> TimeInterval {
        return max(0, lastStart + interval - now)
    }
}
