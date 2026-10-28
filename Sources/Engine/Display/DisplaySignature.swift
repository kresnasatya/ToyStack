import Foundation

// A stable textual signature of a display list.
//
// Two signatures are equal when the same commands cover the same geometry with
// the same painted content. Used by the headless runner to detect a settled
// frame and by the differential layout oracle to compare an incremental render
// with a full rebuild.
public func displaySignature(_ list: [any DisplayItem]) -> String {
    var parts: [String] = []
    parts.reserveCapacity(list.count)
    appendDisplaySignature(list, into: &parts)
    return parts.joined(separator: "|")
}

private func appendDisplaySignature(
    _ list: [any DisplayItem],
    into parts: inout [String]
) {
    for item in list {
        if let command = item as? any DisplayCommand {
            parts.append("\(type(of: command)) \(command.rect) \(command.contentHash)")
        } else if let effect = item as? BrowserVisualEffect {
            parts.append("\(type(of: effect)) \(effect.rect)")
            appendDisplaySignature(effect.children, into: &parts)
        } else {
            parts.append("\(type(of: item))")
        }
    }
}
