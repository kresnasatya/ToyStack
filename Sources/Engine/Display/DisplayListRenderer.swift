import CoreGraphics

public func renderDisplayList(_ ops: [DisplayOp], renderer: any Renderer) {
    var index: Int = 0
    renderDisplayRange(ops, index: &index, end: ops.count, renderer: renderer)
}

private func renderDisplayRange(
    _ ops: [DisplayOp],
    index: inout Int,
    end: Int,
    renderer: any Renderer
) {
    while index < end {
        switch ops[index] {
        case .beginEffect(let scope):
            let close: Int = matchingEnd(ops, from: index)
            applyEffect(scope.kind, renderer: renderer) { inner in
                var innerIndex: Int = index + 1
                renderDisplayRange(ops, index: &innerIndex, end: close, renderer: inner)
            }
            index = close + 1
        case .endEffect:
            return
        default:
            ops[index].execute(renderer: renderer)
            index += 1
        }
    }
}

private func matchingEnd(_ ops: [DisplayOp], from start: Int) -> Int {
    var depth: Int = 0
    var index: Int = start
    while index < ops.count {
        switch ops[index] {
        case .beginEffect:
            depth += 1
        case .endEffect:
            depth -= 1
            if depth == 0 { return index }
        default:
            break
        }
        index += 1
    }
    preconditionFailure("unbalanced display effect scope")
}
