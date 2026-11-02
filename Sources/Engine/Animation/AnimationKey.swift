// MARK: - AnimationKey

enum AnimationKey: Hashable {
    case property(StyleProperty)
    case keyframes(String)
}
