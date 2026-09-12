extension EngineBlendMode {
    public var compositingFilterName: String? {
        switch self {
            case .normal, .destinationIn: return nil
            case .multiply: return "CIMultiplyBlendMode"
            case .difference: return "CIDifferenceBlendMode"
        }
    }
}
