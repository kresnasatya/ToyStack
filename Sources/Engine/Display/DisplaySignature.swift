import Foundation

// A stable textual signature of a display list.
//
// Two signatures are equal when the same commands cover the same geometry with
// the same painted content. Used by the headless runner to detect a settled
// frame and by the differential layout oracle to compare an incremental render
// with a full rebuild.
public func displaySignature(_ list: [DisplayOp]) -> String {
    var parts: [String] = []
    parts.reserveCapacity(list.count)
    appendDisplaySignature(list, into: &parts)
    return parts.joined(separator: "|")
}

private func appendDisplaySignature(
    _ list: [DisplayOp],
    into parts: inout [String]
) {
    for item in list {
        parts.append("\(item.name) \(item.rect) \(item.contentHash)")
        if case .effect(let effect) = item {
            appendDisplaySignature(effect.children, into: &parts)
        }
    }
}
