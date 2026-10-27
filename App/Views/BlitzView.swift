import SwiftUI

/// «Блиц»: 60 секунд, как можно больше слов. Ошибка отнимает 3 секунды.
struct BlitzView: View {
    @EnvironmentObject var store: ProgressStore
    @Environment(\.dismiss) private var dismiss
    let words: [WordPair]
    let pool: [WordPair]

    private struct Question: Identifiable {
        let id = UUID()
        let word: WordPair
        let toSlovak: Bool
        let options: [String]
        let answer: String
    }

    private static let duration: Double = 60

    @State private var question: Question?
    @State private var score = 0
    @State private var streak = 0
    @State private var mistakes = 0
    @State private var timeLeft = BlitzView.duration
    @State private var started = false
    @State private var finished = false
    @State private var flash: Color = .clear
    @State private var newRecord = false
    @State private var shake: CGFloat = 0

    private let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            flash.opacity(0.18).ignoresSafeArea().allowsHitTesting(false)

            VStack(spacing: 20) {
                header
                if finished {
                    results
                } else if !started {
                    intro
                } else if let question {
                    questionView(question)
                        .id(question.id)
                        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                                 removal: .move(edge: .leading).combined(with: .opacity)))
                }
                Spacer(minLength: 0)
            }
            .padding(20)

            if finished && newRecord {
                ConfettiView().ignoresSafeArea()
            }
        }
        .roundedDesign()
        .onReceive(timer) { _ in
            guard started, !finished else { return }
            timeLeft -= 0.1
            if timeLeft <= 0 { finish() }
        }
    }

    // MARK: - Части

    private var header: some View {
        HStack(spacing: 14) {
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.title3.weight(.bold)).foregroundColor(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.systemGray5))
                    Capsule()
                        .fill(timeLeft < 10 ? Theme.red : Theme.gold)
                        .frame(width: geo.size.width * max(0, timeLeft) / Self.duration)
                        .animation(.linear(duration: 0.1), value: timeLeft)
                }
            }
            .frame(height: 14)
            Text(verbatim: "⚡\(score)")
                .font(.headline.weight(.heavy))
                .foregroundColor(Theme.gold)
                .contentTransition(.numericText())
        }
    }

    private var intro: some View {
        VStack(spacing: 18) {
            Spacer()
            Text("⚡").font(.system(size: 80)).floating()
            Text("Блиц").font(.largeTitle.weight(.black))
            Text("60 секунд. Переводите слова как можно быстрее.\nОшибка отнимает 3 секунды.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            if store.state.blitzBest > 0 {
                Text(verbatim: "Рекорд: \(store.state.blitzBest)")
                    .font(.headline)
                    .foregroundColor(Theme.gold)
            }
            Spacer()
            Button("СТАРТ") {
                started = true
                next()
            }
            .buttonStyle(ChunkyButtonStyle(color: Theme.gold))
        }
    }

    private func questionView(_ q: Question) -> some View {
        VStack(spacing: 24) {
            if streak >= 3 {
                Text(verbatim: "🔥 \(streak) подряд")
                    .font(.subheadline.weight(.heavy))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Theme.orange))
            }
            VStack(spacing: 10) {
                Text(q.toSlovak ? "Как по-словацки?" : "Что это значит?")
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(.secondary)
                Text(q.toSlovak ? q.word.ru : q.word.sk)
                    .font(.system(size: 38, weight: .heavy))
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.5)
            }
            .padding(.vertical, 26)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 24).fill(Color(.secondarySystemGroupedBackground)))
            .modifier(Shake(amount: 10, shakes: 3, animatableData: shake))

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(q.options, id: \.self) { option in
                    Button {
                        answer(option, for: q)
                    } label: {
                        Text(option)
                            .font(.body.weight(.semibold))
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.center)
                            .minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity, minHeight: 64)
                            .padding(.horizontal, 6)
                            .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemGroupedBackground)))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(.systemGray4), lineWidth: 2))
                    }
                    .buttonStyle(PressScale())
                }
            }
        }
        .onAppear {
            if !q.toSlovak { Speech.shared.speak(q.word.sk) }
        }
    }

    private var results: some View {
        VStack(spacing: 18) {
            Spacer()
            Text(newRecord ? "🏆" : "⏱").font(.system(size: 80))
            Text(newRecord ? "Новый рекорд!" : "Время вышло!")
                .font(.largeTitle.weight(.heavy))
            HStack(spacing: 30) {
                VStack {
                    Text(verbatim: "\(score)").font(.system(size: 44, weight: .black)).foregroundColor(Theme.gold)
                    Text("верных").font(.caption.weight(.bold)).foregroundColor(.secondary)
                }
                VStack {
                    Text(verbatim: "\(mistakes)").font(.system(size: 44, weight: .black)).foregroundColor(Theme.red)
                    Text("ошибок").font(.caption.weight(.bold)).foregroundColor(.secondary)
                }
            }
            Text(verbatim: "Рекорд: \(store.state.blitzBest) · +\(xp) XP")
                .font(.headline)
                .foregroundColor(.secondary)
            Spacer()
            Button("ЕЩЁ РАЗ") { restart() }
                .buttonStyle(ChunkyButtonStyle(color: Theme.gold))
            Button("ГОТОВО") { dismiss() }
                .buttonStyle(ChunkyButtonStyle(color: Theme.blue))
        }
    }

    // MARK: - Логика

    private var xp: Int { min(20, score) }

    private func next() {
        guard let word = words.randomElement() else { return }
        let toSlovak = Bool.random()
        let exercise = ExerciseFactory.choice(word, toSlovak: toSlovak, pool: pool.shuffled())
        withAnimation(.easeInOut(duration: 0.2)) {
            question = Question(word: word, toSlovak: toSlovak,
                                options: exercise.options, answer: exercise.answer)
        }
    }

    private func answer(_ option: String, for q: Question) {
        guard !finished else { return }
        if option == q.answer {
            score += 1
            streak += 1
            Haptics.tap()
            SoundFX.shared.play(streak > 0 && streak % 5 == 0 ? .combo : .pop)
            flashColor(Theme.green)
            if q.toSlovak { Speech.shared.speak(q.word.sk) }
            next()
        } else {
            mistakes += 1
            streak = 0
            timeLeft = max(0, timeLeft - 3)
            Haptics.error()
            SoundFX.shared.play(.wrong)
            flashColor(Theme.red)
            withAnimation(.linear(duration: 0.35)) { shake += 1 }
        }
    }

    private func flashColor(_ color: Color) {
        flash = color
        withAnimation(.easeOut(duration: 0.35)) { flash = .clear }
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        timeLeft = 0
        newRecord = score > store.state.blitzBest && score > 0
        if newRecord { store.state.blitzBest = score }
        if score > 0 { store.addXP(xp) }
        SoundFX.shared.play(.complete)
        Haptics.success()
    }

    private func restart() {
        score = 0
        streak = 0
        mistakes = 0
        timeLeft = Self.duration
        finished = false
        newRecord = false
        started = true
        next()
    }
}
