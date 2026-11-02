import Foundation

/// Identity of a DOM node inside one `DOMTree`.
struct NodeID: Hashable, Sendable {
    let raw: UInt32
}
