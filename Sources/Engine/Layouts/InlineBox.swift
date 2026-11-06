import CoreGraphics

/// A laid-out text fragment inside a line. It is a value, not a tree node.
import Foundation

struct InlineBox: Equatable {
    let dom: NodeID
    let fragment: TextFragment?
    let geometry: InlineBoxGeometry
    let text: InlineBoxText
}

struct InlineBoxGeometry {
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
}

struct InlineBoxText {
    let payload: TextPayload
    let font: BrowserFont
    let ascent: CGFloat
    let descent: CGFloat
}


extension InlineBox {
    static func == (lhs: InlineBox, rhs: InlineBox) -> Bool {
        return lhs.dom == rhs.dom
            && lhs.fragment == rhs.fragment
            && lhs.geometry.x == rhs.geometry.x
            && lhs.geometry.y == rhs.geometry.y
            && lhs.geometry.width == rhs.geometry.width
            && lhs.text.payload.word == rhs.text.payload.word
            && lhs.text.payload.display == rhs.text.payload.display
            && lhs.text.ascent == rhs.text.ascent
            && lhs.text.descent == rhs.text.descent
            && lhs.text.font.size == rhs.text.font.size
    }
}
