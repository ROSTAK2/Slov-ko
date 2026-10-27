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
    @Published var combo = 0
    var bestCombo = 0
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
        if exercise.kind == .speak {
            // Распознавание речи неточное: сердца не отнимаем и задание не повторяем.
            let outcome = Checker.speech(input, answer: exercise.answer)
            result = outcome
            if outcome == .wrong {
                completedCount += 1
                combo = 0
                Haptics.error()
                SoundFX.shared.play(.wrong)
            } else {
                registerCorrect()
            }
            return
        }
        let outcome = Checker.check(input, answer: exercise.answer, alternatives: exercise.alternatives)
        result = outcome
        if outcome == .wrong {
            mistakes += 1
            combo = 0
            Haptics.error()
            SoundFX.shared.play(.wrong)
            if usesHearts { store.loseHeart() }
            if let key = exercise.wordKey { store.markWeak(key) }
            queue.append(exercise)  // ошибку повторим в конце урока
        } else {
            registerCorrect()
        }
        if let say = exercise.speakAfter {
            // Сначала звук ответа, потом произношение.
            DispatchQueue.main.asyncAfter(deadline: .now() + (SoundFX.shared.enabled ? 0.45 : 0)) {
                Speech.shared.speak(say)
            }
        }
    }

    func matchCompleted() {
        guard result == nil else { return }
        result = .correct
        registerCorrect()
    }

    private func registerCorrect() {
        completedCount += 1
        combo += 1
        bestCombo = max(bestCombo, combo)
        Haptics.success()
        SoundFX.shared.play(isComboMilestone ? .combo : .correct)
    }

    /// 3, 5, 10, 15… правильных ответов подряд.
    var isComboMilestone: Bool {
        combo == 3 || combo == 5 || (combo >= 10 && combo % 5 == 0)
    }

    /// «Сейчас не могу говорить»: убираем упражнения на произношение на час.
    func skipSpeaking(store: ProgressStore) {
        guard position < queue.count else { return }
        let rest = queue[position...]
        completedCount += rest.filter { $0.kind == .speak }.count
        queue = Array(queue[..<position]) + rest.filter { $0.kind != .speak }
        store.state.speakingPausedUntil = Date().addingTimeInterval(3600)
        pending = nil
        result = nil
        step += 1
        if position >= queue.count {
            finished = true
        }
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
    @State private var heartHit = false
    @State private var lastHearts = Int.max
    @State private var showHearts = false

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
                    ZStack(alignment: .topLeading) {
                        exerciseView(exercise)
                            .padding(20)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .modifier(Shake(animatableData: CGFloat(session.mistakes)))
                            .animation(.linear(duration: 0.4), value: session.mistakes)
                            .id(session.step)
                            .transition(.asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .move(edge: .leading).combined(with: .opacity)))
                    }
                }
                .scrollDismissesKeyboard(.interactively)
                footer(exercise)
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .roundedDesign()
        .sheet(isPresented: $showHearts) {
            HeartsSheet().environmentObject(store)
        }
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
                        .fill(session.combo >= 3 ? Theme.orange : Theme.green)
                        .overlay(alignment: .top) {
                            // Блик на полосе прогресса.
                            Capsule()
                                .fill(Color.white.opacity(0.35))
                                .frame(height: 4)
                                .padding(.horizontal, 8)
                                .padding(.top, 3)
                        }
                        .frame(width: max(16, geo.size.width * session.progress))
                        .animation(.spring(response: 0.45, dampingFraction: 0.7), value: session.progress)
                }
            }
            .frame(height: 16)
            .overlay(alignment: .trailing) {
                if session.combo >= 3 {
                    Text(verbatim: "🔥\(session.combo)")
                        .font(.caption.weight(.heavy))
                        .foregroundColor(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Theme.orange))
                        .offset(y: -16)
                        .transition(.scale.combined(with: .opacity))
                        .id(session.combo)
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.5), value: session.combo)
            if session.usesHearts {
                HStack(spacing: 4) {
                    Image(systemName: "heart.fill")
                        .foregroundColor(Theme.red)
                        .scaleEffect(heartHit ? 1.5 : 1)
                        .rotationEffect(.degrees(heartHit ? -15 : 0))
                    Text(store.state.unlimitedHearts ? "∞" : "\(store.state.hearts)")
                        .font(.headline.weight(.heavy))
                        .foregroundColor(Theme.red)
                }
                .overlay(alignment: .top) {
                    if heartHit {
                        Text(verbatim: "−1")
                            .font(.caption.weight(.heavy))
                            .foregroundColor(Theme.red)
                            .offset(y: -18)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { showHearts = true }
                .onAppear { lastHearts = store.state.hearts }
                .onChange(of: store.state.hearts) { hearts in
                    if hearts < lastHearts {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.35)) { heartHit = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                            withAnimation(.easeOut(duration: 0.25)) { heartHit = false }
                        }
                    }
                    lastHearts = hearts
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private func exerciseView(_ exercise: Exercise) -> some View {
        let result = session.result
        switch exercise.kind {
        case .choice:
            ChoiceExerciseView(exercise: exercise, selection: $session.pending, result: result)
        case .match:
            MatchExerciseView(exercise: exercise) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { session.matchCompleted() }
            }
        case .build:
            BuildExerciseView(exercise: exercise, answer: $session.pending, result: result)
        case .typing:
            TypeExerciseView(exercise: exercise, answer: $session.pending, result: result) {
                guard session.pending != nil, session.result == nil else { return }
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    session.check(store: store)
                }
            }
        case .fill:
            FillExerciseView(exercise: exercise, selection: $session.pending, result: result)
        case .spot:
            SpotErrorView(exercise: exercise, selection: $session.pending, result: result)
        case .speak:
            SpeakExerciseView(exercise: exercise, answer: $session.pending, result: result) {
                withAnimation(.easeInOut(duration: 0.3)) {
                    session.skipSpeaking(store: store)
                }
            }
        }
    }

    @ViewBuilder
    private func footer(_ exercise: Exercise) -> some View {
        if let result = session.result {
            feedback(result, exercise: exercise)
        } else if exercise.kind != .match {
            Button("ПРОВЕРИТЬ") {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    session.check(store: store)
                }
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
            HStack(spacing: 10) {
                MascotReaction(positive: !isWrong)
                Text(title(for: result)).font(.title3.weight(.heavy))
                if !isWrong && session.combo >= 3 {
                    Text(verbatim: "🔥 \(session.combo) подряд")
                        .font(.subheadline.weight(.heavy))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Theme.orange))
                        .scaleEffect(session.isComboMilestone ? 1.1 : 1)
                }
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
            if result != .correct && (exercise.kind == .typing || exercise.kind == .build) {
                DiffAnswerView(user: session.lastAnswer, correct: exercise.answer,
                               byWords: exercise.kind == .build)
            }
            if exercise.kind == .speak && result != .correct && !session.lastAnswer.isEmpty {
                DiffAnswerView(user: session.lastAnswer, correct: exercise.answer, byWords: true)
            }
            if result != .correct || exercise.tipAlways, let tip = exercise.tip {
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
            if isWrong && exercise.kind != .typing && exercise.kind != .build && exercise.kind != .speak {
                Text("Правильный ответ:").font(.subheadline.weight(.bold)).foregroundColor(color)
                Text(exercise.speakAfter ?? exercise.answer).font(.body).foregroundColor(color)
            }
            if let note = exercise.note {
                Text(note).font(.subheadline).foregroundColor(color.opacity(0.85))
            }
            Button("ДАЛЕЕ") {
                withAnimation(.easeInOut(duration: 0.3)) {
                    session.next(store: store)
                }
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
    @State private var shown = false

    var body: some View {
        ZStack {
            VStack(spacing: 22) {
                Spacer()
                Text(session.mistakes == 0 ? "🏆" : "🎉")
                    .font(.system(size: 96))
                    .scaleEffect(shown ? 1 : 0.2)
                    .rotationEffect(.degrees(shown ? 0 : -30))
                    .animation(.spring(response: 0.5, dampingFraction: 0.5), value: shown)
                Text(headline)
                    .font(.largeTitle.weight(.heavy))
                    .multilineTextAlignment(.center)
                    .opacity(shown ? 1 : 0)
                    .animation(.easeOut(duration: 0.4).delay(0.15), value: shown)
                if session.kind == .practice {
                    Text("+1 ❤️").font(.title3.weight(.bold)).foregroundColor(Theme.red)
                }
                HStack(spacing: 12) {
                    statTile(title: "ОПЫТ", color: Theme.gold, index: 0) {
                        CountingText(value: shown ? Double(session.xpEarned) : 0, prefix: "+")
                            .animation(.easeOut(duration: 1.0).delay(0.4), value: shown)
                    }
                    statTile(title: "ТОЧНОСТЬ", color: Theme.green, index: 1) {
                        CountingText(value: shown ? Double(session.accuracy) : 0, suffix: "%")
                            .animation(.easeOut(duration: 1.0).delay(0.55), value: shown)
                    }
                    statTile(title: "ВРЕМЯ", color: Theme.blue, index: 2) {
                        Text(verbatim: elapsed)
                    }
                }
                .padding(.horizontal, 20)
                VStack(spacing: 6) {
                    Text(verbatim: "🔥 Серия: \(store.currentStreak) дн.")
                        .font(.headline)
                        .foregroundColor(Theme.orange)
                    if session.bestCombo >= 3 {
                        Text(verbatim: "Лучшая серия ответов: \(session.bestCombo) подряд")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .opacity(shown ? 1 : 0)
                .animation(.easeOut(duration: 0.4).delay(0.9), value: shown)
                Spacer()
                Button("ПРОДОЛЖИТЬ") { onDone() }
                    .buttonStyle(ChunkyButtonStyle(color: Theme.green))
                    .padding(20)
            }
            ConfettiView()
                .ignoresSafeArea()
        }
        .onAppear {
            reward()
            shown = true
        }
    }

    private var headline: String {
        if session.kind == .practice { return "Тренировка завершена!" }
        return session.mistakes == 0 ? "Без единой ошибки!" : "Урок пройден!"
    }

    private var elapsed: String {
        let seconds = Int(Date().timeIntervalSince(session.startedAt))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private func reward() {
        guard !session.rewarded else { return }
        session.rewarded = true
        Haptics.success()
        SoundFX.shared.play(.complete)
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

    private func statTile<Value: View>(title: String, color: Color, index: Int,
                                       @ViewBuilder value: () -> Value) -> some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.caption.weight(.heavy))
                .foregroundColor(.white)
                .padding(.vertical, 6)
            value()
                .font(.title3.weight(.heavy))
                .foregroundColor(color)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemBackground)))
                .padding(3)
        }
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 14).fill(color))
        .scaleEffect(shown ? 1 : 0.6)
        .opacity(shown ? 1 : 0)
        .animation(.spring(response: 0.45, dampingFraction: 0.6).delay(0.3 + Double(index) * 0.12), value: shown)
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
