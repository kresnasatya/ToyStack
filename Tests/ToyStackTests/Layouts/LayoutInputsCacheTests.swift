import CoreGraphics
import Foundation
import Testing

@testable import Engine

@Suite(.serialized)
@MainActor
struct LayoutInputsCacheTests {

    @Test func widthResizeReusesLayoutInputs() {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<div id="box">one two three four</div>"#,
            rules: """
                html { width: 600px; }
                body { display: block; }
                div { display: block; width: 300px; }
                """
        )

        page.frame.setViewport(width: 500, height: page.frame.frameHeight)
        page.frame.setNeedsViewportResize()
        page.frame.render()

        let metrics: [String: ProfileMetric] = profiler.snapshot()
        #expect((metrics["layout.inputs.reused"]?.count ?? 0) > 0)
        #expect(metrics["layout.inputs.rebuilt"] == nil)
    }

    @Test func styleChangeRebuildsOnlyTouchedInputs() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<div id="box">text</div>"#,
            rules: """
                html { width: 600px; }
                body { display: block; }
                div { display: block; }
                """
        )
        let box: ElementRef = try #require(page.firstElement(id: "box"))

        box.style.mutate({ style in
            style.text.color = BrowserColor(cssName: "blue")
        })
        page.frame.setNeedsLayout()
        page.frame.render()

        let metrics: [String: ProfileMetric] = profiler.snapshot()
        #expect((metrics["layout.inputs.style"]?.count ?? 0) > 0)
        #expect((metrics["layout.inputs.reused"]?.count ?? 0) > 0)
        #expect(box.style.computed.text.color == BrowserColor(cssName: "blue"))
    }

    @Test func documentMutationRebuildsInputs() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<p id="p">one</p>"#,
            rules: """
                html { width: 600px; }
                body { display: block; }
                p { display: block; }
                """
        )
        let paragraph: ElementRef = try #require(page.firstElement(id: "p"))
        let text: TextRef = try #require(paragraph.children.first?.text)

        text.append(" more")
        page.frame.setNeedsRender()
        page.frame.render()

        let metrics: [String: ProfileMetric] = profiler.snapshot()
        #expect(metrics["layout.inputs.reused"] == nil)
    }

    @Test func imageChangeRebuildsInputs() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<img id="pic" src="missing.png">"#,
            rules: """
                html { width: 600px; }
                body { display: block; }
                img { display: block; width: 20px; height: 20px; }
                """
        )
        let image: ElementRef = try #require(page.firstElement(id: "pic"))

        image.image = makeTestImage()
        LayoutInvalidation.imageChanged(image.ref)
        page.frame.setNeedsLayout()
        page.frame.render()

        let metrics: [String: ProfileMetric] = profiler.snapshot()
        #expect(metrics["layout.inputs.reused"] == nil)
    }
}

private func makeTestImage() -> CGImage {
    let colorSpace: CGColorSpace = CGColorSpaceCreateDeviceRGB()
    let pixels: [UInt8] = [255, 0, 0, 255]
    let provider: CGDataProvider = CGDataProvider(data: Data(pixels) as CFData)!
    return CGImage(
        width: 1,
        height: 1,
        bitsPerComponent: 8,
        bitsPerPixel: 32,
        bytesPerRow: 4,
        space: colorSpace,
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
        provider: provider,
        decode: nil,
        shouldInterpolate: false,
        intent: .defaultIntent
    )!
}
