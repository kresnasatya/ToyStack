import Foundation

enum EngineResources {
    private final class BundleToken {}

    static let bundle: Bundle = {
        let name: String = "ToyStack_Engine.bundle"
        var candidates: [URL] = []
        if let resourceURL = Bundle.main.resourceURL {
            candidates.append(resourceURL.appendingPathComponent(name))
        }
        var directory: URL = Bundle(for: BundleToken.self).bundleURL
        for _ in 0..<4 {
            candidates.append(directory.appendingPathComponent(name))
            directory = directory.deletingLastPathComponent()
        }
        candidates.append(Bundle.main.bundleURL.appendingPathComponent(name))
        for url in candidates {
            if let bundle: Bundle = Bundle(url: url) {
                return bundle
            }
        }
        fatalError("could not find \(name)")
    }()
}
