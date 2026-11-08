/// Moves a layout tree to another thread without keeping a second reference
/// to it.
///
/// A value in a task's capture list lives as long as the task, so a captured
/// tree is never the only owner of its storage. `take()` moves the tree out
/// instead. A background layout job uses it so its first write does not copy
/// the node array and dependency index; an install uses it so the replaced
/// tree is freed off the main thread.
final class LayoutTreeHandoff: @unchecked Sendable {
    private var tree: LayoutTree?

    init(_ tree: LayoutTree) {
        self.tree = tree
    }

    /// Called once, by the receiving task. Accessed from one thread at a time:
    /// the main thread creates the handoff before it starts the task.
    func take() -> LayoutTree {
        guard let tree: LayoutTree = tree else {
            preconditionFailure("The layout tree was already taken")
        }
        self.tree = nil
        return tree
    }
}
