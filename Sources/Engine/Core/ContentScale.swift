import CoreGraphics

public struct ContentScale: Equatable {
    public let display: CGFloat
    public let page: CGFloat

    public var effective: CGFloat { display * page }

    public init(display: CGFloat, page: CGFloat = 1.0) {
        self.display = display
        self.page = page
    }
}
