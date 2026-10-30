import CoreGraphics

@MainActor
protocol InlineLayoutItem: LayoutObject {
    var font: BrowserFont { get }
}
