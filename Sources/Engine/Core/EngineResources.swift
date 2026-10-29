import Foundation

enum EngineResources {
    static let bundle: Bundle = {
        let name: String = "ToyStack_Engine.bundle"
        let candidates: [URL?] = [
            Bundle.main.resourceURL?.appendingPathComponent(name),
            Bundle.main.bundleURL.appendingPathComponent(name),
            Bundle.main.bundleURL.deletingLastPathComponent().appending(path: name)
        ]
        for case let url? in candidates {
            if let bundle: Bundle = Bundle(url: url) {
                return bundle
            }
        }
        fatalError("could not find \(name)")
    }()
}
