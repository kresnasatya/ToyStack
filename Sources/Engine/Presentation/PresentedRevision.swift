/// `content` changes only when the engine commits new content. `sequence`
/// changes on every dispatch and is used to de-duplicate present work. The
/// presentation state compares `content` only, so a resize can preview the
/// same content at a new size.
public struct PresentedRevision: Equatable, Sendable {
    public let content: Int
    public let sequence: Int

    public init(content: Int, sequence: Int) {
        self.content = content
        self.sequence = sequence
    }
}
