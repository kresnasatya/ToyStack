import Foundation

/// They are one display frame apart, counted from the start of the previous
/// present. Counting from its end would add the commit (6-14 ms for a
/// 30-tile chunk) to every gap.
public enum PresentPacing {
    public static let interval: TimeInterval = 1.0 / 60.0

    public static func delay(lastStart: TimeInterval, now: TimeInterval) -> TimeInterval {
        return max(0, lastStart + interval - now)
    }
}
