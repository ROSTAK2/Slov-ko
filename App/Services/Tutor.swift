import Foundation
import Security

// MARK: - Хранение ключа

enum Keychain {
    private static let fallbackPrefix = "slovicko.fallback."

    static func save(_ value: String, for key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
        UserDefaults.standard.removeObject(forKey: fallbackPrefix + key)
        guard !value.isEmpty else { return }
        var add = query
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        if SecItemAdd(add as CFDictionary, nil) != errSecSuccess {
            // У переподписанных приложений Keychain иногда недоступен — тогда храним локально.
            UserDefaults.standard.set(value, forKey: fallbackPrefix + key)
        }
    }

    static func read(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var out: AnyObject?
        if SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
           let data = out as? Data,
           let value = String(data: data, encoding: .utf8) {
            return value
        }
        return UserDefaults.standard.string(forKey: fallbackPrefix + key)
    }
}

// MARK: - Клиент Claude API

enum TutorError: LocalizedError {
    case noKey
    case http(String)
    case refusal
    case empty
    case badJSON

    var errorDescription: String? {
        switch self {
        case .noKey: return "Не задан API-ключ. Добавьте его в Профиле."
        case .http(let message): return "Ошибка сервера: \(message)"
        case .refusal: return "Модель отказалась отвечать на этот запрос. Попробуйте переформулировать."
        case .empty: return "Пустой ответ. Попробуйте ещё раз."
        case .badJSON: return "Не удалось разобрать урок. Попробуйте ещё раз."
        }
    }
}

enum TutorModel: String, CaseIterable, Identifiable {
    case opus = "claude-opus-5-5"
    case sonnet = "claude-sonnet-5-5"
    case haiku = "claude-haiku-5-5"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .opus: return "Opus 5.5 — лучшее качество"
        case .sonnet: return "Sonnet 5.5 — баланс цены и качества"
        case .haiku: return "Haiku 5.5 — самый дешёвый"
        }
    }
}

enum TutorClient {
    static let apiKeyName = "anthropicKey"
    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    static var hasKey: Bool {
        !(Keychain.read(apiKeyName) ?? "").isEmpty
    }

    /// Один запрос к Messages API. `content` — блоки ответа целиком,
    /// их нужно без изменений возвращать в историю диалога.
    static func send(model: String,
                     system: String,
                     messages: [[String: Any]],
                     schema: [String: Any]? = nil,
                     maxTokens: Int = 8000) async throws -> (text: String, content: [Any]) {
        guard let key = Keychain.read(apiKeyName), !key.isEmpty else { throw TutorError.noKey }

        var outputConfig: [String: Any] = ["effort": "low"]
        if let schema {
            outputConfig["format"] = ["type": "json_schema", "schema": schema]
        }
        var body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "system": system,
            "messages": messages,
            "output_config": outputConfig
        ]
        // Если модель откажется отвечать, сервер сам повторит запрос на подходящей модели.
        // У Haiku серверного fallback нет.
        let useFallback = !model.contains("haiku")
        if useFallback {
            body["fallbacks"] = "default"
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        if useFallback {
            request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let message = (json["error"] as? [String: Any])?["message"] as? String ?? "HTTP \(http.statusCode)"
            throw TutorError.http(message)
        }
        if (json["stop_reason"] as? String) == "refusal" {
            throw TutorError.refusal
        }
        let content = json["content"] as? [Any] ?? []
        let text = content.compactMap { block -> String? in
            guard let b = block as? [String: Any], (b["type"] as? String) == "text" else { return nil }
            return b["text"] as? String
        }.joined()
        guard !text.isEmpty else { throw TutorError.empty }
        return (text, content)
    }

    // MARK: - Готовые сценарии

    static func explainMistake(model: String, exercise: Exercise, userAnswer: String) async throws -> String {
        let system = """
        Ты опытный преподаватель словацкого языка для русскоязычных. \
        Объясняй по-русски, коротко и понятно (не больше 6–7 предложений), \
        опирайся на сходства и различия с русским. Без Markdown-заголовков; **жирный** можно.
        """
        var task = exercise.instruction
        if let template = exercise.template { task += ": \(template)" }
        if !exercise.prompt.isEmpty { task += " (\(exercise.prompt))" }
        if exercise.listening, let audio = exercise.promptAudio { task += " Аудио: «\(audio)»" }
        let user = """
        Задание: \(task)
        Правильный ответ: \(exercise.answer)
        Ответ ученика: \(userAnswer)
        Объясни, в чём ошибка, и какое правило тут работает. Приведи 1–2 похожих примера со словацким и переводом.
        """
        let result = try await send(model: model, system: system,
                                    messages: [["role": "user", "content": user]], maxTokens: 4000)
        return result.text
    }

    static func generateLesson(model: String, topic: String, level: String) async throws -> Lesson {
        let pair: [String: Any] = [
            "type": "object",
            "additionalProperties": false,
            "required": ["sk", "ru"],
            "properties": ["sk": ["type": "string"], "ru": ["type": "string"]]
        ]
        let fill: [String: Any] = [
            "type": "object",
            "additionalProperties": false,
            "required": ["text", "answer", "options", "ru", "tip"],
            "properties": [
                "text": ["type": "string"],
                "answer": ["type": "string"],
                "options": ["type": "array", "items": ["type": "string"]],
                "ru": ["type": "string"],
                "tip": ["type": "string"]
            ]
        ]
        let schema: [String: Any] = [
            "type": "object",
            "additionalProperties": false,
            "required": ["title", "words", "sentences", "fills"],
            "properties": [
                "title": ["type": "string"],
                "words": ["type": "array", "items": pair],
                "sentences": ["type": "array", "items": pair],
                "fills": ["type": "array", "items": fill]
            ]
        ]
        let system = """
        Ты методист, который составляет уроки словацкого языка для русскоязычного взрослого, \
        переезжающего в Словакию ради работы и учёбы. Пиши естественный современный литературный словацкий \
        с правильной диакритикой. Переводы — естественный русский.
        """
        let user = """
        Тема: \(topic)
        Уровень ученика по CEFR: \(level)
        Составь урок:
        - title: короткое название урока по-словацки;
        - words: 8 полезных слов или выражений по теме (sk — в словарной форме, ru — перевод);
        - sentences: 6 предложений по теме уровня \(level), 4–10 слов каждое, без кавычек и скобок;
        - fills: 4 предложения с пропуском: в text ровно один пропуск «___» на месте слова, \
        answer — пропущенное слово, options — 3 НЕВЕРНЫХ, но правдоподобных варианта \
        (другие падежи, лица, виды глагола; не совпадают с answer), ru — перевод всего предложения, tip — одно короткое предложение по-русски: какое правило здесь работает (можно **жирный**).
        Используй лексику и грамматику, подходящие уровню \(level).
        """
        let result = try await send(model: model, system: system,
                                    messages: [["role": "user", "content": user]],
                                    schema: schema, maxTokens: 8000)
        struct Generated: Decodable {
            var title: String
            var words: [WordPair]
            var sentences: [SentencePair]
            var fills: [FillItem]
        }
        guard let data = result.text.data(using: .utf8),
              let g = try? JSONDecoder().decode(Generated.self, from: data),
              !g.words.isEmpty else {
            throw TutorError.badJSON
        }
        let fills = g.fills.filter { $0.text.contains("___") && !$0.answer.isEmpty }
        return Lesson(id: "ai-\(UUID().uuidString)", title: g.title,
                      words: g.words, sentences: g.sentences, fills: fills)
    }
}
