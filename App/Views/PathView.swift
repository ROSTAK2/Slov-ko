import SwiftUI

/// Панель сверху: уровень, серия, кольцо дневной цели, сердца.
struct StatsBar: View {
    @EnvironmentObject var store: ProgressStore
    @EnvironmentObject var course: CourseStore

    var body: some View {
        let progress = min(1, Double(store.xpToday) / Double(max(store.state.dailyGoal, 1)))
        let goalDone = progress >= 1
        HStack {
            HStack(spacing: 5) {
                Text("🇸🇰")
                Text(course.currentLevel(completed: store.state.completedLessons))
                    .font(.subheadline.weight(.black))
                    .foregroundColor(Theme.blue)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(Theme.blue.opacity(0.12)))
            Spacer()
            HStack(spacing: 4) {
                Image(systemName: "flame.fill")
                Text("\(store.currentStreak)")
            }
            .foregroundColor(store.practicedToday ? Theme.orange : Color(.systemGray3))
            Spacer()
            HStack(spacing: 6) {
                ZStack {
                    Circle().stroke(Color(.systemGray5), lineWidth: 4)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(goalDone ? Theme.gold : Theme.blue, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 11, weight: .heavy))
                }
                .frame(width: 26, height: 26)
                .animation(.spring(response: 0.6), value: progress)
                Text("\(store.xpToday)/\(store.state.dailyGoal)")
            }
            .foregroundColor(goalDone ? Theme.gold : Theme.blue)
            Spacer()
            Label(store.state.unlimitedHearts ? "∞" : "\(store.state.hearts)", systemImage: "heart.fill")
                .foregroundColor(Theme.red)
        }
        .font(.headline.weight(.heavy))
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
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
                    ForEach(Array(course.units.enumerated()), id: \.element.id) { unitIndex, unit in
                        if unitIndex == 0 || course.units[unitIndex - 1].level != unit.level {
                            LevelDivider(level: unit.level)
                                .padding(.top, unitIndex == 0 ? 16 : 36)
                        }
                        UnitHeader(unit: unit, done: doneCount(unit)) { guideUnit = unit }
                            .padding(.horizontal, 16)
                            .padding(.top, 20)
                            .padding(.bottom, 18)
                        ForEach(Array(unit.lessons.enumerated()), id: \.element.id) { index, lesson in
                            let swing = zigzag(index) * (unit.id.isMultiple(of: 2) ? -1 : 1)
                            ZStack {
                                if index == 1, let art = unit.art {
                                    UnitArt(art: art, color: Theme.unitColor(unit.id))
                                        .offset(x: swing > 0 ? -110 : 110, y: 44)
                                }
                                LessonNode(
                                    lesson: lesson,
                                    color: Theme.unitColor(unit.id),
                                    status: status(of: lesson, current: current)
                                ) {
                                    open(lesson)
                                }
                                .offset(x: swing)
                            }
                            .padding(.vertical, 10)
                            .id(lesson.id)
                        }
                    }
                    if current == nil && !course.units.isEmpty {
                        VStack(spacing: 8) {
                            Text("🏆").font(.system(size: 60)).floating()
                            Text("Весь курс пройден!").font(.title2.weight(.heavy))
                            Text("Дальше — разговорная практика и уроки от репетитора.")
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(30)
                    }
                    Color.clear.frame(height: 80)
                }
            }
            .background(Color(.systemGroupedBackground))
            .safeAreaInset(edge: .top, spacing: 0) { StatsBar() }
            .overlay(alignment: .bottomTrailing) {
                if let current {
                    Button {
                        Haptics.tap()
                        withAnimation(.easeInOut(duration: 0.5)) {
                            proxy.scrollTo(current, anchor: .center)
                        }
                    } label: {
                        Image(systemName: "location.fill")
                            .font(.system(size: 18, weight: .heavy))
                            .foregroundColor(Theme.blue)
                            .frame(width: 50, height: 50)
                            .background(Circle().fill(Color(.systemBackground)))
                            .overlay(Circle().stroke(Color(.systemGray4), lineWidth: 2))
                            .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
                    }
                    .buttonStyle(PressScale())
                    .padding(16)
                    .accessibilityLabel("К текущему уроку")
                }
            }
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

    private func doneCount(_ unit: CourseUnit) -> Int {
        unit.lessons.filter { store.state.completedLessons.contains($0.id) }.count
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
        SoundFX.shared.play(.pop)
        activeLesson = lesson
    }

    private func exercises(for lesson: Lesson) -> [Exercise] {
        let unit = course.unit(containing: lesson.id)
        return ExerciseFactory.make(
            lesson: lesson,
            unitWords: unit?.lessons.filter { !$0.isReview }.flatMap { $0.words } ?? [],
            allWords: course.allWords,
            unitSentences: unit?.lessons.filter { !$0.isReview }.flatMap { $0.sentences } ?? [],
            known: Set(store.state.cards.keys)
        )
    }

    private func zigzag(_ index: Int) -> CGFloat {
        let pattern: [CGFloat] = [0, 55, 85, 55, 0, -55, -85, -55]
        return pattern[index % pattern.count]
    }
}

/// Разделитель уровней: ★ —— A2 · ЭЛЕМЕНТАРНЫЙ УРОВЕНЬ —— ★
struct LevelDivider: View {
    let level: String

    var body: some View {
        HStack(spacing: 10) {
            line
            VStack(spacing: 2) {
                Text(level)
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .foregroundColor(Theme.blue)
                Text(LevelInfo.title(level).uppercased())
                    .font(.caption2.weight(.heavy))
                    .foregroundColor(.secondary)
                    .fixedSize()
            }
            line
        }
        .padding(.horizontal, 24)
    }

    private var line: some View {
        HStack(spacing: 6) {
            Image(systemName: "star.fill")
                .font(.system(size: 9))
                .foregroundColor(Theme.gold)
            Capsule()
                .fill(Color(.systemGray4))
                .frame(height: 3)
            Image(systemName: "star.fill")
                .font(.system(size: 9))
                .foregroundColor(Theme.gold)
        }
    }
}

/// Картинка-украшение раздела рядом с тропинкой.
struct UnitArt: View {
    let art: String
    let color: Color

    var body: some View {
        Text(art)
            .font(.system(size: 52))
            .frame(width: 104, height: 104)
            .background(Circle().fill(color.opacity(0.13)))
            .overlay(Circle().stroke(color.opacity(0.3), style: StrokeStyle(lineWidth: 2, dash: [4, 6])))
            .floating()
            .allowsHitTesting(false)
    }
}

struct UnitHeader: View {
    let unit: CourseUnit
    let done: Int
    let onGuide: () -> Void

    var body: some View {
        let total = max(unit.lessons.count, 1)
        let color = Theme.unitColor(unit.id)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                if let icon = unit.icon {
                    Text(icon)
                        .font(.system(size: 28))
                        .frame(width: 50, height: 50)
                        .background(Circle().fill(Color.white.opacity(0.22)))
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("РАЗДЕЛ \(unit.id) · \(unit.level)")
                        .font(.caption.weight(.heavy))
                        .foregroundColor(.white.opacity(0.85))
                    Text(unit.title)
                        .font(.title3.weight(.heavy))
                        .foregroundColor(.white)
                    Text(unit.subtitle)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
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
                .buttonStyle(PressScale())
            }
            HStack(spacing: 8) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.25))
                        Capsule()
                            .fill(Color.white)
                            .frame(width: geo.size.width * CGFloat(done) / CGFloat(total))
                    }
                }
                .frame(height: 8)
                Text(done >= total ? "✓ пройден" : "\(done)/\(total)")
                    .font(.caption.weight(.heavy))
                    .foregroundColor(.white)
                    .fixedSize()
            }
        }
        .padding(16)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .fill(color)
                    .overlay(RoundedRectangle(cornerRadius: 18).fill(Color.black.opacity(0.2)))
                    .offset(y: 4)
                RoundedRectangle(cornerRadius: 18)
                    .fill(LinearGradient(colors: [color.opacity(0.85), color], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(alignment: .bottomTrailing) {
                        // Большая полупрозрачная картинка раздела в углу.
                        Text(unit.art ?? "")
                            .font(.system(size: 96))
                            .opacity(0.16)
                            .rotationEffect(.degrees(-14))
                            .offset(x: 18, y: 26)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 18))
            }
        )
    }
}

/// Круглая «объёмная» кнопка урока: при нажатии верх опускается на подложку.
struct NodeButtonStyle: ButtonStyle {
    let fill: Color

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        ZStack {
            Circle()
                .fill(fill)
                .overlay(Circle().fill(Color.black.opacity(0.22)))
                .offset(y: 6)
            Circle()
                .fill(fill)
                .overlay(
                    Circle()
                        .fill(LinearGradient(colors: [Color.white.opacity(0.3), .clear],
                                             startPoint: .top, endPoint: .center))
                        .padding(5)
                )
                .offset(y: pressed ? 6 : 0)
            configuration.label
                .offset(y: pressed ? 6 : 0)
        }
        .frame(width: 74, height: 70)
        .animation(.easeOut(duration: 0.08), value: pressed)
    }
}

struct LessonNode: View {
    enum Status { case done, current, open, locked }

    let lesson: Lesson
    let color: Color
    let status: Status
    let onTap: () -> Void
    @State private var bounce = false
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 6) {
            if status == .current {
                Text(lesson.isReview ? "ПОВТОРИТЬ" : "НАЧАТЬ")
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
                Image(systemName: icon)
                    .font(.system(size: 28, weight: .heavy))
                    .foregroundColor(status == .locked ? Color(.systemGray) : .white)
            }
            .buttonStyle(NodeButtonStyle(fill: fill))
            .background(
                ZStack {
                    if status == .current {
                        Circle()
                            .stroke(color.opacity(0.3), lineWidth: 8)
                            .frame(width: 94, height: 94)
                        Circle()
                            .stroke(color.opacity(pulse ? 0 : 0.5), lineWidth: 5)
                            .frame(width: 94, height: 94)
                            .scaleEffect(pulse ? 1.35 : 1)
                            .animation(.easeOut(duration: 1.6).repeatForever(autoreverses: false), value: pulse)
                            .onAppear { pulse = true }
                    }
                }
                .offset(y: 3)
                .allowsHitTesting(false)
            )
            Text(lesson.title)
                .font(.caption.weight(.semibold))
                .foregroundColor(status == .locked ? .secondary : (status == .done ? Theme.gold : .primary))
                .lineLimit(1)
                .padding(.top, 8)
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
        case .done: return lesson.isReview ? "crown.fill" : "checkmark"
        case .current: return lesson.isReview ? "dumbbell.fill" : "star.fill"
        case .open: return lesson.isReview ? "dumbbell.fill" : "play.fill"
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
                    ForEach(unit.lessons.filter { !$0.isReview }) { lesson in
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
