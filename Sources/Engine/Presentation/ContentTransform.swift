import CoreGraphics

public struct ContentTransform {
    public let pageZoom: CGFloat
    public let scroll: CGFloat
    public let topInset: CGFloat

    public init(pageZoom: CGFloat, scroll: CGFloat, topInset: CGFloat) {
        self.pageZoom = pageZoom
        self.scroll = scroll
        self.topInset = topInset
    }

    public func apply(to renderer: any Renderer) {
        renderer.translateBy(x: 0, y: topInset - scroll * pageZoom)
        renderer.scaleBy(x: pageZoom, y: pageZoom)
    }
}
