import Foundation

/// Revision key for reusing the previous layout inputs.
struct LayoutInputsKey {
    let dom: ObjectIdentifier
    let domRevision: UInt64
    let imageRevision: UInt64
    let styleRevision: UInt64
}
