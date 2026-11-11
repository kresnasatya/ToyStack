struct FrameSnapshot: Sendable {
    let scroll: ScrollState
    let display: DisplaySnapshot
    let preferences: ColorPreferences
}
