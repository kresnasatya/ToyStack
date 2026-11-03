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

    static func replacement(for attributes: [String: String]) -> CGImage? {
        hasAltText(attributes) ? image : nil
    }

    static func hasAltText(_ attributes: [String: String]) -> Bool {
        guard let alt: String = attributes["alt"] else { return false }
        return !alt.isEmpty
    }
}
