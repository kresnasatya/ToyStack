/// One frozen frame handed from `Frame` to the tab presentation.
struct FrameSnapshot: Sendable {
    let scroll: ScrollState
    let display: DisplaySnapshot
    let preferences: ColorPreferences
}
