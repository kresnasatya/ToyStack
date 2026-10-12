import CoreGraphics

// MARK: - CanvasRenderingContext2D
final class CanvasRenderingContext2D {
    let width: CGFloat
    let height: CGFloat

    private var cg: CGContext
    private var renderer: CGRenderer
    private(set) var scale: CGFloat
    private var commands: [CanvasCommand] = []
    private(set) var revision: UInt64 = 0
    private var path: CGMutablePath = CGMutablePath()

    private var state: CanvasState = CanvasState(
        style: CanvasStyle(
            fillStyle: "black",
            strokeStyle: "black",
            font: "16px serif",
            lineWidth: 1
        ),
        transform: .identity
    )
    private var stateStack: [CanvasState] = []

    init?(width: CGFloat, height: CGFloat, scale: CGFloat) {
        guard let cg: CGContext = Self.makeContext(width: width, height: height, scale: scale) else { return nil }

        self.width = width
        self.height = height
        self.scale = scale
        self.cg = cg
        self.renderer = CGRenderer(cg: cg, canvasSize: CGSize(width: width, height: height), scale: scale)
    }

    private static func makeContext(width: CGFloat, height: CGFloat, scale: CGFloat) -> CGContext? {
        let pxWidth: Int = Int((width * scale).rounded())
        let pxHeight: Int = Int((height * scale).rounded())
        guard pxWidth > 0, pxHeight > 0,
            let cg: CGContext = CGContext(
                data: nil,
                width: pxWidth,
                height: pxHeight,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else { return nil }

        cg.scaleBy(x: scale, y: scale)
        cg.translateBy(x: 0, y: height)
        cg.scaleBy(x: 1, y: -1)
        return cg
    }

    func setScale(_ newScale: CGFloat) {
        guard abs(newScale - scale) > 0.001 else { return }
        guard let next: CGContext = Self.makeContext(width: width, height: height, scale: newScale) else { return }
        scale = newScale
        cg = next
        renderer = CGRenderer(cg: next, canvasSize: CGSize(width: width, height: height), scale: newScale)
        revision += 1
        for command in commands {
            command.draw(cg: cg, renderer: renderer)
        }
    }

    func image() -> CGImage? {
        cg.makeImage()
    }

    func fillRect(_ rect: Rect) {
        revision += 1
        if state.transform.isIdentity, coversWholeCanvas(rect) && state.style.fillStyle != "transparent" {
            commands.removeAll()
        }
        let command: CanvasCommand = CanvasCommand(
            transform: state.transform,
            op: .fillRect(rect, state.style.fillStyle)
        )
        commands.append(command)
        command.draw(cg: cg, renderer: renderer)
    }

    func clearRect(_ rect: Rect) {
        revision += 1
        if state.transform.isIdentity, coversWholeCanvas(rect) {
            commands.removeAll()
        }
        let command: CanvasCommand = CanvasCommand(
            transform: state.transform,
            op: .clearRect(rect)
        )
        commands.append(command)
        command.draw(cg: cg, renderer: renderer)
    }

    func strokeRect(_ rect: Rect) {
        revision += 1
        let command: CanvasCommand = CanvasCommand(
            transform: state.transform,
            op: .strokeRect(rect, state.style.strokeStyle, state.style.lineWidth)
        )
        commands.append(command)
        command.draw(cg: cg, renderer: renderer)
    }

    func fillText(_ text: String, at point: Point) {
        revision += 1
        let command: CanvasCommand = CanvasCommand(
            transform: state.transform,
            op: .fillText(text, point, state.style.fillStyle, canvasFont())
        )
        commands.append(command)
        command.draw(cg: cg, renderer: renderer)
    }

    func beginPath() {
        path = CGMutablePath()
    }

    func moveTo(_ point: Point) {
        path.move(to: point.cgPoint)
    }

    func lineTo(_ point: Point) {
        path.addLine(to: point.cgPoint)
    }

    func stroke() {
        revision += 1
        let command: CanvasCommand = CanvasCommand(
            transform: state.transform,
            op: .strokePath(path.copy() ?? path, state.style.strokeStyle, state.style.lineWidth)
        )
        commands.append(command)
        command.draw(cg: cg, renderer: renderer)
    }

    func fill() {
        revision += 1
        let command: CanvasCommand = CanvasCommand(
            transform: state.transform,
            op: .fillPath(path.copy() ?? path, state.style.fillStyle)
        )
        commands.append(command)
        command.draw(cg: cg, renderer: renderer)
    }

    func save() {
        stateStack.append(state)
    }

    func restore() {
        guard let previous: CanvasState = stateStack.popLast() else { return }
        state = previous
    }

    func translate(x: CGFloat, y: CGFloat) {
        state.transform = state.transform.translated(x: x, y: y)
    }

    func scale(x: CGFloat, y: CGFloat) {
        state.transform = state.transform.scaled(x: x, y: y)
    }

    func rotate(radians: CGFloat) {
        state.transform = state.transform.rotated(by: radians)
    }

    func transform(_ matrix: CGAffineTransform) {
        state.transform = CanvasTransform(matrix: matrix).concatenating(state.transform)
    }

    func setTransform(_ matrix: CGAffineTransform) {
        state.transform = CanvasTransform(matrix: matrix)
    }

    func resetTransform() {
        state.transform = .identity
    }

    func style(_ key: String) -> String {
        switch key {
            case "fillStyle": return state.style.fillStyle
            case "strokeStyle": return state.style.strokeStyle
            case "font": return state.style.font
            case "lineWidth": return String(Double(state.style.lineWidth))
            default: return ""
        }
    }

    func setStyle(_ key: String, _ value: String) {
        switch key {
            case "fillStyle":
                if BrowserColor.parse(value) != nil {
                    state.style.fillStyle = value
                }
            case "strokeStyle":
                if BrowserColor.parse(value) != nil {
                    state.style.strokeStyle = value
                }
            case "font": state.style.font = value
            case "lineWidth": state.style.lineWidth = CGFloat(Double(value) ?? Double(state.style.lineWidth))
            default: break

        }
    }

    private func coversWholeCanvas(_ rect: Rect) -> Bool {
        let epsilon: CGFloat = 0.5
        return rect.left <= epsilon && rect.top <= epsilon
            && rect.right >= width - epsilon && rect.bottom >= height - epsilon
    }

    private func canvasFont() -> BrowserFont {
        let size: Double = Double(state.style.font.prefix(while: { $0.isNumber })) ?? 10
        return getFont(size: Int(size * 0.75), weight: "normal", style: "roman", family: "serif")
    }
}
