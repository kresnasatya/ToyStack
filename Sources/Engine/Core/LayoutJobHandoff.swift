/// Passes a layout tree to a background job without keeping a second
/// reference to it.
///
/// A value in a task's capture list lives as long as the task, so the job's
/// copy would never be the only owner of its storage and its first write would
/// copy the node array and the dependency index. `take()` moves the tree out
/// instead.
final class LayoutJobHandoff: @unchecked Sendable {
    private var tree: LayoutTree?

    init(_ tree: LayoutTree) {
        self.tree = tree
    }

    /// Called once, by the job. Accessed from one thread at a time: the main
    /// thread creates the handoff before it starts the task.
    func take() -> LayoutTree {
        guard let tree: LayoutTree = tree else {
            preconditionFailure("The layout tree was already taken")
        }
        self.tree = nil
        return tree
    }
}
