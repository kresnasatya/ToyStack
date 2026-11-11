import Foundation

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
        switch item {
        case .beginEffect(let scope):
            parts.append("beginEffect \(scope.kind.description) \(scope.placement.rect)")
        case .endEffect:
            parts.append("endEffect")
        default:
            parts.append("\(item.name) \(item.rect) \(item.contentHash)")
        }
    }
}
