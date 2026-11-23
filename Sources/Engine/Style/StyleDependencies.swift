// MARK: - StyleDependencies

struct StyleDependencies: OptionSet {
    let rawValue: UInt8

    static let viewport: StyleDependencies = StyleDependencies(rawValue: 1 << 0)
    static let rootFont: StyleDependencies = StyleDependencies(rawValue: 1 << 1)

    init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    init(declarations: [String: String]) {
        var dependencies: StyleDependencies = []
        for value in declarations.values {
            if RelativeLengths.isViewportRelative(value) {
                dependencies.insert(.viewport)
            }
            if RelativeLengths.isRootRelative(value) {
                dependencies.insert(.rootFont)
            }
        }
        self = dependencies
    }
}
