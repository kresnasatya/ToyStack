public struct PresentedRevision: Equatable, Sendable {
    public let content: Int
    public let sequence: Int

    public init(content: Int, sequence: Int) {
        self.content = content
        self.sequence = sequence
    }
}
