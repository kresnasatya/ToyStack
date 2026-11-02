import CoreGraphics
import Foundation
import ImageIO

enum BrokenImage {
    static let image: CGImage = {
        guard let url = EngineResources.bundle.url(forResource: "Broken_Image", withExtension: "png"),
            let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            fatalError("Broken_Image.png missing from bundle")
        }
        return image
    }()

    @MainActor
    static func replacement(for element: ElementRef) -> CGImage? {
        hasAltText(element) ? image : nil
    }

    @MainActor
    static func hasAltText(_ element: ElementRef) -> Bool {
        guard let alt: String = element.attributes["alt"] else { return false }
        return !alt.isEmpty
    }
}
