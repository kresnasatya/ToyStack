import CoreGraphics
import Foundation
import ImageIO

enum BrokenImage {
    static let image: CGImage = {
        guard let url = Bundle.module.url(forResource: "Broken_Image", withExtension: "png"),
            let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            fatalError("Broken_Image.png missing from bundle")
        }
        return image
    }()
}
