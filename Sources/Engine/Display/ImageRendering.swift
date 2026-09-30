public enum ImageRendering: String {
    case auto, highQuality = "high-quality", crispEdges = "crisp-edges"
    init(css: String?) { self = ImageRendering(rawValue: css ?? "auto") ?? .auto }
}
