import CoreGraphics

// MARK: - LayoutObject Protocol
// Every node in the layout tree implements these. The protocol lets
// paintTree(), treeToList(), and Tab.draw() work generically accross all types.
protocol LayoutObject: AnyObject {
    var node: any DOMNode { get }
    var parent: (any LayoutObject)? { get }
    var children: [any LayoutObject] { get set }
    var x: CGFloat { get set }
    var y: CGFloat { get set }
    var width: CGFloat { get set }
    var height: CGFloat { get set }
    var zoom: CGFloat { get set }

    func layout()
    func paint() -> [Any]
    func shouldPaint() -> Bool

}

// MARK: - InlineLayoutItem
// TextLayout and InputLayout both live inside a LineLayout.
// This protocol lets LineLayout read font metrics and set y positions.
protocol InlineLayoutItem: LayoutObject {
    var font: BrowserFont { get }
}
