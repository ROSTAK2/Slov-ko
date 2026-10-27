import SwiftUI

/// Кнопка слегка «вдавливается» при нажатии.
struct PressScale: ButtonStyle {
    var scale: CGFloat = 0.95

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// Число, которое «досчитывает» до значения при анимации (+15 XP).
struct CountingText: View, Animatable {
    var value: Double
    var prefix: String = ""
    var suffix: String = ""

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text(verbatim: "\(prefix)\(Int(value.rounded()))\(suffix)")
    }
}

/// Конфетти цветов флага Словакии и звёзд ЕС.
struct ConfettiView: View {
    var count = 90

    private struct Piece: Identifiable {
        let id = UUID()
        let x: CGFloat
        let drift: CGFloat
        let color: Color
        let size: CGSize
        let spin: Double
        let delay: Double
        let duration: Double
        let round: Bool
    }

    @State private var pieces: [Piece] = []
    @State private var falling = false

    private let colors: [Color] = [
        .white, Color(hex: 0x0B4EA2), Color(hex: 0xEE1C25), Color(hex: 0xFFCC00),
        Color(hex: 0x2BB673), Color(hex: 0x8B5CF6)
    ]

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(pieces) { piece in
                    Group {
                        if piece.round {
                            Circle().fill(piece.color)
                        } else {
                            RoundedRectangle(cornerRadius: 1.5).fill(piece.color)
                        }
                    }
                    .frame(width: piece.size.width, height: piece.size.height)
                    .shadow(color: .black.opacity(0.15), radius: 0.5)
                    .rotationEffect(.degrees(falling ? piece.spin : 0))
                    .rotation3DEffect(.degrees(falling ? piece.spin * 1.5 : 0), axis: (x: 1, y: 0.3, z: 0))
                    .position(x: piece.x * geo.size.width + (falling ? piece.drift : 0),
                              y: falling ? geo.size.height + 40 : -30)
                    .animation(.easeIn(duration: piece.duration).delay(piece.delay), value: falling)
                }
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            guard pieces.isEmpty else { return }
            pieces = (0..<count).map { _ -> Piece in
                let wide = CGFloat.random(in: 6...10)
                return Piece(x: .random(in: 0...1),
                             drift: .random(in: -80...80),
                             color: colors.randomElement() ?? .white,
                             size: CGSize(width: wide, height: wide * .random(in: 1.2...2.2)),
                             spin: .random(in: 180...900) * (Bool.random() ? 1 : -1),
                             delay: .random(in: 0...0.8),
                             duration: .random(in: 2.2...3.8),
                             round: Int.random(in: 0..<5) == 0)
            }
            DispatchQueue.main.async { falling = true }
        }
    }
}

/// Мягкое «парение» вверх-вниз — для картинок на карте.
struct Floating: ViewModifier {
    var amplitude: CGFloat = 5
    var duration: Double = 2.2
    @State private var up = false

    func body(content: Content) -> some View {
        content
            .offset(y: up ? -amplitude : amplitude)
            .animation(.easeInOut(duration: duration).repeatForever(autoreverses: true), value: up)
            .onAppear { up = true }
    }
}

extension View {
    func floating(amplitude: CGFloat = 5, duration: Double = 2.2) -> some View {
        modifier(Floating(amplitude: amplitude, duration: duration))
    }
}

/// Названия уровней CEFR для разделителей на карте.
enum LevelInfo {
    static func title(_ level: String) -> String {
        switch level {
        case "A1": return "Начальный уровень"
        case "A2": return "Элементарный уровень"
        case "B1": return "Средний уровень"
        case "B2": return "Выше среднего"
        default: return "Уровень \(level)"
        }
    }
}

/// Тряска «нет-нет» — при ошибке. Анимируется изменением animatableData (0 → 1).
struct Shake: GeometryEffect {
    var amount: CGFloat = 8
    var shakes: CGFloat = 3
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: amount * sin(animatableData * .pi * shakes * 2), y: 0))
    }
}

/// Округлый шрифт во всём приложении (как в игровых приложениях).
struct RoundedDesign: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 16.1, *) {
            content.fontDesign(.rounded)
        } else {
            content
        }
    }
}

extension View {
    func roundedDesign() -> some View {
        modifier(RoundedDesign())
    }
}

/// Талисман реагирует на ответ: подпрыгивает со звёздочками или огорчённо качается.
struct MascotReaction: View {
    let positive: Bool
    @State private var animate = false

    var body: some View {
        ZStack {
            if positive {
                StarBurst(active: animate)
            }
            Mascot(size: 40)
                .scaleEffect(animate ? 1 : 0.4)
                .rotationEffect(.degrees(positive ? (animate ? 0 : -20) : 0))
                .modifier(Shake(amount: positive ? 0 : 5, shakes: 2, animatableData: animate ? 1 : 0))
        }
        .frame(width: 44, height: 44)
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.45)) {
                animate = true
            }
        }
    }
}

/// Звёздочки разлетаются из центра.
struct StarBurst: View {
    let active: Bool

    var body: some View {
        ZStack {
            ForEach(0..<8, id: \.self) { i in
                Image(systemName: "star.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(Theme.gold)
                    .offset(y: active ? -36 : -6)
                    .scaleEffect(active ? 1.1 : 0.4)
                    .opacity(active ? 0 : 1)
                    .frame(width: 90, height: 90)
                    .rotationEffect(.degrees(Double(i) * 45))
                    .animation(.easeOut(duration: 0.8), value: active)
            }
        }
        .allowsHitTesting(false)
    }
}

/// Пламя серии «мерцает», если сегодня уже занимались.
struct Flicker: ViewModifier {
    var active: Bool
    @State private var on = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(active && on ? 1.15 : 1, anchor: .bottom)
            .animation(active ? .easeInOut(duration: 0.6).repeatForever(autoreverses: true) : .default, value: on)
            .onAppear { on = true }
    }
}
