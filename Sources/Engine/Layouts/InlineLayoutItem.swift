import CoreGraphics

@MainActor
protocol InlineLayoutItem: LayoutObject {
    var fontField: ProtectedField<BrowserFont> { get }
    var ascentField: ProtectedField<CGFloat> { get }
    var descentField: ProtectedField<CGFloat> { get }
    var font: BrowserFont { get }
}
