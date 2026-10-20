import Foundation
import SwiftUI

/// Карточка для интервального повторения (упрощённый SM-2).
struct Card: Codable, Identifiable {
    var sk: String
    var ru: String
    var interval: Double   // в днях
    var ease: Double
    var due: Date
    var reps: Int
    var lapses: Int

    var id: String { sk }
}

struct AppState: Codable {
    var completedLessons: Set<String> = []
    var xpTotal: Int = 0
    var xpByDay: [String: Int] = [:]
    var streak: Int = 0
    var bestStreak: Int = 0
    var lastActiveDay: String? = nil
    var hearts: Int = ProgressStore.maxHearts
    var heartsUpdatedAt: Date = Date()
    var dailyGoal: Int = 20
    var reminderEnabled: Bool = false
    var reminderHour: Int = 19
    var reminderMinute: Int = 0
    var cards: [String: Card] = [:]
    var unlimitedHearts: Bool = false
    var unlockAll: Bool = false
    var onboarded: Bool = false
    var speechRate: Double = 0.45
    var tutorModel: String = "claude-opus-5-5"
    var soundsOn: Bool = true

    init() {}

    // Ручной декодер: новые поля в будущих версиях не сотрут старый прогресс.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppState()
        completedLessons = try c.decodeIfPresent(Set<String>.self, forKey: .completedLessons) ?? d.completedLessons
        xpTotal = try c.decodeIfPresent(Int.self, forKey: .xpTotal) ?? d.xpTotal
        xpByDay = try c.decodeIfPresent([String: Int].self, forKey: .xpByDay) ?? d.xpByDay
        streak = try c.decodeIfPresent(Int.self, forKey: .streak) ?? d.streak
        bestStreak = try c.decodeIfPresent(Int.self, forKey: .bestStreak) ?? d.bestStreak
        lastActiveDay = try c.decodeIfPresent(String.self, forKey: .lastActiveDay) ?? d.lastActiveDay
        hearts = try c.decodeIfPresent(Int.self, forKey: .hearts) ?? d.hearts
        heartsUpdatedAt = try c.decodeIfPresent(Date.self, forKey: .heartsUpdatedAt) ?? d.heartsUpdatedAt
        dailyGoal = try c.decodeIfPresent(Int.self, forKey: .dailyGoal) ?? d.dailyGoal
        reminderEnabled = try c.decodeIfPresent(Bool.self, forKey: .reminderEnabled) ?? d.reminderEnabled
        reminderHour = try c.decodeIfPresent(Int.self, forKey: .reminderHour) ?? d.reminderHour
        reminderMinute = try c.decodeIfPresent(Int.self, forKey: .reminderMinute) ?? d.reminderMinute
        cards = try c.decodeIfPresent([String: Card].self, forKey: .cards) ?? d.cards
        unlimitedHearts = try c.decodeIfPresent(Bool.self, forKey: .unlimitedHearts) ?? d.unlimitedHearts
        unlockAll = try c.decodeIfPresent(Bool.self, forKey: .unlockAll) ?? d.unlockAll
        onboarded = try c.decodeIfPresent(Bool.self, forKey: .onboarded) ?? d.onboarded
        speechRate = try c.decodeIfPresent(Double.self, forKey: .speechRate) ?? d.speechRate
        tutorModel = try c.decodeIfPresent(String.self, forKey: .tutorModel) ?? d.tutorModel
        soundsOn = try c.decodeIfPresent(Bool.self, forKey: .soundsOn) ?? d.soundsOn
    }
}

final class ProgressStore: ObservableObject {
    static let maxHearts = 5
    static let heartRefill: TimeInterval = 30 * 60

    @Published var state: AppState {
        didSet { save() }
    }

    private let storageKey = "slovicko.state.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode(AppState.self, from: data) {
            state = saved
        } else {
            state = AppState()
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    // MARK: - Дни и серия

    static func dayKey(_ date: Date = Date()) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func dayKey(daysAgo: Int) -> String {
        dayKey(Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date())
    }

    var currentStreak: Int {
        guard let last = state.lastActiveDay else { return 0 }
        return (last == Self.dayKey() || last == Self.dayKey(daysAgo: 1)) ? state.streak : 0
    }

    var practicedToday: Bool { state.lastActiveDay == Self.dayKey() }
    var xpToday: Int { state.xpByDay[Self.dayKey()] ?? 0 }

    func addXP(_ xp: Int) {
        let today = Self.dayKey()
        var s = state
        s.xpTotal += xp
        s.xpByDay[today, default: 0] += xp
        if s.lastActiveDay != today {
            s.streak = (s.lastActiveDay == Self.dayKey(daysAgo: 1)) ? s.streak + 1 : 1
            s.lastActiveDay = today
            s.bestStreak = max(s.bestStreak, s.streak)
        }
        state = s
        NotificationManager.shared.reschedule(for: self)
    }

    // MARK: - Сердца

    var hasHearts: Bool { state.unlimitedHearts || state.hearts > 0 }

    func refreshHearts() {
        guard state.hearts < Self.maxHearts else { return }
        let gained = Int(Date().timeIntervalSince(state.heartsUpdatedAt) / Self.heartRefill)
        guard gained > 0 else { return }
        var s = state
        s.hearts = min(Self.maxHearts, s.hearts + gained)
        s.heartsUpdatedAt = s.hearts >= Self.maxHearts
            ? Date()
            : s.heartsUpdatedAt.addingTimeInterval(Double(gained) * Self.heartRefill)
        state = s
    }

    /// Минут до следующего сердца (nil, если сердца полные).
    var minutesToNextHeart: Int? {
        guard state.hearts < Self.maxHearts else { return nil }
        let left = Self.heartRefill - Date().timeIntervalSince(state.heartsUpdatedAt)
        return max(1, Int((left / 60).rounded(.up)))
    }

    func loseHeart() {
        guard !state.unlimitedHearts else { return }
        var s = state
        if s.hearts >= Self.maxHearts { s.heartsUpdatedAt = Date() }
        s.hearts = max(0, s.hearts - 1)
        state = s
    }

    func gainHeart() {
        guard state.hearts < Self.maxHearts else { return }
        state.hearts += 1
    }

    // MARK: - Уроки

    func completeLesson(_ lesson: Lesson, xp: Int, markCompleted: Bool) {
        var s = state
        if markCompleted { s.completedLessons.insert(lesson.id) }
        let firstDue = Date().addingTimeInterval(12 * 3600)
        for w in lesson.words where s.cards[w.sk] == nil {
            s.cards[w.sk] = Card(sk: w.sk, ru: w.ru, interval: 0, ease: 2.5, due: firstDue, reps: 0, lapses: 0)
        }
        state = s
        addXP(xp)
    }

    // MARK: - Повторение

    var dueCards: [Card] {
        let now = Date()
        return state.cards.values.filter { $0.due <= now }.sorted { $0.due < $1.due }
    }

    var dueCount: Int {
        let now = Date()
        return state.cards.values.filter { $0.due <= now }.count
    }

    /// Ошибка в уроке — слово сразу попадает в повторение.
    func markWeak(_ sk: String) {
        guard var c = state.cards[sk] else { return }
        c.due = Date()
        c.ease = max(1.3, c.ease - 0.1)
        state.cards[sk] = c
    }

    /// grade: 0 — снова, 1 — трудно, 2 — хорошо, 3 — легко.
    func review(_ sk: String, grade: Int) {
        guard var c = state.cards[sk] else { return }
        let now = Date()
        switch grade {
        case 0:
            c.lapses += 1
            c.reps = 0
            c.interval = 0
            c.ease = max(1.3, c.ease - 0.2)
            c.due = now.addingTimeInterval(10 * 60)
        case 1:
            c.interval = max(1, c.interval * 1.2)
            c.ease = max(1.3, c.ease - 0.15)
        case 2:
            c.interval = c.reps == 0 ? 1 : (c.reps == 1 ? 3 : c.interval * c.ease)
        default:
            c.interval = c.reps == 0 ? 3 : max(4, c.interval * c.ease * 1.3)
            c.ease += 0.15
        }
        if grade > 0 {
            c.reps += 1
            c.due = now.addingTimeInterval(c.interval * 86_400)
        }
        state.cards[sk] = c
    }

    /// Слова для тренировки: сначала просроченные, потом самые «трудные», потом случайные.
    func practiceWords(limit: Int = 10) -> [WordPair] {
        var picked = dueCards.map { WordPair(sk: $0.sk, ru: $0.ru) }
        if picked.count < limit {
            let rest = state.cards.values
                .filter { c in !picked.contains { $0.sk == c.sk } }
                .sorted { ($0.lapses, -$0.ease) > ($1.lapses, -$1.ease) }
            picked += rest.prefix(limit - picked.count).map { WordPair(sk: $0.sk, ru: $0.ru) }
        }
        return Array(picked.prefix(limit))
    }

    // MARK: - Напоминания

    var reminderDate: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: self.state.reminderHour,
                                      minute: self.state.reminderMinute,
                                      second: 0, of: Date()) ?? Date()
            },
            set: { date in
                let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                var s = self.state
                s.reminderHour = c.hour ?? 19
                s.reminderMinute = c.minute ?? 0
                self.state = s
                NotificationManager.shared.reschedule(for: self)
            }
        )
    }

    func resetProgress() {
        var fresh = AppState()
        fresh.onboarded = true
        fresh.reminderEnabled = state.reminderEnabled
        fresh.reminderHour = state.reminderHour
        fresh.reminderMinute = state.reminderMinute
        fresh.tutorModel = state.tutorModel
        fresh.speechRate = state.speechRate
        fresh.soundsOn = state.soundsOn
        state = fresh
        NotificationManager.shared.reschedule(for: self)
    }
}
