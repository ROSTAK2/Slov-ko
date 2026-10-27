import Foundation
import UserNotifications

/// Локальные напоминания в духе «не забудь позаниматься» — без сервера и push-сертификатов.
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    private let center = UNUserNotificationCenter.current()

    private let dailyMessages: [(String, String)] = [
        ("Ahoj! 👋", "Пять минут словацкого — и день засчитан. Poďme!"),
        ("Slovíčko скучает 🥺", "Jedna lekcia? Одна. Маленькая. Обещаю."),
        ("Словакия ждёт 🇸🇰", "Каждый урок — на шаг ближе к переезду."),
        ("Dobrý večer! 🌙", "Самое время повторить пару slovíčok."),
        ("Собеседование само себя не пройдёт 😉", "Pracovný pohovor ждёт. Пять минут практики?"),
        ("Bez práce nie sú koláče! 🥐", "Без труда не выловишь и рыбку из пруда. Урок?"),
        ("Pozor! ⚠️", "Слова, которые ты учил, начинают забываться. Повтори их!"),
        ("Ako sa máš? 😊", "Ответь Slovíčku уроком — это займёт пару минут."),
        ("Malý krok 👣", "Маленький шаг каждый день = B2 к переезду."),
        ("Kde si? 👀", "Slovíčko ищет тебя уже целый день…")
    ]

    private let rescueMessages: [(String, String)] = [
        ("🔥 Серия под угрозой!", "Ещё не поздно: один урок — и серия спасена."),
        ("Posledná šanca! ⏰", "До полуночи пара часов. Спаси серию!"),
        ("Ešte nie je neskoro 🌙", "Ещё не поздно. Пять минут — и спать.")
    ]

    override init() {
        super.init()
        center.delegate = self
    }

    func requestPermission(completion: @escaping (Bool) -> Void) {
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            DispatchQueue.main.async { completion(granted) }
        }
    }

    /// Пересоздаёт напоминания на 14 дней вперёд. Если сегодня уже занимались — сегодня не беспокоим.
    func reschedule(for store: ProgressStore) {
        let state = store.state
        let practiced = store.practicedToday
        let streak = store.currentStreak
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()

        // Сердца восстановились — отдельное уведомление, работает и без ежедневных напоминаний.
        if state.heartsNotify, let full = store.heartsFullAt, full > Date() {
            let content = UNMutableNotificationContent()
            content.title = "❤️ Сердца восстановлены!"
            content.body = "Все 5 сердец снова с тобой. Самое время для урока."
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: full.timeIntervalSinceNow, repeats: false)
            center.add(UNNotificationRequest(identifier: "hearts-full", content: content, trigger: trigger))
        }

        guard state.reminderEnabled else { return }

        let calendar = Calendar.current
        let now = Date()
        let seed = calendar.ordinality(of: .day, in: .year, for: now) ?? 0
        let reminderMinutes = state.reminderHour * 60 + state.reminderMinute

        for offset in 0..<14 {
            if offset == 0 && practiced { continue }
            guard let day = calendar.date(byAdding: .day, value: offset, to: now) else { continue }

            var daily = calendar.dateComponents([.year, .month, .day], from: day)
            daily.hour = state.reminderHour
            daily.minute = state.reminderMinute
            if let fire = calendar.date(from: daily), fire > now {
                var (title, body) = dailyMessages[(seed + offset) % dailyMessages.count]
                if offset == 0 && streak > 0 {
                    body = "Серия: \(streak) дн. 🔥 " + body
                }
                add(id: "daily-\(offset)", components: daily, title: title, body: body)
            }

            // Вечернее «спасение серии», если основное напоминание раньше 21:00.
            guard reminderMinutes < 21 * 60 else { continue }
            var rescue = calendar.dateComponents([.year, .month, .day], from: day)
            rescue.hour = 21
            rescue.minute = 30
            if let fire = calendar.date(from: rescue), fire > now {
                var (title, body) = rescueMessages[(seed + offset) % rescueMessages.count]
                if offset == 0 && streak > 0 {
                    title = "🔥 Серия \(streak) дн. сгорит в полночь!"
                    body = "Один короткий урок — и она спасена."
                }
                add(id: "rescue-\(offset)", components: rescue, title: title, body: body)
            }
        }
    }

    func sendTest() {
        let content = UNMutableNotificationContent()
        content.title = "Ahoj! Это Slovíčko 👋"
        content.body = "Так будут выглядеть напоминания."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        center.add(UNNotificationRequest(identifier: "test", content: content, trigger: trigger))
    }

    private func add(id: String, components: DateComponents, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    // Показываем уведомления и когда приложение открыто (иначе тестовое не увидеть).
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
