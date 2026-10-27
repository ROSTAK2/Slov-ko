import SwiftUI

/// Показывает, где именно ошибка: сравнивает ответ ученика с правильным
/// (по буквам — для письма, по словам — для плиток) и подсвечивает расхождения.
enum AnswerDiff {
    /// Возвращает (ответ ученика с выделенными лишними/неверными частями,
    ///             правильный ответ с выделенными пропущенными/исправленными частями).
    static func highlight(user: String, correct: String, byWords: Bool,
                          wrongColor: Color, fixColor: Color) -> (AttributedString, AttributedString) {
        let a = units(user, byWords: byWords)
        let b = units(correct, byWords: byWords)
        let (keepA, keepB) = lcs(a.map { key($0) }, b.map { key($0) })

        var userText = AttributedString()
        for (i, unit) in a.enumerated() {
            var piece = AttributedString(unit)
            if !keepA.contains(i) && isMeaningful(unit) {
                piece.foregroundColor = wrongColor
                piece.strikethroughStyle = Text.LineStyle.single
                piece.backgroundColor = wrongColor.opacity(0.15)
            }
            userText += piece
            if byWords && i < a.count - 1 { userText += AttributedString(" ") }
        }

        var correctText = AttributedString()
        for (i, unit) in b.enumerated() {
            var piece = AttributedString(unit)
            if !keepB.contains(i) && isMeaningful(unit) {
                piece.foregroundColor = fixColor
                piece.backgroundColor = fixColor.opacity(0.18)
                piece.underlineStyle = Text.LineStyle.single
            }
            correctText += piece
            if byWords && i < b.count - 1 { correctText += AttributedString(" ") }
        }
        return (userText, correctText)
    }

    private static func units(_ text: String, byWords: Bool) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if byWords {
            return trimmed.split(separator: " ").map(String.init)
        }
        return trimmed.map { String($0) }
    }

    /// Пробелы и знаки препинания не подсвечиваем — при проверке они не учитываются.
    private static func isMeaningful(_ unit: String) -> Bool {
        !key(unit).trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Сравниваем без учёта регистра и знаков препинания по краям слова.
    private static func key(_ unit: String) -> String {
        unit.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".,!?;:„“\"”«»…()"))
    }

    /// Наибольшая общая подпоследовательность: какие элементы совпали в обеих строках.
    private static func lcs(_ a: [String], _ b: [String]) -> (Set<Int>, Set<Int>) {
        let n = a.count, m = b.count
        guard n > 0, m > 0 else { return ([], []) }
        var table = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                table[i][j] = a[i] == b[j] ? table[i + 1][j + 1] + 1 : max(table[i + 1][j], table[i][j + 1])
            }
        }
        var keepA = Set<Int>(), keepB = Set<Int>()
        var i = 0, j = 0
        while i < n && j < m {
            if a[i] == b[j] {
                keepA.insert(i)
                keepB.insert(j)
                i += 1
                j += 1
            } else if table[i + 1][j] >= table[i][j + 1] {
                i += 1
            } else {
                j += 1
            }
        }
        return (keepA, keepB)
    }
}

/// Блок «Ваш ответ / Правильно» с подсветкой расхождений.
struct DiffAnswerView: View {
    let user: String
    let correct: String
    let byWords: Bool

    var body: some View {
        let (userText, correctText) = AnswerDiff.highlight(user: user, correct: correct, byWords: byWords,
                                                           wrongColor: Theme.red, fixColor: Theme.green)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Ваш ответ:")
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(.secondary)
                Text(userText)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Правильно:")
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(.secondary)
                Text(correctText)
                    .font(.body.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(.systemBackground).opacity(0.85)))
    }
}
