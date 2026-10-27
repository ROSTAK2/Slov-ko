import SwiftUI

/// Нажатие на сердечко: сколько осталось до восстановления + уведомление.
struct HeartsSheet: View {
    @EnvironmentObject var store: ProgressStore
    @Environment(\.dismiss) private var dismiss
    @State private var permissionDenied = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(spacing: 18) {
                Capsule()
                    .fill(Color(.systemGray4))
                    .frame(width: 40, height: 5)
                    .padding(.top, 8)

                HStack(spacing: 8) {
                    ForEach(0..<ProgressStore.maxHearts, id: \.self) { i in
                        Image(systemName: i < store.state.hearts || store.state.unlimitedHearts ? "heart.fill" : "heart")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundColor(Theme.red)
                            .scaleEffect(i < store.state.hearts ? 1 : 0.85)
                    }
                }
                .padding(.top, 6)

                Text(title)
                    .font(.title2.weight(.heavy))

                VStack(spacing: 6) {
                    if store.state.unlimitedHearts {
                        Text("Включены бесконечные сердца.")
                            .foregroundColor(.secondary)
                    } else if let next = store.nextHeartAt, let full = store.heartsFullAt {
                        Text("Следующее сердце через **\(countdown(to: next, now: context.date))**")
                        Text("Все сердца — в **\(clock(full))** (через \(countdown(to: full, now: context.date)))")
                            .foregroundColor(.secondary)
                    } else {
                        Text("Можно учиться без ограничений. Ошибка в уроке стоит одно сердце.")
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .font(.subheadline)

                if !store.state.unlimitedHearts && store.state.hearts < ProgressStore.maxHearts {
                    Label("Тренировка во вкладке «Повтор» сразу вернёт одно сердце", systemImage: "dumbbell.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(Theme.blue)
                        .padding(10)
                        .frame(maxWidth: .infinity)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.blue.opacity(0.1)))
                }

                Toggle(isOn: notifyBinding) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Уведомить, когда сердца восстановятся")
                            .font(.subheadline.weight(.semibold))
                        if permissionDenied {
                            Text("Уведомления запрещены в Настройках iPhone.")
                                .font(.caption)
                                .foregroundColor(Theme.red)
                        }
                    }
                }
                .tint(Theme.red)

                Button("ПОНЯТНО") { dismiss() }
                    .buttonStyle(ChunkyButtonStyle(color: Theme.red))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
        .presentationDetents([.height(440)])
        .roundedDesign()
        .onAppear { store.refreshHearts() }
    }

    private var title: String {
        if store.state.unlimitedHearts { return "Сердца: ∞" }
        if store.state.hearts >= ProgressStore.maxHearts { return "Все сердца на месте!" }
        if store.state.hearts == 0 { return "Сердца закончились" }
        return "Сердец: \(store.state.hearts) из \(ProgressStore.maxHearts)"
    }

    private var notifyBinding: Binding<Bool> {
        Binding(
            get: { store.state.heartsNotify },
            set: { on in
                store.state.heartsNotify = on
                if on {
                    NotificationManager.shared.requestPermission { granted in
                        permissionDenied = !granted
                        NotificationManager.shared.reschedule(for: store)
                    }
                } else {
                    NotificationManager.shared.reschedule(for: store)
                }
            }
        )
    }

    private func countdown(to date: Date, now: Date) -> String {
        let seconds = max(0, Int(date.timeIntervalSince(now)))
        let h = seconds / 3600, m = (seconds % 3600) / 60, s = seconds % 60
        if h > 0 { return "\(h) ч \(m) мин" }
        return String(format: "%d:%02d", m, s)
    }

    private func clock(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

/// Как установить словацкий голос — если его нет на iPhone.
struct VoiceHelpSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("🔈").font(.system(size: 56))
                    Text("Установите словацкий голос")
                        .font(.title2.weight(.heavy))
                    Text(statusText)
                        .foregroundColor(.secondary)
                    VStack(alignment: .leading, spacing: 10) {
                        step(1, "Откройте **Настройки** iPhone.")
                        step(2, "**Универсальный доступ → Устный контент → Голоса**.")
                        step(3, "Выберите **Словацкий**.")
                        step(4, "Скачайте голос **Laura** (лучше «Улучшенный»).")
                        step(5, "Вернитесь в Slovíčko — голос подхватится сам.")
                    }
                    Button("ПРОВЕРИТЬ ГОЛОС") {
                        Speech.shared.refreshVoice()
                        Speech.shared.speak("Dobrý deň! My sa učíme po slovensky.")
                    }
                    .buttonStyle(ChunkyButtonStyle())
                    .padding(.top, 8)
                }
                .padding(24)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
        }
        .roundedDesign()
    }

    private var statusText: String {
        switch Speech.shared.status {
        case .czechFallback:
            return "Сейчас слова читает чешский голос — он похож, но не идеален. Со словацким голосом произношение будет точным."
        case .missing:
            return "Сейчас на iPhone нет словацкого голоса, поэтому слова читаются системным голосом с неправильным произношением (например, «my» звучит как «май»)."
        case .slovak:
            return "Словацкий голос установлен. Улучшенная версия звучит естественнее."
        }
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.subheadline.weight(.heavy))
                .foregroundColor(.white)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Theme.blue))
            markdownText(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
