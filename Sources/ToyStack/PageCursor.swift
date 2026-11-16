import Engine
import SwiftUI

// The page view leaves hit testing to SwiftUI so its tap gesture gets clicks,
// which also makes the hosting view the one AppKit asks for the cursor on every
// mouse move. NSCursor.set() from the page is overwritten at once; only a
// SwiftUI pointer style survives.
struct PageCursor: ViewModifier {
    let kind: CursorKind

    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.pointerStyle(pointerStyle)
        } else {
            content
        }
    }

    @available(macOS 15.0, *)
    private var pointerStyle: PointerStyle? {
        switch kind {
        case .auto, .default: return nil
        case .pointer: return .link
        }
    }
}
