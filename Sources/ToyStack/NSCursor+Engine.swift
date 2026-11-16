import AppKit
import Engine

extension NSCursor {
    static func engine(_ kind: CursorKind) -> NSCursor {
        switch kind {
        case .auto, .default: return .arrow
        case .pointer: return .pointingHand
        }
    }
}
