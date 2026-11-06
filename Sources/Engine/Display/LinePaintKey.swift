import CoreGraphics

/// The two independent inputs that make a line's cached ops stale: the line's
/// generation (content and geometry) and a hash of the style revisions of the
/// boxes' owners (text colour and other node-local paint inputs).
///
/// They are kept as separate fields rather than mixed into one number: mixing
/// with XOR lets a generation change cancel an owner-revision change
/// (`8 ^ 1 == 11 ^ 2`), which served stale text after a font flip.
struct LinePaintVersion: Equatable, Sendable {
    let generation: UInt
    let style: UInt64
}

struct LinePaintKey: Equatable, Sendable {
    let x: CGFloat
    let y: CGFloat
    let epoch: UInt
    let version: LinePaintVersion

    init(x: CGFloat, y: CGFloat, epoch: UInt, version: LinePaintVersion) {
        self.x = x
        self.y = y
        self.epoch = epoch
        self.version = version
    }
}
