import Foundation

/// Identity of a DOM node inside one `DOMTree`.
/// Public so it can be carried by the renderer seam; its raw value stays internal.
public struct NodeID: Hashable, Sendable {
    let raw: UInt32
}
