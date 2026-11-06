import Foundation

/// One hit-test result: the layout node that owns the hit area plus the DOM
/// node whose semantics (link, text, iframe) the hit resolves to.
struct LayoutHit {
    let layout: LayoutID
    let dom: NodeID
}
