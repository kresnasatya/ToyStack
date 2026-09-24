public enum BrowserBlendMode: String {
    case normal
    case multiply
    case difference
    case destinationIn
}

extension BrowserBlendMode {
    public var compositingFilterName: String? {
        switch self {
            case .normal, .destinationIn: return nil
            case .multiply: return "CIMultiplyBlendMode"
            case .difference: return "CIDifferenceBlendMode"
        }
    }
}
