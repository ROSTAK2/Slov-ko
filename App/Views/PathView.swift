import SwiftUI

/// Панель сверху: серия, опыт за день, сердца.
struct StatsBar: View {
    @EnvironmentObject var store: ProgressStore

    var body: some View {
        HStack {
            Text("🇸🇰").font(.title2)
            Spacer()
            Label("\(store.currentStreak)", systemImage: "flame.fill")
                .foregroundColor(store.practicedToday ? Theme.orange : Color(.systemGray3))
            Spacer()
            Label("\(store.xpToday)/\(store.state.dailyGoal)", systemImage: "bolt.fill")
                .foregroundColor(store.xpToday >= store.state.dailyGoal ? Theme.gold : Theme.blue)
            Spacer()
            Label(store.state.unlimitedHearts ? "∞" : "\(store.state.hearts)", systemImage: "heart.fill")
                .foregroundColor(Theme.red)
        }
        .font(.headline.weight(.heavy))
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.bar)
    }
}

struct PathView: View {
    @EnvironmentObject var store: ProgressStore
    @EnvironmentObject var course: CourseStore
    @State private var activeLesson: Lesson?
    @State private var guideUnit: CourseUnit?
    @State private var noHeartsAlert = false

    var body: some View {
        let current = course.currentLessonID(completed: store.state.completedLessons)
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    if course.units.isEmpty {
                        Text("Курс не найден в приложении.").padding(40)
                    }
                    ForEach(course.units) { unit in
                        UnitHeader(unit: unit) { guideUnit = unit }
                            .padding(.horizontal, 16)
                            .padding(.top, 24)
                            .padding(.bottom, 18)
                        ForEach(Array(unit.lessons.enumerated()), id: \.element.id) { index, lesson in
                            LessonNode(
                                lesson: lesson,
                                color: Theme.unitColor(unit.id),
                                status: status(of: lesson, current: current)
                            ) {
                                open(lesson)
                            }
                            .offset(x: zigzag(index))
                            .padding(.vertical, 10)
                            .id(lesson.id)
                        }
                    }
                    if current == nil && !course.units.isEmpty {
                        VStack(spacing: 8) {
                            Text("🏆").font(.system(size: 60))
                            Text("Весь курс пройден!").font(.title2.weight(.heavy))
                            Text("Дальше — разговорная практика и уроки от репетитора.")
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(30)
                    }
                    Color.clear.frame(height: 40)
                }
            }
            .background(Color(.systemGroupedBackground))
            .safeAreaInset(edge: .top, spacing: 0) { StatsBar() }
            .onAppear {
                store.refreshHearts()
                if let current {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        proxy.scrollTo(current, anchor: .center)
                    }
                }
            }
        }
        .fullScreenCover(item: $activeLesson) { lesson in
            LessonView(lesson: lesson, exercises: exercises(for: lesson), kind: .course)
                .environmentObject(store)
        }
        .sheet(item: $guideUnit) { unit in
            GuideView(unit: unit)
        }
        .alert("Сердца закончились", isPresented: $noHeartsAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(noHeartsMessage)
        }
    }

    private var noHeartsMessage: String {
        if let minutes = store.minutesToNextHeart {
            return "Новое сердце через \(minutes) мин. Тренировка во вкладке «Повтор» вернёт сердце сразу."
        }
        return "Пройдите тренировку во вкладке «Повтор»."
    }

    private func status(of lesson: Lesson, current: String?) -> LessonNode.Status {
        if store.state.completedLessons.contains(lesson.id) { return .done }
        if lesson.id == current { return .current }
        return store.state.unlockAll ? .open : .locked
    }

    private func open(_ lesson: Lesson) {
        guard course.isUnlocked(lesson.id, completed: store.state.completedLessons, unlockAll: store.state.unlockAll) else {
            Haptics.error()
            return
        }
        store.refreshHearts()
        guard store.hasHearts else {
            noHeartsAlert = true
            return
        }
        activeLesson = lesson
    }

    private func exercises(for lesson: Lesson) -> [Exercise] {
        let unit = course.unit(containing: lesson.id)
        return ExerciseFactory.make(
            lesson: lesson,
            unitWords: unit?.lessons.flatMap { $0.words } ?? [],
            allWords: course.allWords,
            unitSentences: unit?.lessons.flatMap { $0.sentences } ?? []
        )
    }

    private func zigzag(_ index: Int) -> CGFloat {
        let pattern: [CGFloat] = [0, 55, 85, 55, 0, -55, -85, -55]
        return pattern[index % pattern.count]
    }
}

struct UnitHeader: View {
    let unit: CourseUnit
    let onGuide: () -> Void

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("РАЗДЕЛ \(unit.id) · \(unit.level)")
                    .font(.caption.weight(.heavy))
                    .foregroundColor(.white.opacity(0.85))
                Text(unit.title)
                    .font(.title3.weight(.heavy))
                    .foregroundColor(.white)
                Text(unit.subtitle)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.9))
            }
            Spacer(minLength: 8)
            Button(action: onGuide) {
                VStack(spacing: 2) {
                    Image(systemName: "book.fill").font(.title3)
                    Text("Теория").font(.caption2.weight(.bold))
                }
                .foregroundColor(.white)
                .frame(width: 62, height: 56)
                .background(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.5), lineWidth: 2))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 18).fill(Theme.unitColor(unit.id))
                    .overlay(RoundedRectangle(cornerRadius: 18).fill(Color.black.opacity(0.2)))
                    .offset(y: 4)
                RoundedRectangle(cornerRadius: 18).fill(Theme.unitColor(unit.id))
            }
        )
    }
}

struct LessonNode: View {
    enum Status { case done, current, open, locked }

    let lesson: Lesson
    let color: Color
    let status: Status
    let onTap: () -> Void
    @State private var bounce = false

    var body: some View {
        VStack(spacing: 6) {
            if status == .current {
                Text("НАЧАТЬ")
                    .font(.caption.weight(.heavy))
                    .foregroundColor(color)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(.systemBackground)))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(.systemGray4), lineWidth: 2))
                    .offset(y: bounce ? -4 : 2)
                    .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: bounce)
                    .onAppear { bounce = true }
            }
            Button(action: onTap) {
                ZStack {
                    Circle()
                        .fill(fill)
                        .overlay(Circle().fill(Color.black.opacity(0.22)))
                        .offset(y: 6)
                    Circle().fill(fill)
                    Image(systemName: icon)
                        .font(.system(size: 28, weight: .heavy))
                        .foregroundColor(status == .locked ? Color(.systemGray) : .white)
                }
                .frame(width: 74, height: 70)
                .overlay(
                    Circle()
                        .stroke(status == .current ? color.opacity(0.35) : .clear, lineWidth: 8)
                        .frame(width: 92, height: 92)
                )
            }
            .buttonStyle(.plain)
            Text(lesson.title)
                .font(.caption.weight(.semibold))
                .foregroundColor(status == .locked ? .secondary : .primary)
                .lineLimit(1)
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
    }

    private var fill: Color {
        switch status {
        case .locked: return Theme.locked
        case .done: return Theme.gold
        default: return color
        }
    }

    private var icon: String {
        switch status {
        case .done: return "checkmark"
        case .current: return "star.fill"
        case .open: return "play.fill"
        case .locked: return "lock.fill"
        }
    }
}

struct GuideView: View {
    @Environment(\.dismiss) private var dismiss
    let unit: CourseUnit

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Раздел \(unit.id) · \(unit.level)")
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(Theme.unitColor(unit.id))
                    Text(unit.title).font(.largeTitle.weight(.heavy))
                    Text(unit.subtitle).foregroundColor(.secondary)

                    ForEach(Array(unit.tip.components(separatedBy: "\n\n").enumerated()), id: \.offset) { _, paragraph in
                        markdownText(paragraph)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Text("Слова раздела")
                        .font(.title2.weight(.heavy))
                        .padding(.top, 10)
                    ForEach(unit.lessons) { lesson in
                        Text(lesson.title)
                            .font(.headline)
                            .foregroundColor(Theme.unitColor(unit.id))
                            .padding(.top, 6)
                        ForEach(lesson.words, id: \.sk) { word in
                            HStack(spacing: 12) {
                                SpeakerButton(text: word.sk)
                                Text(word.sk).font(.body.weight(.semibold))
                                Spacer()
                                Text(word.ru)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.trailing)
                            }
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
        }
    }
}
