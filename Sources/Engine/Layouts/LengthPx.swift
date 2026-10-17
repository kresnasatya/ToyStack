import CoreGraphics

// MARK: - LengthPx

func lengthPx(_ css: String?, available: CGFloat, zoom: CGFloat) -> CGFloat? {
    guard let css else { return nil }
    let trimmed: String = css.trimmingCharacters(in: .whitespaces)
    if trimmed.hasSuffix("%"), let pct = Double(trimmed.dropLast()) {
        return available * CGFloat(pct) / 100
    }
    if trimmed.hasSuffix("px"), let px = Double(trimmed.dropLast(2)) {
        return CGFloat(px) * zoom
    }
    return nil
}
