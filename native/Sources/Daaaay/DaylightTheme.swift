import SwiftUI
import DayCore

enum DaylightTheme {
    static let canvas = Color(hex: DaylightTokens.canvasHex)
    static let surface = Color(hex: DaylightTokens.surfaceHex)
    static let ink = Color(hex: DaylightTokens.inkHex)
    static let slate = Color(hex: DaylightTokens.slateHex)
    static let hairline = Color(hex: DaylightTokens.hairlineHex)
    static let action = Color(hex: DaylightTokens.actionHex)
    static let living = Color(hex: DaylightTokens.livingHex)
    static let sun = Color(hex: DaylightTokens.sunHex)

    static let primaryHeight = CGFloat(DaylightTokens.primaryHeight)
    static let minimumTarget = CGFloat(DaylightTokens.minimumTarget)
}

extension Color {
    init(hex: String) {
        let value = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        let number = UInt64(value, radix: 16) ?? 0
        self.init(
            red: Double((number >> 16) & 0xFF) / 255,
            green: Double((number >> 8) & 0xFF) / 255,
            blue: Double(number & 0xFF) / 255
        )
    }
}
