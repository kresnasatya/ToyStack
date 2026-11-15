import CoreGraphics

public struct ContentTransform {
    public let pageZoom: CGFloat
    public let scroll: CGFloat

    public init(pageZoom: CGFloat, scroll: CGFloat) {
        self.pageZoom = pageZoom
        self.scroll = scroll
    }

    public func apply(to renderer: any Renderer) {
        renderer.translateBy(x: 0, y: -scroll * pageZoom)
        renderer.scaleBy(x: pageZoom, y: pageZoom)
    }
}
