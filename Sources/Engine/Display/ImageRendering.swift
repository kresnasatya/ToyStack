public enum ImageRendering: String, Sendable {
    case auto, highQuality = "high-quality", crispEdges = "crisp-edges"
    init(css: String?) { self = ImageRendering(rawValue: css ?? "auto") ?? .auto }
}
