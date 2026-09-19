import CoreGraphics
import Foundation

// MARK: - Layout Constants
public let WIDTH: CGFloat = 800
public let HEIGHT: CGFloat = 600
let HSTEP: CGFloat = 13
let VSTEP: CGFloat = 18
let SCROLL_STEP: CGFloat = 100

public let isRTL: Bool = ProcessInfo.processInfo.arguments.contains("--rtl")
