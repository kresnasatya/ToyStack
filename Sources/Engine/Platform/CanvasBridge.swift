import Foundation
import JavaScriptCore

// MARK: - CanvasBridge
final class CanvasBridge {
    private let jsContext: JSContext
    private let nodeForHandle: (Int) -> (any DOMNode)?
    private let requestPaint: @MainActor () -> Void
    private let displayScale: @MainActor () -> CGFloat

    init(
        jsContext: JSContext,
        nodeForHandle: @escaping (Int) -> (any DOMNode)?,
        requestPaint: @escaping @MainActor () -> Void,
        displayScale: @escaping @MainActor () -> CGFloat
    ) {
        self.jsContext = jsContext
        self.nodeForHandle = nodeForHandle
        self.requestPaint = requestPaint
        self.displayScale = displayScale
    }

    func register() {
        jsContext.setObject({
            [nodeForHandle, displayScale] (handle: Int, type: String) -> Bool in
            guard type == "2d" else { return false }
            return MainActor.assumeIsolated({
                guard let el = nodeForHandle(handle) as? Element else { return false }
                if el.canvasContext == nil {
                    let size: (width: CGFloat, height: CGFloat) = CanvasLayout.contentSize(for: el)
                    el.canvasContext = CanvasRenderingContext2D(
                        width: size.width,
                        height: size.height,
                        scale: displayScale()
                    )
                }
                return el.canvasContext != nil
            })
        } as @convention(block) (Int, String) -> Bool,
        forKeyedSubscript: "_canvasContext" as NSString)

        jsContext.setObject({
            [nodeForHandle] (handle: Int, key: String) -> String in
            MainActor.assumeIsolated({
                guard let ctx = (nodeForHandle(handle) as? Element)?.canvasContext else { return "" }
                return ctx.style(key)
            })
        } as @convention(block) (Int, String) -> String,
        forKeyedSubscript: "_canvasStyleGet" as NSString)

        jsContext.setObject({
            [nodeForHandle] (handle: Int, key: String, value: String) in
            MainActor.assumeIsolated({
                guard let ctx = (nodeForHandle(handle) as? Element)?.canvasContext else { return }
                ctx.setStyle(key, value)
            })
        } as @convention(block) (Int, String, String) -> Void,
        forKeyedSubscript: "_canvasStyleSet" as NSString)

        jsContext.setObject({
            [nodeForHandle, requestPaint] (handle: Int, op: String, nums: [Double]) in
            MainActor.assumeIsolated({
                guard let ctx = (nodeForHandle(handle) as? Element)?.canvasContext else { return }
                let rect: Rect = Rect(
                    left: CGFloat(nums[0]),
                    top: CGFloat(nums[1]),
                    right: CGFloat(nums[0] + nums[2]),
                    bottom: CGFloat(nums[1] + nums[3])
                )
                switch op {
                    case "fill": ctx.fillRect(rect)
                    case "clear": ctx.clearRect(rect)
                    case "stroke": ctx.strokeRect(rect)
                    default: break
                }
                requestPaint()
            })
        } as @convention(block) (Int, String, [Double]) -> Void,
        forKeyedSubscript: "_canvasRect" as NSString)

        jsContext.setObject({
            [nodeForHandle, requestPaint] (handle: Int, op: String, nums: [Double]) in
            MainActor.assumeIsolated({
                guard let ctx = (nodeForHandle(handle) as? Element)?.canvasContext else { return }
                switch op {
                    case "begin": ctx.beginPath()
                    case "move": ctx.moveTo(Point(x: CGFloat(nums[0]), y: CGFloat(nums[1])))
                    case "line": ctx.lineTo(Point(x: CGFloat(nums[0]), y: CGFloat(nums[1])))
                    default: break
                }
                requestPaint()
            })
        } as @convention(block) (Int, String, [Double]) -> Void,
        forKeyedSubscript: "_canvasPath" as NSString)

        jsContext.setObject({
            [nodeForHandle, requestPaint] (handle: Int, op: String) in
            MainActor.assumeIsolated({
                guard let ctx = (nodeForHandle(handle) as? Element)?.canvasContext else { return }
                if op == "fill" { ctx.fill() } else { ctx.stroke() }
                requestPaint()
            })
        } as @convention(block) (Int, String) -> Void,
        forKeyedSubscript: "_canvasPaint" as NSString)

        jsContext.setObject({
            [nodeForHandle, requestPaint] (handle: Int, text: String, nums: [Double]) in
            MainActor.assumeIsolated({
                guard let ctx = (nodeForHandle(handle) as? Element)?.canvasContext else { return }
                ctx.fillText(text, at: Point(x: CGFloat(nums[0]), y: CGFloat(nums[1])))
                requestPaint()
            })
        } as @convention(block) (Int, String, [Double]) -> Void,
        forKeyedSubscript: "_canvasText" as NSString)
    }
}
