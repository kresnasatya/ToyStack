import Engine
import SwiftUI

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
        case .text: return .horizontalText
        }
    }
}
