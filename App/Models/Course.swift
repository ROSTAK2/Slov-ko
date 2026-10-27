import Foundation

struct WordPair: Codable, Hashable {
    var sk: String
    var ru: String
    /// «Ложный друг»: значение, которое русскоговорящий ошибочно ожидает (čerstvý ≠ черствый).
    var trap: String? = nil
}

/// Слово предложения с подсказкой: t — как написано, h — перевод части, g — номер части (-1 — сама по себе).
struct HintWord: Codable, Hashable {
    var t: String
    var h: String
    var g: Int
}

struct SentencePair: Codable, Hashable {
    var sk: String
    var ru: String
    var skw: [HintWord]? = nil
    var ruw: [HintWord]? = nil
}

/// Предложение с пропуском: `text` содержит «___», `options` — только неверные варианты.
struct FillItem: Codable, Hashable {
    var text: String
    var answer: String
    var options: [String]
    var ru: String
    var tip: String? = nil
    var w: [HintWord]? = nil
}

struct Lesson: Codable, Identifiable, Hashable {
    var id: String
    var title: String
    var words: [WordPair]
    var sentences: [SentencePair]
    var fills: [FillItem]
    var review: Bool? = nil

    var isReview: Bool { review == true }
}

struct CourseUnit: Codable, Identifiable {
    var id: Int
    var level: String
    var title: String
    var subtitle: String
    var tip: String
    var lessons: [Lesson]
    /// Значок раздела и картинка-украшение для карты (эмодзи).
    var icon: String? = nil
    var art: String? = nil
    /// Номер на карте (по порядку); id не меняется, на нём держится прогресс.
    var number: Int? = nil

    var displayNumber: Int { number ?? id }
}

struct Course: Codable {
    var units: [CourseUnit]
    var dictSk: [String: String]?
    var dictRu: [String: String]?
}

/// Словарь форм — подсказки для предложений без готового разбора (уроки от ИИ).
enum HintDictionary {
    static var sk: [String: String] = [:]
    static var ru: [String: String] = [:]

    static func words(_ text: String, slovak: Bool) -> [HintWord] {
        let dict = slovak ? sk : ru
        return text.split(separator: " ").map { raw in
            let word = String(raw)
            let key = word.trimmingCharacters(in: ExerciseFactory.trimSet).lowercased()
            return HintWord(t: word, h: key.contains("___") ? "" : (dict[key] ?? ""), g: -1)
        }
    }
}

final class CourseStore: ObservableObject {
    let units: [CourseUnit]
    let allLessons: [Lesson]
    let allWords: [WordPair]

    init() {
        if let url = Bundle.main.url(forResource: "course", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let course = try? JSONDecoder().decode(Course.self, from: data) {
            units = course.units
            HintDictionary.sk = course.dictSk ?? [:]
            HintDictionary.ru = course.dictRu ?? [:]
        } else {
            units = []
        }
        allLessons = units.flatMap { $0.lessons }
        allWords = allLessons.filter { !$0.isReview }.flatMap { $0.words }
    }

    func unit(containing lessonID: String) -> CourseUnit? {
        units.first { unit in unit.lessons.contains { $0.id == lessonID } }
    }

    /// Первый непройденный урок — «текущий» на карте.
    func currentLessonID(completed: Set<String>) -> String? {
        allLessons.first { !completed.contains($0.id) }?.id
    }

    func isUnlocked(_ lessonID: String, completed: Set<String>, unlockAll: Bool) -> Bool {
        unlockAll || completed.contains(lessonID) || currentLessonID(completed: completed) == lessonID
    }

    /// Уровень CEFR, на котором сейчас ученик (по текущему уроку).
    func currentLevel(completed: Set<String>) -> String {
        guard let id = currentLessonID(completed: completed) else { return "B2" }
        return unit(containing: id)?.level ?? "A1"
    }
}
