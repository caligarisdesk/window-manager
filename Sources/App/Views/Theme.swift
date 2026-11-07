import SwiftUI

/// Explicit palette for light and dark appearance so text always has strong contrast.
struct Theme {
    let bg, card, cardHover, inset, chip, chipSelected, border, borderStrong, text, secondary: Color
    let shadow: Double

    init(_ scheme: ColorScheme) {
        if scheme == .dark {
            bg = Color(red: 0.11, green: 0.12, blue: 0.14)
            card = Color(red: 0.17, green: 0.18, blue: 0.21)
            cardHover = Color(red: 0.20, green: 0.21, blue: 0.25)
            inset = Color(red: 0.13, green: 0.14, blue: 0.17)
            chip = Color.white.opacity(0.10)
            chipSelected = Color.white.opacity(0.22)
            border = Color.white.opacity(0.12)
            borderStrong = Color.white.opacity(0.30)
            text = Color(red: 0.96, green: 0.96, blue: 0.97)
            secondary = Color(red: 0.70, green: 0.72, blue: 0.77)
            shadow = 0.35
        } else {
            bg = Color(red: 0.94, green: 0.95, blue: 0.97)
            card = .white
            cardHover = .white
            inset = Color(red: 0.95, green: 0.96, blue: 0.98)
            chip = Color.black.opacity(0.06)
            chipSelected = Color.black.opacity(0.14)
            border = Color.black.opacity(0.10)
            borderStrong = Color.black.opacity(0.25)
            text = Color(red: 0.10, green: 0.11, blue: 0.14)
            secondary = Color(red: 0.38, green: 0.40, blue: 0.46)
            shadow = 0.10
        }
    }
}

extension SessionStatus {
    var color: Color {
        switch self {
        case .needsYou: return Color(red: 1.0, green: 0.62, blue: 0.2)
        case .working: return Color(red: 0.25, green: 0.85, blue: 0.5)
        case .idle: return Color(white: 0.55)
        case .shell: return Color(red: 0.35, green: 0.6, blue: 1.0)
        }
    }
}

extension TerminalSession {
    /// Per-project tint so cards from the same directory look alike.
    var accent: Color { Color(hue: accentHue, saturation: 0.55, brightness: 0.95) }
}
