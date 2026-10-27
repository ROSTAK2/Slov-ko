import SwiftUI

struct PracticeSet: Identifiable {
    let id = UUID()
    let lesson: Lesson
    let exercises: [Exercise]
}

struct ReviewView: View {
    @EnvironmentObject var store: ProgressStore
    @EnvironmentObject var course: CourseStore
    @State private var showCards = false
    @State private var practice: PracticeSet?
    @State private var showBlitz = false
    @State private var search = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 14) {
                            Text("🧠").font(.system(size: 44))
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(store.dueCount) слов ждут повторения")
                                    .font(.headline)
                                Text("Всего в словаре: \(store.state.cards.count)")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                        Button("ПОВТОРИТЬ КАРТОЧКИ") { showCards = true }
                            .buttonStyle(ChunkyButtonStyle())
                            .disabled(store.dueCount == 0)
                        Button("ТРЕНИРОВКА СЛОВ  +❤️") { startPractice() }
                            .buttonStyle(ChunkyButtonStyle(color: Theme.green))
                            .disabled(store.state.cards.count < 4)
                        Button(store.state.blitzBest > 0 ? "⚡ БЛИЦ 60 СЕКУНД · РЕКОРД \(store.state.blitzBest)" : "⚡ БЛИЦ 60 СЕКУНД") {
                            showBlitz = true
                        }
                        .buttonStyle(ChunkyButtonStyle(color: Theme.gold))
                        .disabled(store.state.cards.count < 4)
                        if store.state.cards.count < 4 {
                            Text("Пройдите первый урок — слова из уроков попадают сюда автоматически.")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 8)
                    .listRowSeparator(.hidden)
                }

                if !store.state.cards.isEmpty {
                    Section("Мой словарь") {
                        ForEach(filteredCards) { card in
                            HStack(spacing: 12) {
                                SpeakerButton(text: card.sk)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(card.sk).font(.body.weight(.semibold))
                                    Text(card.ru).font(.subheadline).foregroundColor(.secondary)
                                }
                                Spacer()
                                strength(card)
                            }
                        }
                    }
                }
            }
            .searchable(text: $search, prompt: "Поиск по словарю")
            .navigationTitle("Повторение")
            .fullScreenCover(isPresented: $showCards) {
                FlashcardSessionView()
            }
            .fullScreenCover(isPresented: $showBlitz) {
                BlitzView(words: store.state.cards.values.map { WordPair(sk: $0.sk, ru: $0.ru) },
                          pool: course.allWords)
                    .environmentObject(store)
            }
            .fullScreenCover(item: $practice) { set in
                LessonView(lesson: set.lesson, exercises: set.exercises, kind: .practice)
            }
        }
    }

    private var filteredCards: [Card] {
        let all = store.state.cards.values.sorted {
            $0.sk.compare($1.sk, locale: Locale(identifier: "sk_SK")) == .orderedAscending
        }
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return all }
        return all.filter { $0.sk.lowercased().contains(query) || $0.ru.lowercased().contains(query) }
    }

    /// Индикатор «силы» слова — от 0 до 4 делений.
    private func strength(_ card: Card) -> some View {
        let level = min(4, Int(card.interval.rounded(.up)) == 0 ? 0 : 1 + Int(log2(max(1, card.interval))))
        return HStack(spacing: 2) {
            ForEach(0..<4, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(i < level ? Theme.gold : Color(.systemGray5))
                    .frame(width: 5, height: 8 + CGFloat(i) * 3)
            }
        }
    }

    private func startPractice() {
        let words = store.practiceWords()
        guard words.count >= 4 else { return }
        let pool = store.state.cards.values.map { WordPair(sk: $0.sk, ru: $0.ru) } + course.allWords
        let done = store.state.completedLessons
        let sentences = course.allLessons
            .filter { done.contains($0.id) && !$0.isReview }
            .flatMap { $0.sentences }
        let lesson = Lesson(id: "practice", title: "Тренировка", words: words, sentences: [], fills: [])
        practice = PracticeSet(lesson: lesson,
                               exercises: ExerciseFactory.practice(words: words, pool: pool, sentences: sentences))
    }
}

struct FlashcardSessionView: View {
    @EnvironmentObject var store: ProgressStore
    @Environment(\.dismiss) private var dismiss
    @State private var queue: [Card] = []
    @State private var revealed = false
    @State private var reverse = false
    @State private var reviewed = 0
    @State private var loaded = false

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.title3.weight(.bold)).foregroundColor(.secondary)
                }
                Spacer()
                Text("Осталось: \(queue.count)").font(.headline).foregroundColor(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)

            if let card = queue.first {
                Spacer()
                VStack(spacing: 18) {
                    Text(reverse ? "Как по-словацки?" : "Что это значит?")
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(.secondary)
                    HStack(spacing: 12) {
                        if !reverse { SpeakerButton(text: card.sk) }
                        Text(reverse ? card.ru : card.sk)
                            .font(.largeTitle.weight(.heavy))
                            .multilineTextAlignment(.center)
                    }
                    if revealed {
                        Divider().padding(.horizontal, 40)
                        HStack(spacing: 12) {
                            if reverse { SpeakerButton(text: card.sk) }
                            Text(reverse ? card.sk : card.ru)
                                .font(.title.weight(.semibold))
                                .foregroundColor(Theme.blue)
                                .multilineTextAlignment(.center)
                        }
                    }
                }
                .padding(28)
                .frame(maxWidth: .infinity, minHeight: 280)
                .background(RoundedRectangle(cornerRadius: 24).fill(Color(.secondarySystemGroupedBackground)))
                .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color(.systemGray4), lineWidth: 2))
                .padding(.horizontal, 20)
                Spacer()
                if revealed {
                    HStack(spacing: 8) {
                        gradeButton("Снова", color: Theme.red, grade: 0)
                        gradeButton("Трудно", color: Theme.orange, grade: 1)
                        gradeButton("Хорошо", color: Theme.green, grade: 2)
                        gradeButton("Легко", color: Theme.blue, grade: 3)
                    }
                    .padding(20)
                } else {
                    Button("ПОКАЗАТЬ ОТВЕТ") {
                        revealed = true
                        if reverse { Speech.shared.speak(card.sk) }
                    }
                    .buttonStyle(ChunkyButtonStyle())
                    .padding(20)
                }
            } else if loaded {
                Spacer()
                Text("✅").font(.system(size: 80))
                Text(reviewed > 0 ? "Повторено слов: \(reviewed)" : "Пока нечего повторять")
                    .font(.title.weight(.heavy))
                Text("Карточки вернутся, когда настанет время их повторить.")
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
                Spacer()
                Button("ГОТОВО") { dismiss() }
                    .buttonStyle(ChunkyButtonStyle(color: Theme.green))
                    .padding(20)
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .onAppear {
            guard !loaded else { return }
            queue = Array(store.dueCards.prefix(30))
            loaded = true
            prepareCard()
        }
    }

    private func gradeButton(_ title: String, color: Color, grade: Int) -> some View {
        Button(title) { rate(grade) }
            .buttonStyle(ChunkyButtonStyle(color: color))
            .font(.subheadline)
    }

    private func rate(_ grade: Int) {
        guard !queue.isEmpty else { return }
        let card = queue.removeFirst()
        store.review(card.sk, grade: grade)
        reviewed += 1
        SoundFX.shared.play(grade == 0 ? .wrong : .pop)
        if grade == 0 {
            queue.append(card)
        }
        revealed = false
        if queue.isEmpty {
            store.addXP(min(20, max(5, reviewed)))
            Haptics.success()
            SoundFX.shared.play(.complete)
        } else {
            prepareCard()
        }
    }

    private func prepareCard() {
        reverse = Bool.random()
        if !reverse, let card = queue.first {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                Speech.shared.speak(card.sk)
            }
        }
    }
}
