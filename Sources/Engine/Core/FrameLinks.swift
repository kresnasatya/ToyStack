import Foundation

struct FrameLinks {
    weak var tab: BrowserTab?
    let id: FrameID
    let parent: FrameID?
    let element: NodeID?
}
