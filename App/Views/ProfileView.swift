import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var store: ProgressStore
    @EnvironmentObject var course: CourseStore
    @State private var apiKey = ""
    @State private var keySaved = TutorClient.hasKey
    @State private var confirmReset = false
    @State private var permissionDenied = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    statsGrid
                        .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                    weekChart
                }

                Section("Цель на день") {
                    Picker("Опыт в день", selection: $store.state.dailyGoal) {
                        Text("10 XP — легко").tag(10)
                        Text("20 XP — нормально").tag(20)
                        Text("30 XP — серьёзно").tag(30)
                        Text("50 XP — интенсив").tag(50)
                    }
                }

                Section {
                    Toggle("Ежедневные напоминания", isOn: reminderToggle)
                    if store.state.reminderEnabled {
                        DatePicker("Время", selection: store.reminderDate, displayedComponents: .hourAndMinute)
                        Button("Отправить тестовое уведомление") {
                            NotificationManager.shared.sendTest()
                        }
                    }
                    if permissionDenied {
                        Text("Уведомления запрещены. Разрешите их: Настройки → Slovíčko → Уведомления.")
                            .font(.footnote)
                            .foregroundColor(Theme.red)
                    }
                } header: {
                    Text("Напоминания")
                } footer: {
                    Text("Как в Duolingo: напоминание в выбранное время и «спасение серии» в 21:30, если вы ещё не занимались.")
                }

                Section {
                    VStack(alignment: .leading) {
                        Text("Скорость речи")
                        Slider(value: $store.state.speechRate, in: 0.3...0.6, step: 0.05) {
                            Text("Скорость")
                        } minimumValueLabel: {
                            Image(systemName: "tortoise.fill")
                        } maximumValueLabel: {
                            Image(systemName: "hare.fill")
                        }
                        .onChange(of: store.state.speechRate) { value in
                            Speech.shared.rate = Float(value)
                        }
                    }
                    Toggle("Звуки ответов", isOn: $store.state.soundsOn)
                        .onChange(of: store.state.soundsOn) { on in
                            SoundFX.shared.enabled = on
                            if on { SoundFX.shared.play(.correct) }
                        }
                    Button("Проверить голос") {
                        Speech.shared.speak("Dobrý deň! Volám sa Slovíčko a budem vás učiť po slovensky.")
                    }
                } header: {
                    Text("Озвучка")
                } footer: {
                    Text(voiceHint)
                }

                Section {
                    if keySaved {
                        Label("Ключ сохранён", systemImage: "checkmark.seal.fill")
                            .foregroundColor(Theme.green)
                        Button("Удалить ключ", role: .destructive) {
                            Keychain.save("", for: TutorClient.apiKeyName)
                            keySaved = false
                        }
                    } else {
                        SecureField("sk-ant-…", text: $apiKey)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button("Сохранить ключ") {
                            Keychain.save(apiKey.trimmingCharacters(in: .whitespacesAndNewlines), for: TutorClient.apiKeyName)
                            apiKey = ""
                            keySaved = TutorClient.hasKey
                        }
                        .disabled(apiKey.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    Picker("Модель", selection: $store.state.tutorModel) {
                        ForEach(TutorModel.allCases) { model in
                            Text(model.title).tag(model.rawValue)
                        }
                    }
                    .pickerStyle(.navigationLink)
                } header: {
                    Text("ИИ-репетитор")
                } footer: {
                    Text("Ключ с console.anthropic.com хранится только на этом iPhone и отправляется только в Anthropic API.")
                }

                Section("Сложность") {
                    Toggle("Бесконечные сердца", isOn: $store.state.unlimitedHearts)
                    Toggle("Открыть все уроки", isOn: $store.state.unlockAll)
                }

                Section {
                    Button("Сбросить прогресс", role: .destructive) { confirmReset = true }
                } footer: {
                    Text("Slovíčko 1.0 · курс: \(course.units.count) разделов, \(course.allLessons.count) уроков, \(course.allWords.count) слов")
                }
            }
            .navigationTitle("Профиль")
            .confirmationDialog("Сбросить весь прогресс?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Сбросить", role: .destructive) { store.resetProgress() }
            } message: {
                Text("Уроки, опыт, серия и словарь будут удалены.")
            }
            .onAppear { keySaved = TutorClient.hasKey }
        }
    }

    private var voiceHint: String {
        if !Speech.shared.hasSlovakVoice {
            return "Словацкий голос не найден. Скачайте его: Настройки → Универсальный доступ → Устный контент → Голоса → Словацкий."
        }
        if !Speech.shared.hasEnhancedVoice {
            return "Совет: для более естественного произношения скачайте улучшенный голос «Laura (улучшенный)»: Настройки → Универсальный доступ → Устный контент → Голоса → Словацкий."
        }
        return "Используется улучшенный словацкий голос."
    }

    private var reminderToggle: Binding<Bool> {
        Binding(
            get: { store.state.reminderEnabled },
            set: { enabled in
                if enabled {
                    NotificationManager.shared.requestPermission { granted in
                        permissionDenied = !granted
                        store.state.reminderEnabled = granted
                        NotificationManager.shared.reschedule(for: store)
                    }
                } else {
                    store.state.reminderEnabled = false
                    NotificationManager.shared.reschedule(for: store)
                }
            }
        )
    }

    private var statsGrid: some View {
        let words = store.state.cards.count
        let lessons = store.state.completedLessons.count
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            statTile("🔥", "\(store.currentStreak)", "дней подряд")
            statTile("🏅", "\(store.state.bestStreak)", "рекорд серии")
            statTile("⚡️", "\(store.state.xpTotal)", "всего опыта")
            statTile("📚", "\(lessons)/\(course.allLessons.count)", "уроков")
            statTile("🧠", "\(words)", "слов в словаре")
            statTile("🎯", course.currentLevel(completed: store.state.completedLessons), "текущий уровень")
        }
    }

    private func statTile(_ emoji: String, _ value: String, _ caption: String) -> some View {
        HStack(spacing: 10) {
            Text(emoji).font(.title2)
            VStack(alignment: .leading, spacing: 0) {
                Text(value).font(.headline.weight(.heavy))
                Text(caption).font(.caption).foregroundColor(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).stroke(Color(.systemGray4), lineWidth: 1.5))
    }

    private var weekChart: some View {
        let days = (0..<7).reversed().map { ago -> (String, Int) in
            let date = Calendar.current.date(byAdding: .day, value: -ago, to: Date()) ?? Date()
            let label = ago == 0 ? "Сег" : shortWeekday(date)
            return (label, store.state.xpByDay[ProgressStore.dayKey(date)] ?? 0)
        }
        let maxValue = max(store.state.dailyGoal, days.map { $0.1 }.max() ?? 0)
        return VStack(alignment: .leading, spacing: 8) {
            Text("Опыт за неделю").font(.headline)
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                    VStack(spacing: 4) {
                        Text(day.1 > 0 ? "\(day.1)" : "")
                            .font(.caption2.weight(.bold))
                            .foregroundColor(.secondary)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(day.1 >= store.state.dailyGoal ? Theme.gold : Theme.blue.opacity(day.1 > 0 ? 0.8 : 0.15))
                            .frame(height: max(4, CGFloat(day.1) / CGFloat(max(maxValue, 1)) * 90))
                        Text(day.0).font(.caption2).foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 130, alignment: .bottom)
        }
        .padding(.vertical, 6)
    }

    private func shortWeekday(_ date: Date) -> String {
        let names = ["Вс", "Пн", "Вт", "Ср", "Чт", "Пт", "Сб"]
        let weekday = Calendar.current.component(.weekday, from: date)
        return names[(weekday - 1) % 7]
    }
}

struct OnboardingView: View {
    @EnvironmentObject var store: ProgressStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Mascot(size: 96)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 30)
                Text("Ahoj! Я Slovíčko 👋")
                    .font(.largeTitle.weight(.heavy))
                Text("Научу вас словацкому с нуля до B2 — с упором на работу и учёбу. Короткие уроки каждый день, повторение слов, разговоры с ИИ-репетитором.")
                    .foregroundColor(.secondary)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Сколько заниматься в день?").font(.headline)
                    Picker("Цель", selection: $store.state.dailyGoal) {
                        Text("10 XP").tag(10)
                        Text("20 XP").tag(20)
                        Text("30 XP").tag(30)
                        Text("50 XP").tag(50)
                    }
                    .pickerStyle(.segmented)
                    Text("Один урок ≈ 10–15 XP ≈ 5 минут.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Когда напоминать?").font(.headline)
                    DatePicker("Время напоминания", selection: store.reminderDate, displayedComponents: .hourAndMinute)
                }

                Button("ВКЛЮЧИТЬ НАПОМИНАНИЯ И НАЧАТЬ") {
                    NotificationManager.shared.requestPermission { granted in
                        store.state.reminderEnabled = granted
                        finish()
                    }
                }
                .buttonStyle(ChunkyButtonStyle(color: Theme.green))
                .padding(.top, 10)

                Button("Начать без напоминаний") { finish() }
                    .frame(maxWidth: .infinity)
                    .foregroundColor(.secondary)
            }
            .padding(24)
        }
        .interactiveDismissDisabled()
    }

    private func finish() {
        store.state.onboarded = true
        NotificationManager.shared.reschedule(for: store)
        dismiss()
    }
}
