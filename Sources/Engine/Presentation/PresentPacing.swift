import Foundation

public enum PresentPacing {
    public static let interval: TimeInterval = 1.0 / 60.0

    public static func delay(lastStart: TimeInterval, now: TimeInterval) -> TimeInterval {
        return max(0, lastStart + interval - now)
    }
}
