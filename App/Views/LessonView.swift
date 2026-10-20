import SwiftUI

enum LessonKind {
    case course     // урок с карты
    case practice   // тренировка слов (возвращает сердце)
    case ai         // урок, созданный репетитором
}

final class LessonSession: ObservableObject {
    let lesson: Lesson
    let kind: LessonKind
    let totalCount: Int
    let startedAt = Date()

    @Published var queue: [Exercise]
    @Published var position = 0
    @Published var step = 0
    @Published var pending: String? = nil
    @Published var result: CheckResult? = nil
    @Published var finished = false
    @Published var outOfHearts = false
    @Published var completedCount = 0
    var mistakes = 0
    var lastAnswer = ""
    var rewarded = false

    init(lesson: Lesson, exercises: [Exercise], kind: LessonKind) {
        self.lesson = lesson
        self.kind = kind
        self.queue = exercises
        self.totalCount = max(exercises.count, 1)
    }

    var current: Exercise? { position < queue.count ? queue[position] : nil }
    var progress: Double { Double(completedCount) / Double(totalCount) }
    var usesHearts: Bool { kind != .practice }

    var xpEarned: Int {
        switch kind {
        case .course, .ai: return 10 + (mistakes == 0 ? 5 : 0)
        case .practice: return 5
        }
    }

    var accuracy: Int {
        let attempts = totalCount + mistakes
        return Int((Double(totalCount) / Double(attempts) * 100).rounded())
    }

    func check(store: ProgressStore) {
        guard let exercise = current, let input = pending, result == nil else { return }
        lastAnswer = input
        let outcome = Checker.check(input, answer: exercise.answer, alternatives: exercise.alternatives)
        result = outcome
        if outcome == .wrong {
            mistakes += 1
            Haptics.error()
            if usesHearts { store.loseHeart() }
            if let key = exercise.wordKey { store.markWeak(key) }
            queue.append(exercise)  // ошибку повторим в конце урока
        } else {
            completedCount += 1
            Haptics.success()
        }
        if let say = exercise.speakAfter {
            Speech.shared.speak(say)
        }
    }

    func matchCompleted() {
        guard result == nil else { return }
        result = .correct
        completedCount += 1
        Haptics.success()
    }

    func next(store: ProgressStore) {
        if usesHearts && !store.hasHearts {
            outOfHearts = true
            return
        }
        position += 1
        step += 1
        pending = nil
        result = nil
        if position >= queue.count {
            finished = true
        }
    }
}

struct LessonView: View {
    @EnvironmentObject var store: ProgressStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var session: LessonSession
    @State private var confirmExit = false
    @State private var showExplain = false

    init(lesson: Lesson, exercises: [Exercise], kind: LessonKind) {
        _session = StateObject(wrappedValue: LessonSession(lesson: lesson, exercises: exercises, kind: kind))
    }

    var body: some View {
        VStack(spacing: 0) {
            if session.finished {
                LessonCompleteView(session: session) { dismiss() }
            } else if session.outOfHearts {
                outOfHeartsView
            } else if let exercise = session.current {
                header
                ScrollView {
                    exerciseView(exercise)
                        .id(session.step)
                        .padding(20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollDismissesKeyboard(.interactively)
                footer(exercise)
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .confirmationDialog("Закончить урок?", isPresented: $confirmExit, titleVisibility: .visible) {
            Button("Выйти", role: .destructive) { dismiss() }
            Button("Продолжить урок", role: .cancel) {}
        } message: {
            Text("Прогресс этого урока не сохранится.")
        }
        .sheet(isPresented: $showExplain) {
            if let exercise = session.current {
                ExplainSheet(exercise: exercise, userAnswer: session.lastAnswer)
            }
        }
    }

    // MARK: - Части экрана

    private var header: some View {
        HStack(spacing: 14) {
            Button {
                confirmExit = true
            } label: {
                Image(systemName: "xmark")
                    .font(.title3.weight(.bold))
                    .foregroundColor(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.systemGray5))
                    Capsule()
                        .fill(Theme.green)
                        .frame(width: max(16, geo.size.width * session.progress))
                        .animation(.spring(response: 0.4), value: session.progress)
                }
            }
            .frame(height: 16)
            if session.usesHearts {
                HStack(spacing: 4) {
                    Image(systemName: "heart.fill").foregroundColor(Theme.red)
                    Text(store.state.unlimitedHearts ? "∞" : "\(store.state.hearts)")
                        .font(.headline.weight(.heavy))
                        .foregroundColor(Theme.red)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private func exerciseView(_ exercise: Exercise) -> some View {
        let locked = session.result != nil
        switch exercise.kind {
        case .choice:
            ChoiceExerciseView(exercise: exercise, selection: $session.pending, locked: locked)
        case .match:
            MatchExerciseView(exercise: exercise) { session.matchCompleted() }
        case .build:
            BuildExerciseView(exercise: exercise, answer: $session.pending, locked: locked)
        case .typing:
            TypeExerciseView(exercise: exercise, answer: $session.pending, locked: locked)
        case .fill:
            FillExerciseView(exercise: exercise, selection: $session.pending, locked: locked)
        }
    }

    @ViewBuilder
    private func footer(_ exercise: Exercise) -> some View {
        if let result = session.result {
            feedback(result, exercise: exercise)
        } else if exercise.kind != .match {
            Button("ПРОВЕРИТЬ") {
                session.check(store: store)
            }
            .buttonStyle(ChunkyButtonStyle(color: Theme.green))
            .disabled(session.pending == nil)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
    }

    private func feedback(_ result: CheckResult, exercise: Exercise) -> some View {
        let isWrong = result == .wrong
        let color = isWrong ? Theme.red : Theme.green
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: isWrong ? "xmark.circle.fill" : "checkmark.circle.fill")
                Text(title(for: result)).font(.title3.weight(.heavy))
                Spacer()
                if isWrong && TutorClient.hasKey {
                    Button {
                        showExplain = true
                    } label: {
                        Label("Почему?", systemImage: "sparkles")
                            .font(.subheadline.weight(.bold))
                    }
                }
            }
            .foregroundColor(color)

            if case .almost(let hint) = result {
                Text(hint).font(.subheadline).foregroundColor(color)
            }
            if result != .correct, let tip = exercise.tip {
                HStack(alignment: .top, spacing: 8) {
                    Text("💡")
                    markdownText(tip)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(.systemBackground).opacity(0.8)))
            }
            if isWrong {
                Text("Правильный ответ:").font(.subheadline.weight(.bold)).foregroundColor(color)
                Text(exercise.speakAfter ?? exercise.answer).font(.body).foregroundColor(color)
            }
            if let note = exercise.note {
                Text(note).font(.subheadline).foregroundColor(color.opacity(0.85))
            }
            Button("ДАЛЕЕ") {
                session.next(store: store)
            }
            .buttonStyle(ChunkyButtonStyle(color: color))
            .padding(.top, 4)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.14).ignoresSafeArea(edges: .bottom))
        .transition(.move(edge: .bottom))
    }

    private func title(for result: CheckResult) -> String {
        switch result {
        case .correct:
            let praise = ["Отлично!", "Výborne!", "Super!", "Správne!", "Молодец!"]
            return praise[session.step % praise.count]
        case .almost: return "Почти правильно"
        case .wrong: return "Неправильно"
        }
    }

    private var outOfHeartsView: some View {
        VStack(spacing: 20) {
            Spacer()
            Text("💔").font(.system(size: 80))
            Text("Сердца закончились").font(.title.weight(.heavy))
            Group {
                if let minutes = store.minutesToNextHeart {
                    Text("Новое сердце через \(minutes) мин. Или пройдите тренировку во вкладке «Повтор» — она вернёт сердце.")
                } else {
                    Text("Пройдите тренировку во вкладке «Повтор», чтобы вернуть сердце.")
                }
            }
            .multilineTextAlignment(.center)
            .foregroundColor(.secondary)
            .padding(.horizontal, 30)
            Spacer()
            Button("ПОНЯТНО") { dismiss() }
                .buttonStyle(ChunkyButtonStyle())
                .padding(20)
        }
    }
}

// MARK: - Финиш

struct LessonCompleteView: View {
    @EnvironmentObject var store: ProgressStore
    @ObservedObject var session: LessonSession
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Text(session.mistakes == 0 ? "🏆" : "🎉").font(.system(size: 90))
            Text(session.kind == .practice ? "Тренировка завершена!" : "Урок пройден!")
                .font(.largeTitle.weight(.heavy))
                .multilineTextAlignment(.center)
            if session.kind == .practice {
                Text("+1 ❤️").font(.title3.weight(.bold)).foregroundColor(Theme.red)
            }
            HStack(spacing: 12) {
                stat(title: "ОПЫТ", value: "+\(session.xpEarned)", color: Theme.gold)
                stat(title: "ТОЧНОСТЬ", value: "\(session.accuracy)%", color: Theme.green)
                stat(title: "ВРЕМЯ", value: elapsed, color: Theme.blue)
            }
            .padding(.horizontal, 20)
            Text("🔥 Серия: \(store.currentStreak) дн.")
                .font(.headline)
                .foregroundColor(Theme.orange)
            Spacer()
            Button("ПРОДОЛЖИТЬ") { onDone() }
                .buttonStyle(ChunkyButtonStyle(color: Theme.green))
                .padding(20)
        }
        .onAppear(perform: reward)
    }

    private var elapsed: String {
        let seconds = Int(Date().timeIntervalSince(session.startedAt))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private func reward() {
        guard !session.rewarded else { return }
        session.rewarded = true
        Haptics.success()
        switch session.kind {
        case .course:
            store.completeLesson(session.lesson, xp: session.xpEarned, markCompleted: true)
        case .ai:
            store.completeLesson(session.lesson, xp: session.xpEarned, markCompleted: false)
        case .practice:
            store.gainHeart()
            store.addXP(session.xpEarned)
        }
    }

    private func stat(title: String, value: String, color: Color) -> some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.caption.weight(.heavy))
                .foregroundColor(.white)
                .padding(.vertical, 6)
            Text(value)
                .font(.title3.weight(.heavy))
                .foregroundColor(color)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemBackground)))
                .padding(3)
        }
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 14).fill(color))
    }
}

// MARK: - «Почему?» от репетитора

struct ExplainSheet: View {
    @EnvironmentObject var store: ProgressStore
    @Environment(\.dismiss) private var dismiss
    let exercise: Exercise
    let userAnswer: String
    @State private var text: String?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let text {
                        ForEach(Array(text.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                            markdownText(line)
                        }
                    } else if let error {
                        Text(error).foregroundColor(Theme.red)
                    } else {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Репетитор думает…").foregroundColor(.secondary)
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("Разбор ошибки")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
        }
        .task {
            do {
                text = try await TutorClient.explainMistake(model: store.state.tutorModel,
                                                           exercise: exercise, userAnswer: userAnswer)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
