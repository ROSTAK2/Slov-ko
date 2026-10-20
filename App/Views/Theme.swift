import SwiftUI
import UIKit

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

enum Theme {
    static let blue = Color(hex: 0x1F6FEB)
    static let green = Color(hex: 0x2BB673)
    static let red = Color(hex: 0xE5484D)
    static let gold = Color(hex: 0xF5B700)
    static let orange = Color(hex: 0xFF8A00)
    static let locked = Color(hex: 0xC9CED6)

    static let unitColors: [Color] = [
        Color(hex: 0x1F6FEB), // modrá
        Color(hex: 0x2BB673), // zelená
        Color(hex: 0x8B5CF6), // fialová
        Color(hex: 0xFF8A00), // oranžová
        Color(hex: 0xE5487F), // ružová
        Color(hex: 0x0EA5B7), // tyrkysová
        Color(hex: 0xD9534F), // červená
        Color(hex: 0x4F5BD5)  // indigo
    ]

    static func unitColor(_ id: Int) -> Color {
        unitColors[max(0, id - 1) % unitColors.count]
    }
}

/// Объёмная «игровая» кнопка с тенью снизу.
struct ChunkyButtonStyle: ButtonStyle {
    var color: Color = Theme.blue
    var textColor: Color = .white

    func makeBody(configuration: Configuration) -> some View {
        ChunkyBody(configuration: configuration, color: color, textColor: textColor)
    }

    private struct ChunkyBody: View {
        let configuration: ButtonStyleConfiguration
        let color: Color
        let textColor: Color
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            let fill = isEnabled ? color : Color(.systemGray4)
            let pressed = configuration.isPressed
            configuration.label
                .font(.headline.weight(.heavy))
                .foregroundColor(isEnabled ? textColor : Color(.systemGray))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(fill)
                            .overlay(RoundedRectangle(cornerRadius: 16).fill(Color.black.opacity(0.22)))
                            .offset(y: pressed ? 0 : 4)
                        RoundedRectangle(cornerRadius: 16).fill(fill)
                    }
                )
                .offset(y: pressed ? 4 : 0)
                .padding(.bottom, 4)
        }
    }
}

/// Плитка-вариант ответа (белая с рамкой).
struct OptionCard<Content: View>: View {
    var selected: Bool
    var tint: Color = Theme.blue
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(selected ? tint.opacity(0.12) : Color(.secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(selected ? tint : Color(.systemGray4), lineWidth: 2)
            )
    }
}

/// Раскладка «в строку с переносом» — для плиток со словами.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width.map { $0.isFinite ? $0 : .greatestFiniteMagnitude } ?? .greatestFiniteMagnitude
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        let width = proposal.width.map { $0.isFinite ? $0 : widest } ?? widest
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// Кнопка-динамик: проговаривает словацкий текст.
struct SpeakerButton: View {
    let text: String
    var big = false
    var slow = false

    var body: some View {
        Button {
            Speech.shared.speak(text, slow: slow)
        } label: {
            Image(systemName: slow ? "tortoise.fill" : "speaker.wave.2.fill")
                .font(big ? .system(size: 34, weight: .bold) : .system(size: 16, weight: .bold))
                .foregroundColor(.white)
                .frame(width: big ? 96 : 34, height: big ? 96 : 34)
                .background(
                    RoundedRectangle(cornerRadius: big ? 24 : 10)
                        .fill(slow ? Theme.blue.opacity(0.7) : Theme.blue)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(slow ? "Медленно" : "Прослушать")
    }
}

/// Строка со словацкими буквами — у большинства клавиатур их нет.
struct DiacriticsBar: View {
    let onTap: (String) -> Void
    private let letters = ["á", "ä", "č", "ď", "é", "í", "ĺ", "ľ", "ň", "ó", "ô", "ŕ", "š", "ť", "ú", "ý", "ž"]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(letters, id: \.self) { letter in
                    Button {
                        onTap(letter)
                    } label: {
                        Text(letter)
                            .font(.title3.weight(.semibold))
                            .frame(width: 36, height: 40)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color(.secondarySystemGroupedBackground)))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(.systemGray4), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }
}

enum Haptics {
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func error() { UINotificationFeedbackGenerator().notificationOccurred(.error) }
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
}

/// Простой рендер параграфа с **жирным** (inline Markdown).
func markdownText(_ string: String) -> Text {
    let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
    if let attributed = try? AttributedString(markdown: string, options: options) {
        return Text(attributed)
    }
    return Text(string)
}
