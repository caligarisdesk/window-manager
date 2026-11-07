import SwiftUI

struct StatusDot: View {
    let status: SessionStatus
    @State private var pulse = false

    var body: some View {
        ZStack {
            if status == .working || status == .needsYou {
                Circle().fill(status.color.opacity(0.35))
                    .frame(width: 14, height: 14)
                    .scaleEffect(pulse ? 1.25 : 0.7)
                    .opacity(pulse ? 0 : 1)
            }
            Circle().fill(status.color).frame(width: 8, height: 8)
        }
        .frame(width: 14, height: 14)
        .onAppear {
            withAnimation(.easeOut(duration: status == .working ? 1.0 : 1.8).repeatForever(autoreverses: false)) { pulse = true }
        }
    }
}

struct MetricPill: View {
    @Environment(\.colorScheme) private var scheme
    private var theme: Theme { Theme(scheme) }
    let icon: String
    let value: String
    var help: String = ""
    var tint: Color = .gray

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 10, weight: .semibold)).foregroundColor(tint)
            Text(value).font(.system(size: 11, weight: .medium, design: .rounded)).monospacedDigit().foregroundColor(theme.text)
        }
        .padding(.horizontal, 7).padding(.vertical, 4)
        .background(theme.chip, in: Capsule())
        .help(help)
    }
}

struct ContextGauge: View {
    @Environment(\.colorScheme) private var scheme
    private var theme: Theme { Theme(scheme) }
    let fill: Double
    let tokens: Int
    let window: Int

    private var brain: some View {
        Image(systemName: "brain").font(.system(size: 17, weight: .bold)).imageScale(.medium)
    }

    /// Visible fill level; symbol strokes don't reach the very top/bottom, so map into that band
    /// and keep a sliver visible even for nearly empty contexts.
    private var level: Double { 0.06 + 0.94 * min(1, max(0, fill)) }

    private var color: Color {
        fill > 0.85 ? .red : fill > 0.6 ? .orange : Color.blue
    }

    var body: some View {
        HStack(spacing: 4) {
            ZStack {
                brain.foregroundColor(theme.secondary.opacity(0.35))
                ZStack {
                    // Soft "liquid" inside the brain outline.
                    Ellipse().fill(color.opacity(0.28)).scaleEffect(x: 0.78, y: 0.72).offset(y: -0.5)
                    brain.foregroundColor(color)
                }
                .mask(alignment: .bottom) {
                    GeometryReader { g in
                        VStack(spacing: 0) {
                            Spacer(minLength: 0)
                            Rectangle().frame(height: g.size.height * level)
                        }
                    }
                }
            }
            .fixedSize()
            Text("\(Int(fill * 100))%").font(.system(size: 10, weight: .semibold, design: .rounded)).monospacedDigit()
                .foregroundColor(color)
        }
        .animation(.easeInOut(duration: 0.6), value: fill)
        .help("Context: \(Fmt.tokens(tokens)) of \(Fmt.tokens(window)) tokens")
    }
}
