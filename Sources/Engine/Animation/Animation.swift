let secondsPerFrame: Double = 1.0 / 60.0

protocol Animation: AnyObject {
    func nextValue() -> String?
    var animatedProperty: String { get }
}
