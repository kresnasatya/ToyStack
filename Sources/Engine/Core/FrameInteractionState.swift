import Foundation

struct FrameInteractionState {
    var focus: NodeID?
    var hovered: [NodeID]
    var scrollFocus: NodeID?
    var needsFocusScroll: Bool

    init() {
        self.focus = nil
        self.hovered = []
        self.scrollFocus = nil
        self.needsFocusScroll = false
    }
}
