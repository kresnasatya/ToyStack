import CoreGraphics

// MARK: - CanvasCommand
struct CanvasCommand {
    let transform: CanvasTransform
    let op: CanvasOp

    func draw(cg: CGContext, renderer: CGRenderer) {
        cg.saveGState()
        cg.concatenate(transform.matrix)
        op.draw(cg: cg, renderer: renderer)
        cg.restoreGState()
    }
}
