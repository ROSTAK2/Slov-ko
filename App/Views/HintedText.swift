import SwiftUI

/// Предложение, в котором каждое слово можно нажать и увидеть перевод (как в Duolingo).
/// Слова одной смысловой части («Volám sa» = «Меня зовут») подсвечиваются вместе.
struct HintedText: View {
    let words: [HintWord]
    /// Слова на словацком (иначе — на русском, а подсказки словацкие).
    var slovak: Bool
    /// Для заданий с пропуском: что показать вместо «___».
    var blank: String? = nil
    var font: Font = .title3.weight(.semibold)

    @State private var selected: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            FlowLayout(spacing: 6) {
                ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                    wordView(index, word)
                }
            }
            if let index = selected, index < words.count {
                hintBar(words[index])
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func wordView(_ index: Int, _ word: HintWord) -> some View {
        if word.t.contains("___") {
            let parts = word.t.components(separatedBy: "___")
            (Text(parts.first ?? "")
                + Text(blank ?? "_____").foregroundColor(Theme.blue).underline()
                + Text(parts.count > 1 ? parts[1] : ""))
                .font(font)
        } else {
            let hasHint = !word.h.isEmpty
            Text(word.t)
                .font(font)
                .padding(.horizontal, 2)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isHighlighted(index) ? Theme.blue.opacity(0.18) : Color.clear)
                )
                .overlay(alignment: .bottom) {
                    if hasHint {
                        DottedUnderline()
                            .stroke(Color.secondary.opacity(0.7),
                                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [1, 4]))
                            .frame(height: 2)
                            .offset(y: 3)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    guard hasHint else { return }
                    Haptics.tap()
                    let opening = selected != index
                    withAnimation(.easeOut(duration: 0.15)) {
                        selected = opening ? index : nil
                    }
                    if opening {
                        Speech.shared.speak(slovak ? groupText(index) : word.h)
                    }
                }
        }
    }

    private func hintBar(_ word: HintWord) -> some View {
        let index = selected ?? 0
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(groupText(index))
                .font(.subheadline.weight(.bold))
            Image(systemName: "arrow.right")
                .font(.caption.weight(.bold))
                .foregroundColor(.secondary)
            Text(word.h)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.blue.opacity(0.12)))
    }

    /// Слова той же смысловой части, что и нажатое слово.
    private func groupText(_ index: Int) -> String {
        let word = words[index]
        let group = word.g >= 0 ? words.filter { $0.g == word.g } : [word]
        return group
            .map { $0.t.trimmingCharacters(in: ExerciseFactory.trimSet) }
            .joined(separator: " ")
    }

    private func isHighlighted(_ index: Int) -> Bool {
        guard let selected, selected < words.count else { return false }
        if selected == index { return true }
        let group = words[selected].g
        return group >= 0 && words[index].g == group
    }
}

struct DottedUnderline: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + 1, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX - 1, y: rect.midY))
        return path
    }
}

/// Плашка «Новое слово».
struct NewWordBadge: View {
    var body: some View {
        Label("НОВОЕ СЛОВО", systemImage: "sparkles")
            .font(.caption.weight(.heavy))
            .foregroundColor(Color(hex: 0x8B5CF6))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color(hex: 0x8B5CF6).opacity(0.14)))
    }
}
