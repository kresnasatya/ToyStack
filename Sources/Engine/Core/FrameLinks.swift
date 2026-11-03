import Foundation

/// The frame's owner, identity, and place in the frame tree.
struct FrameLinks {
    weak var tab: BrowserTab?
    let id: FrameID
    let parent: FrameID?
    let element: NodeID?
}
