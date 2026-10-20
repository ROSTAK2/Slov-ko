import SwiftUI

struct Scenario: Identifiable, Hashable {
    let id: String
    let emoji: String
    let title: String
    let details: String
    let brief: String   // описание роли для модели
}

enum Scenarios {
    static let all: [Scenario] = [
        Scenario(id: "free", emoji: "💬", title: "Свободный разговор",
                 details: "Болтаем о чём угодно: о вас, планах, переезде",
                 brief: "Свободная беседа. Ты — дружелюбный словак-собеседник. Расспрашивай ученика о жизни, работе, планах переезда."),
        Scenario(id: "interview", emoji: "💼", title: "Собеседование",
                 details: "HR-менеджер словацкой компании задаёт вопросы",
                 brief: "Ролевая игра: ты HR-менеджер словацкой IT-компании в Братиславе и проводишь собеседование с учеником. Задавай типичные вопросы по одному."),
        Scenario(id: "colleague", emoji: "☕️", title: "Коллега на кухне",
                 details: "Small talk с коллегой в офисе",
                 brief: "Ролевая игра: ты коллега ученика в офисе, вы встретились на кухне у кофемашины. Лёгкий small talk."),
        Scenario(id: "meeting", emoji: "📊", title: "Совещание",
                 details: "Обсуждаем проект, сроки и задачи",
                 brief: "Ролевая игра: ты руководитель проекта на рабочем совещании. Обсуждайте задачи, сроки и проблемы проекта; проси ученика высказать мнение."),
        Scenario(id: "university", emoji: "🎓", title: "Учебный отдел",
                 details: "Запись в университет, документы, расписание",
                 brief: "Ролевая игра: ты сотрудница учебного отдела (študijné oddelenie) словацкого университета. Ученик приходит по вопросам зачисления, документов и расписания."),
        Scenario(id: "landlord", emoji: "🏠", title: "Аренда квартиры",
                 details: "Звонок арендодателю, осмотр, договор",
                 brief: "Ролевая игра: ты арендодатель квартиры в Братиславе. Ученик звонит по объявлению: обсуждайте цену, залог, коммунальные платежи, осмотр."),
        Scenario(id: "office", emoji: "🛂", title: "Иностранная полиция",
                 details: "ВНЖ, документы, запись на приём",
                 brief: "Ролевая игра: ты сотрудник отдела иностранной полиции (cudzinecká polícia). Ученик подаёт документы на временный вид на жительство для работы."),
        Scenario(id: "doctor", emoji: "🩺", title: "У врача",
                 details: "Описать симптомы, получить рецепт",
                 brief: "Ролевая игра: ты всеобщий врач (všeobecný lekár). Ученик пришёл с жалобами; расспроси о симптомах.")
    ]
}

struct TutorView: View {
    @EnvironmentObject var store: ProgressStore
    @EnvironmentObject var course: CourseStore
    @State private var hasKey = TutorClient.hasKey
    @State private var topic = ""
    @State private var level = ""
    @State private var generating = false
    @State private var generateError: String?
    @State private var generated: PracticeSet?

    private let suggestedTopics = [
        "Собеседование на позицию программиста",
        "Общение с HR и трудовой договор",
        "Рабочая переписка по e-mail",
        "Зачисление в университет",
        "Аренда квартиры",
        "Налоги и зарплата в Словакии",
        "Споры на совещании",
        "Визит к врачу"
    ]

    var body: some View {
        NavigationStack {
            Group {
                if hasKey {
                    content
                } else {
                    noKey
                }
            }
            .navigationTitle("Репетитор")
            .onAppear {
                hasKey = TutorClient.hasKey
                if level.isEmpty { level = course.currentLevel(completed: store.state.completedLessons) }
            }
            .fullScreenCover(item: $generated) { set in
                LessonView(lesson: set.lesson, exercises: set.exercises, kind: .ai)
            }
        }
    }

    private var content: some View {
        List {
            Section {
                ForEach(Scenarios.all) { scenario in
                    NavigationLink {
                        ChatView(scenario: scenario, level: level)
                    } label: {
                        HStack(spacing: 14) {
                            Text(scenario.emoji).font(.title)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(scenario.title).font(.headline)
                                Text(scenario.details).font(.subheadline).foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            } header: {
                Text("Разговорная практика")
            } footer: {
                Text("Репетитор говорит по-словацки на вашем уровне (\(level)), переводит свои реплики и исправляет ваши ошибки по-русски.")
            }

            Section {
                Picker("Уровень", selection: $level) {
                    ForEach(["A1", "A2", "B1", "B2", "C1"], id: \.self) { Text($0).tag($0) }
                }
                TextField("Тема урока, например: «переговоры о зарплате»", text: $topic, axis: .vertical)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(suggestedTopics, id: \.self) { suggestion in
                            Button(suggestion) { topic = suggestion }
                                .font(.footnote.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Capsule().fill(Theme.blue.opacity(0.12)))
                                .foregroundColor(Theme.blue)
                                .buttonStyle(.plain)
                        }
                    }
                }
                if generating {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Составляю урок… (до минуты)").foregroundColor(.secondary)
                    }
                } else {
                    Button("СОЗДАТЬ УРОК") { generate() }
                        .buttonStyle(ChunkyButtonStyle(color: Theme.green))
                        .disabled(topic.trimmingCharacters(in: .whitespaces).isEmpty)
                        .listRowSeparator(.hidden)
                }
                if let generateError {
                    Text(generateError).font(.footnote).foregroundColor(Theme.red)
                }
            } header: {
                Text("Новый урок на любую тему")
            } footer: {
                Text("Бесконечная практика: ИИ составит урок со словами, предложениями и грамматикой по вашей теме.")
            }
        }
    }

    private var noKey: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Mascot(size: 80).frame(maxWidth: .infinity)
                Text("ИИ-репетитор").font(.largeTitle.weight(.heavy))
                Text("Репетитор работает на Claude. Он ведёт с вами диалоги по-словацки (собеседование, совещание, аренда квартиры…), исправляет ошибки, объясняет правила и составляет новые уроки на любую тему — это нужно, чтобы дойти до B2.")
                Text("Как подключить:").font(.headline)
                VStack(alignment: .leading, spacing: 8) {
                    Text("1. Зайдите на console.anthropic.com и зарегистрируйтесь.")
                    Text("2. Пополните баланс (оплата по факту — разговор обычно стоит центы).")
                    Text("3. Создайте API-ключ (раздел API Keys).")
                    Text("4. Вставьте его во вкладке «Профиль» → «ИИ-репетитор».")
                }
                .foregroundColor(.secondary)
                Text("Без ключа всё остальное приложение работает полностью: курс, карточки, напоминания.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            .padding(24)
        }
    }

    private func generate() {
        let request = topic.trimmingCharacters(in: .whitespaces)
        generating = true
        generateError = nil
        Task {
            do {
                let lesson = try await TutorClient.generateLesson(model: store.state.tutorModel,
                                                                  topic: request, level: level)
                let exercises = ExerciseFactory.make(lesson: lesson, unitWords: lesson.words,
                                                     allWords: course.allWords,
                                                     unitSentences: lesson.sentences)
                generated = PracticeSet(lesson: lesson, exercises: exercises)
            } catch {
                generateError = error.localizedDescription
            }
            generating = false
        }
    }
}

// MARK: - Диалог

struct ChatMessage: Identifiable {
    let id = UUID()
    let isUser: Bool
    let slovak: String
    let notes: String
}

struct ChatView: View {
    @EnvironmentObject var store: ProgressStore
    let scenario: Scenario
    let level: String

    @State private var display: [ChatMessage] = []
    @State private var history: [[String: Any]] = []
    @State private var system = ""
    @State private var input = ""
    @State private var loading = false
    @State private var error: String?
    @State private var started = false
    @State private var exchanges = 0
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(display) { message in
                            bubble(message).id(message.id)
                        }
                        if loading {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("Печатает…").foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 16)
                            .id("loading")
                        }
                        if let error {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(error)
                                    .font(.footnote)
                                    .foregroundColor(Theme.red)
                                if !loading && (history.last?["role"] as? String) == "user" {
                                    Button("Повторить") { request() }
                                        .font(.footnote.weight(.bold))
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                    .padding(.vertical, 12)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: display.count) { _ in
                    if let last = display.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }
            Divider()
            VStack(spacing: 8) {
                if focused { DiacriticsBar { input.append($0) } }
                HStack(alignment: .bottom, spacing: 10) {
                    TextField("Napíšte po slovensky…", text: $input, axis: .vertical)
                        .lineLimit(1...5)
                        .textInputAutocapitalization(.sentences)
                        .focused($focused)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 18).fill(Color(.secondarySystemGroupedBackground)))
                    Button {
                        send()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 34))
                            .foregroundColor(canSend ? Theme.blue : Color(.systemGray3))
                    }
                    .disabled(!canSend)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .navigationTitle(scenario.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: start)
        .onDisappear {
            if exchanges > 0 { store.addXP(min(30, exchanges * 3)) }
            exchanges = 0
        }
    }

    private var canSend: Bool {
        !loading && !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func bubble(_ message: ChatMessage) -> some View {
        HStack(alignment: .bottom) {
            if message.isUser { Spacer(minLength: 40) }
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    if !message.isUser && !message.slovak.isEmpty {
                        SpeakerButton(text: message.slovak)
                    }
                    markdownText(message.slovak)
                        .font(.body.weight(message.isUser ? .regular : .semibold))
                        .foregroundColor(message.isUser ? .white : .primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !message.notes.isEmpty {
                    markdownText(message.notes)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(message.isUser ? Theme.blue : Color(.secondarySystemGroupedBackground))
            )
            if !message.isUser { Spacer(minLength: 24) }
        }
        .padding(.horizontal, 12)
    }

    private func start() {
        guard !started else { return }
        started = true
        system = """
        Ты — дружелюбный репетитор словацкого языка для русскоязычного взрослого, \
        который переезжает в Словакию ради работы и учёбы. Уровень ученика по CEFR: \(level).
        Сценарий: \(scenario.brief)

        Правила:
        - Веди диалог по-словацки, используя лексику и грамматику уровня \(level). \
        На A1–A2 — короткие простые предложения, на B1–B2 — естественная живая речь.
        - Задавай по одному вопросу за раз, чтобы ученик больше говорил.
        - Формат КАЖДОГО ответа строго такой:
          1) Твоя реплика по-словацки (1–4 предложения).
          2) Отдельная строка: ---
          3) Перевод твоей реплики на русский.
          4) Если в последнем сообщении ученика были ошибки — строка «✏️ Исправления:» и список \
        «неправильно → правильно» с коротким пояснением правила по-русски. Если ошибок нет — «✅ Без ошибок!». \
        В первом сообщении этот пункт пропусти.
        - Если ученик пишет по-русски или не знает слова — подскажи, как сказать это по-словацки.
        - Не используй Markdown-заголовки и таблицы; **жирный** можно.
        """
        history = [["role": "user", "content": "Začnime, prosím. (Начнём сценарий — ты говоришь первым.)"]]
        request()
    }

    private func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !loading else { return }
        input = ""
        display.append(ChatMessage(isUser: true, slovak: text, notes: ""))
        history.append(["role": "user", "content": text])
        exchanges += 1
        request()
    }

    private func request() {
        loading = true
        error = nil
        let messages = history
        Task {
            do {
                let result = try await TutorClient.send(model: store.state.tutorModel,
                                                        system: system, messages: messages)
                // Ответ модели кладём в историю целиком и без изменений.
                history.append(["role": "assistant", "content": result.content])
                let parts = result.text.components(separatedBy: "\n---")
                let slovak = parts.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? result.text
                let notes = parts.dropFirst().joined(separator: "\n")
                    .trimmingCharacters(in: CharacterSet(charactersIn: "-").union(.whitespacesAndNewlines))
                display.append(ChatMessage(isUser: false, slovak: slovak, notes: notes))
                Speech.shared.speak(slovak)
            } catch {
                // Неотправленную реплику убираем с конца истории, чтобы её можно было отправить снова.
                if history.count > 1, let last = history.last, (last["role"] as? String) == "user" {
                    history.removeLast()
                    if let lastShown = display.last, lastShown.isUser {
                        input = lastShown.slovak
                        display.removeLast()
                    }
                }
                self.error = error.localizedDescription
            }
            loading = false
        }
    }
}
