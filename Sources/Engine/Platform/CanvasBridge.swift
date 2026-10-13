import Foundation
import JavaScriptCore
import CoreGraphics

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

        jsContext.setObject({
            [nodeForHandle] (handle: Int, op: String) in
            MainActor.assumeIsolated({
                guard let ctx = (nodeForHandle(handle) as? Element)?.canvasContext else { return }
                if op == "save" { ctx.save() } else { ctx.restore() }
            })
        } as @convention(block) (Int, String) -> Void,
        forKeyedSubscript: "_canvasState" as NSString)

        jsContext.setObject({
            [nodeForHandle] (handle: Int, op: String, nums: [Double]) in
            MainActor.assumeIsolated({
                guard let ctx = (nodeForHandle(handle) as? Element)?.canvasContext else { return }
                switch op {
                    case "translate": ctx.translate(x: CGFloat(nums[0]), y: CGFloat(nums[1]))
                    case "scale": ctx.scale(x: CGFloat(nums[0]), y: CGFloat(nums[1]))
                    case "rotate": ctx.rotate(radians: CGFloat(nums[0]))
                    case "transform": ctx.transform(CanvasBridge.affine(nums))
                    case "setTransform": ctx.setTransform(CanvasBridge.affine(nums))
                    case "reset": ctx.resetTransform()
                    default: break
                }
            })
        } as @convention(block) (Int, String, [Double]) -> Void,
        forKeyedSubscript: "_canvasTransform" as NSString)

        jsContext.setObject({
            [nodeForHandle, requestPaint] (handle: Int, source: Int, mode: String, nums: [Double]) in
            MainActor.assumeIsolated({
                guard let ctx = (nodeForHandle(handle) as? Element)?.canvasContext,
                    let img = (nodeForHandle(source) as? Element)?.image
                else { return }
                let width: CGFloat = CGFloat(img.width)
                let height: CGFloat = CGFloat(img.height)
                let sourceRect: Rect?
                let dest: Rect
                switch mode {
                    case "at":
                        sourceRect = nil
                        dest = Rect(
                            left: CGFloat(nums[0]),
                            top: CGFloat(nums[1]),
                            right: CGFloat(nums[0]) + width,
                            bottom: CGFloat(nums[1]) + height
                        )
                    case "scale":
                        sourceRect = nil
                        dest = Rect(
                            left: CGFloat(nums[0]),
                            top: CGFloat(nums[1]),
                            right: CGFloat(nums[0] + nums[2]),
                            bottom: CGFloat(nums[1] + nums[3])
                        )
                    case "crop":
                        sourceRect = Rect(
                            left: CGFloat(nums[0]),
                            top: CGFloat(nums[1]),
                            right: CGFloat(nums[0] + nums[2]),
                            bottom: CGFloat(nums[1] + nums[3])
                        )
                        dest = Rect(
                            left: CGFloat(nums[4]),
                            top: CGFloat(nums[5]),
                            right: CGFloat(nums[4] + nums[6]),
                            bottom: CGFloat(nums[5] + nums[7])
                        )
                    default: return
                }
                ctx.drawImage(img, source: sourceRect, dest: dest)
                requestPaint()
            })
        } as @convention(block) (Int, Int, String, [Double]) -> Void,
        forKeyedSubscript: "_canvasDrawImage" as NSString)

        jsContext.setObject({
            [nodeForHandle] (handle: Int, kind: String, nums: [Double]) -> Int in
            MainActor.assumeIsolated({
                guard let ctx = (nodeForHandle(handle) as? Element)?.canvasContext else { return -1 }
                return ctx.createGradient(kind: kind, nums: nums)
            })
        } as @convention(block) (Int, String, [Double]) -> Int,
        forKeyedSubscript: "_canvasCreateGradient" as NSString)

        jsContext.setObject({
            [nodeForHandle] (handle: Int, id: Int, offset: Double, color: String) in
            MainActor.assumeIsolated({
                guard let ctx = (nodeForHandle(handle) as? Element)?.canvasContext else { return }
                ctx.addColorStop(id: id, offset: offset, color: color)
            })
        } as @convention(block) (Int, Int, Double, String) -> Void,
        forKeyedSubscript: "_canvasGradientStop" as NSString)
    }

    private static func affine(_ nums: [Double]) -> CGAffineTransform {
        CGAffineTransform(
            a: CGFloat(nums[0]),
            b: CGFloat(nums[1]),
            c: CGFloat(nums[2]),
            d: CGFloat(nums[3]),
            tx: CGFloat(nums[4]),
            ty: CGFloat(nums[5])
        )
    }
}
