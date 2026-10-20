import Foundation

struct WordPair: Codable, Hashable {
    var sk: String
    var ru: String
}

struct SentencePair: Codable, Hashable {
    var sk: String
    var ru: String
}

/// Предложение с пропуском: `text` содержит «___», `options` — только неверные варианты.
struct FillItem: Codable, Hashable {
    var text: String
    var answer: String
    var options: [String]
    var ru: String
}

struct Lesson: Codable, Identifiable, Hashable {
    var id: String
    var title: String
    var words: [WordPair]
    var sentences: [SentencePair]
    var fills: [FillItem]
}

struct CourseUnit: Codable, Identifiable {
    var id: Int
    var level: String
    var title: String
    var subtitle: String
    var tip: String
    var lessons: [Lesson]
}

struct Course: Codable {
    var units: [CourseUnit]
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
        } else {
            units = []
        }
        allLessons = units.flatMap { $0.lessons }
        allWords = allLessons.flatMap { $0.words }
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
