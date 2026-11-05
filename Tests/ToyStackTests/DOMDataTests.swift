import CoreGraphics
import Testing

@testable import Engine

@Suite(.serialized)
@MainActor
struct DOMDataTests {
    @Test func payloadsHaveValueSemantics() {
        var element: ElementData = ElementData(tag: "p", attributes: ["id": "a"], isChecked: false)
        var copy: ElementData = element
        copy.tag = "div"
        copy.attributes["id"] = "b"
        #expect(element.tag == "p")
        #expect(element.attributes["id"] == "a")

        var text: DOMTextData = DOMTextData(text: "hello")
        var textCopy: DOMTextData = text
        textCopy.text = "bye"
        #expect(text.text == "hello")
    }

    @Test func payloadsStayWithinFourStoredProperties() {
        #expect(storedPropertyCount(DOMBase()) == 4)
        #expect(storedPropertyCount(DOMState()) == 2)
        #expect(storedPropertyCount(DOMFlags()) == 4)
        #expect(storedPropertyCount(ElementData(tag: "p", attributes: [:], isChecked: false)) == 3)
        #expect(storedPropertyCount(DOMTextData(text: "")) == 1)
        #expect(storedPropertyCount(DOMSideTables()) == 4)
        #expect(storedPropertyCount(ImageTable()) == 4)
        #expect(storedPropertyCount(EmbedTable()) == 2)
        #expect(storedPropertyCount(CanvasTable()) == 1)
    }

    @Test func sideTablesStartEmptyAndStoreByNodeID() throws {
        var tables: DOMSideTables = DOMSideTables()
        #expect(tables.images.images.isEmpty)
        #expect(tables.images.backgrounds.isEmpty)
        #expect(tables.images.backgroundSources.isEmpty)
        #expect(tables.embeds.frames.isEmpty)
        #expect(tables.embeds.frameSources.isEmpty)
        #expect(tables.canvases.contexts.isEmpty)
        #expect(tables.scrollOffsets.isEmpty)

        let id: NodeID = NodeID(raw: 7)
        let image: CGImage = try #require(makeImage())
        let frame: Frame = BrowserTab(tabHeight: 600, tabWidth: 800).rootFrame
        let frameID: FrameID = frame.links.id
        let canvas: CanvasRenderingContext2D = try #require(
            CanvasRenderingContext2D(width: 1, height: 1, scale: 1)
        )

        tables.images.images[id] = image
        tables.images.backgroundSources[id] = "background.png"
        tables.embeds.frames[id] = frameID
        tables.embeds.frameSources[id] = "frame.html"
        tables.canvases.contexts[id] = canvas
        tables.scrollOffsets[id] = 42

        #expect(tables.images.images[id] === image)
        #expect(tables.images.backgroundSources[id] == "background.png")
        #expect(tables.embeds.frames[id] == frameID)
        #expect(tables.embeds.frameSources[id] == "frame.html")
        #expect(tables.canvases.contexts[id] === canvas)
        #expect(tables.scrollOffsets[id] == 42)
    }

    @Test func kindSwitchesAreExhaustive() {
        let element: DOMKind = .element(ElementData(tag: "p", attributes: [:], isChecked: true))
        let text: DOMKind = .text(DOMTextData(text: "hello"))
        #expect(describe(element) == "element:p checked:true")
        #expect(describe(text) == "text:hello")
    }

    private func describe(_ kind: DOMKind) -> String {
        switch kind {
        case .element(let data):
            return "element:\(data.tag) checked:\(data.isChecked)"
        case .text(let data):
            return "text:\(data.text)"
        }
    }

    private func storedPropertyCount<T>(_ value: T) -> Int {
        return Mirror(reflecting: value).children.count
    }

    private func makeImage() -> CGImage? {
        guard
            let context: CGContext = CGContext(
                data: nil,
                width: 1,
                height: 1,
                bitsPerComponent: 8,
                bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else { return nil }
        return context.makeImage()
    }
}
