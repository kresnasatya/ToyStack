import Engine
import SwiftUI

extension Color {
    init(engine: BrowserColor) {
        self = Color(
            .sRGB,
            red: engine.red,
            green: engine.green,
            blue: engine.blue,
            opacity: engine.alpha
        )
    }
}
