import SwiftUI

/// Rotates a card face around the Y axis and hides it once it turns past 90°.
struct FlipEffect: AnimatableModifier {
    var angle: Double
    let isBack: Bool

    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    func body(content: Content) -> some View {
        let visible = isBack ? angle >= 90 : angle < 90
        content
            .opacity(visible ? 1 : 0)
            .rotation3DEffect(.degrees(isBack ? angle - 180 : angle), axis: (x: 0, y: 1, z: 0), perspective: 0.4)
            .allowsHitTesting(visible)
    }
}
