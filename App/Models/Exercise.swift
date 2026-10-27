import Foundation

enum ExerciseKind {
    case choice   // выбрать вариант (слово, предложение или «что вы услышали»)
    case match    // найти пары (текстом или на слух)
    case build    // собрать предложение из плиток
    case typing   // напечатать ответ
    case fill     // вставить пропущенное слово
    case spot     // найти ошибку в предложении
    case speak    // произнести вслух
}

struct Exercise: Identifiable {
    let id = UUID()
    var kind: ExerciseKind
    var instruction: String
    var prompt: String = ""
    var promptAudio: String? = nil
    var autoplay: Bool = false
    var listening: Bool = false
    var options: [String] = []
    var optionsSlovak: Bool = false
    var answer: String = ""
    var alternatives: [String] = []
    var pairs: [WordPair] = []
    var template: String? = nil
    var answerIsSlovak: Bool = true
    var speakAfter: String? = nil
    var wordKey: String? = nil
    var note: String? = nil
    /// Слова задания с подсказками по нажатию.
    var hints: [HintWord]? = nil
    /// Слова задания на словацком (тогда при нажатии слово проговаривается).
    var hintsSlovak: Bool = false
    /// Слово встречается впервые.
    var isNew: Bool = false
    /// Короткое правило — показывается при ошибке.
    var tip: String? = nil
    /// Показать правило и при правильном ответе (ложные друзья).
    var tipAlways: Bool = false
    /// Пары на слух: слева только кнопки озвучки.
    var audioPairs: Bool = false
    /// Слова предложения для «Найдите ошибку».
    var spotTokens: [String] = []
}

enum CheckResult: Equatable {
    case correct
    case almost(String)
    case wrong
}

enum Checker {
    private static let punctuation = CharacterSet(charactersIn: ".,!?;:„“\"”«»…()–—-'’")

    static func normalize(_ s: String) -> String {
        var out = ""
        for scalar in s.precomposedStringWithCanonicalMapping.lowercased().unicodeScalars {
            out.unicodeScalars.append(punctuation.contains(scalar) ? " " : scalar)
        }
        return out.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    static func stripDiacritics(_ s: String) -> String {
        s.folding(options: .diacriticInsensitive, locale: Locale(identifier: "sk_SK"))
    }

    static func check(_ input: String, answer: String, alternatives: [String] = []) -> CheckResult {
        let user = normalize(input)
        let targets = ([answer] + alternatives).map(normalize)
        if targets.contains(user) { return .correct }
        let plain = stripDiacritics(user)
        if targets.contains(where: { stripDiacritics($0) == plain }) {
            return .almost("Почти! Проверьте диакритику (чёрточки и галочки над буквами).")
        }
        if user.count >= 5, targets.contains(where: { levenshtein($0, user) <= 1 }) {
            return .almost("Почти! Небольшая опечатка.")
        }
        return .wrong
    }

    /// Проверка произношения: распознавание неточное, поэтому считаем долю совпавших слов.
    static func speech(_ transcript: String, answer: String) -> CheckResult {
        let said = Set(stripDiacritics(normalize(transcript)).split(separator: " ").map(String.init))
        let expected = stripDiacritics(normalize(answer)).split(separator: " ").map(String.init)
        guard !expected.isEmpty else { return .wrong }
        let matched = expected.filter { said.contains($0) }.count
        let ratio = Double(matched) / Double(expected.count)
        if ratio >= 0.8 { return .correct }
        if ratio >= 0.5 { return .almost("Почти! Часть слов не распознана — попробуйте чётче.") }
        return .wrong
    }

    static func levenshtein(_ a: String, _ b: String) -> Int {
        let x = Array(a), y = Array(b)
        if x.isEmpty { return y.count }
        if y.isEmpty { return x.count }
        var previous = Array(0...y.count)
        for i in 1...x.count {
            var current = [i] + Array(repeating: 0, count: y.count)
            for j in 1...y.count {
                current[j] = min(previous[j] + 1,
                                 current[j - 1] + 1,
                                 previous[j - 1] + (x[i - 1] == y[j - 1] ? 0 : 1))
            }
            previous = current
        }
        return previous[y.count]
    }
}

enum ExerciseFactory {
    static let trimSet = CharacterSet(charactersIn: ".,!?;:„“\"”«»…()–—")

    static func tokens(_ s: String) -> [String] {
        s.split(separator: " ")
            .map { String($0).trimmingCharacters(in: trimSet) }
            .filter { !$0.isEmpty }
    }

    /// Урок курса, урок от ИИ или «Повторение» раздела.
    /// `known` — слова, которые уже есть в словаре ученика (остальные помечаются как новые).
    /// `speaking` — можно ли давать упражнения на произношение.
    static func make(lesson: Lesson, unitWords: [WordPair], allWords: [WordPair],
                     unitSentences: [SentencePair], known: Set<String>, speaking: Bool) -> [Exercise] {
        let pool = unitWords.shuffled() + allWords.shuffled()
        let sentencePool = unitSentences + lesson.sentences
        if lesson.isReview {
            return review(lesson: lesson, pool: pool, sentencePool: sentencePool, speaking: speaking)
        }

        let words = lesson.words.shuffled()
        var head: [Exercise] = []
        var body: [Exercise] = []

        // Знакомство с новыми словами: слово с подсказкой → выбрать перевод.
        for w in words.prefix(3) {
            head.append(choice(w, toSlovak: false, pool: pool, isNew: !known.contains(w.sk)))
        }
        let matchable = distinctPairs(lesson.words)
        if matchable.count >= 3 {
            head.append(match(Array(matchable.shuffled().prefix(5))))
        }
        if words.count > 3 { body.append(choice(words[3], toSlovak: true, pool: pool)) }
        if words.count > 4 { body.append(listenChoice(words[4], pool: pool)) }
        if let w = (words.count > 5 ? Optional(words[5]) : words.last) {
            body.append(typeWord(w))
        }
        // Ловушки урока — отдельным вопросом, если не попали выше.
        for w in words.dropFirst(6) where w.trap != nil {
            body.append(choice(w, toSlovak: false, pool: pool))
        }
        let sentences = Array(lesson.sentences.shuffled().prefix(5))
        body += sentenceExercises(sentences, pool: sentencePool)
        if speaking, let s = shortest(lesson.sentences) {
            body.append(speak(s))
        }
        body += fillExercises(Array(lesson.fills.prefix(3)))
        return head + body.shuffled()
    }

    /// «Повторение» в конце раздела: всё вперемешку, больше письма и аудирования.
    static func review(lesson: Lesson, pool: [WordPair], sentencePool: [SentencePair], speaking: Bool) -> [Exercise] {
        let words = lesson.words.shuffled()
        var out: [Exercise] = []
        for (i, w) in words.prefix(4).enumerated() {
            switch i {
            case 0: out.append(choice(w, toSlovak: true, pool: pool))
            case 2: out.append(listenChoice(w, pool: pool))
            default: out.append(typeWord(w))
            }
        }
        out += sentenceExercises(Array(lesson.sentences.shuffled().prefix(6)), pool: sentencePool)
        if speaking, let s = shortest(lesson.sentences.shuffled()) {
            out.append(speak(s))
        }
        out += fillExercises(Array(lesson.fills.shuffled().prefix(3)))
        let matchable = distinctPairs(Array(words.dropFirst(4)))
        let first = matchable.count >= 3 ? [match(Array(matchable.prefix(5)), audio: true)] : []
        return first + out.shuffled()
    }

    /// Тренировка (вкладка «Повтор»): выученные слова + предложения из пройденных уроков.
    static func practice(words: [WordPair], pool: [WordPair], sentences: [SentencePair]) -> [Exercise] {
        let selected = Array(words.shuffled().prefix(8))
        var out: [Exercise] = []
        let matchable = distinctPairs(selected)
        if matchable.count >= 3 {
            out.append(match(Array(matchable.prefix(5)), audio: Bool.random()))
        }
        let shuffledPool = pool.shuffled()
        var rest: [Exercise] = []
        for (i, w) in selected.enumerated() {
            switch i % 4 {
            case 0: rest.append(choice(w, toSlovak: false, pool: shuffledPool))
            case 1: rest.append(choice(w, toSlovak: true, pool: shuffledPool))
            case 2: rest.append(listenChoice(w, pool: shuffledPool))
            default: rest.append(typeWord(w))
            }
        }
        let picked = Array(sentences.shuffled().prefix(4))
        rest += sentenceExercises(picked, pool: sentences)
        return out + rest.shuffled()
    }

    /// Предложения по кругу: перевод на словацкий, аудирование, перевод на русский,
    /// диктант, выбор правильного варианта.
    private static func sentenceExercises(_ sentences: [SentencePair], pool: [SentencePair]) -> [Exercise] {
        let skTiles = pool.flatMap { tokens($0.sk) }
        let ruTiles = pool.flatMap { tokens($0.ru) }
        return sentences.enumerated().map { (i, s) -> Exercise in
            switch i % 5 {
            case 0: return buildSlovak(s, tilePool: skTiles, listening: false)
            case 1: return buildSlovak(s, tilePool: skTiles, listening: true)
            case 2: return buildRussian(s, tilePool: ruTiles)
            case 3:
                return tokens(s.sk).count <= 8 ? dictation(s) : buildSlovak(s, tilePool: skTiles, listening: false)
            default:
                return sentenceChoice(s, tilePool: skTiles) ?? buildSlovak(s, tilePool: skTiles, listening: false)
            }
        }
    }

    /// Пропуски: по очереди «вставьте слово» и «найдите ошибку».
    private static func fillExercises(_ fills: [FillItem]) -> [Exercise] {
        fills.enumerated().map { (i, f) -> Exercise in
            i == 1 ? (spotError(f) ?? fill(f)) : fill(f)
        }
    }

    private static func shortest(_ sentences: [SentencePair]) -> SentencePair? {
        sentences.filter { tokens($0.sk).count <= 7 }.randomElement()
            ?? sentences.min { tokens($0.sk).count < tokens($1.sk).count }
    }

    // MARK: - Отдельные типы

    static func choice(_ w: WordPair, toSlovak: Bool, pool: [WordPair], isNew: Bool = false) -> Exercise {
        let correct = toSlovak ? w.sk : w.ru
        var options = [correct]
        var usedMeanings = meanings(w.ru)
        // Ложный друг: главный «соблазн» — значение, которого ждёт русскоговорящий.
        if !toSlovak, let trap = w.trap {
            options.append(trap)
            usedMeanings.formUnion(meanings(trap))
        }
        for p in pool where options.count < 4 && p.sk != w.sk {
            let option = toSlovak ? p.sk : p.ru
            let m = meanings(p.ru)
            // Синонимы (pretože/lebo → «потому что») дали бы два верных ответа.
            guard m.isDisjoint(with: usedMeanings),
                  !options.contains(where: { $0.lowercased() == option.lowercased() }) else { continue }
            usedMeanings.formUnion(m)
            options.append(option)
        }
        var e = Exercise(kind: .choice, instruction: toSlovak ? "Как сказать по-словацки?" : "Что это значит?")
        e.prompt = toSlovak ? w.ru : w.sk
        e.promptAudio = toSlovak ? nil : w.sk
        e.autoplay = !toSlovak
        e.options = options.shuffled()
        e.optionsSlovak = toSlovak
        e.answer = correct
        e.answerIsSlovak = toSlovak
        e.speakAfter = toSlovak ? w.sk : nil
        e.wordKey = w.sk
        if isNew && !toSlovak {
            // Новое слово: перевод можно подсмотреть, нажав на него.
            e.isNew = true
            e.hints = [HintWord(t: w.sk, h: w.ru, g: 0)]
            e.hintsSlovak = true
        }
        applyTrap(w, to: &e)
        return e
    }

    /// «Что вы услышали?» — только звук, варианты похожи по написанию.
    static func listenChoice(_ w: WordPair, pool: [WordPair]) -> Exercise {
        let similar = pool
            .filter { $0.sk.lowercased() != w.sk.lowercased() }
            .sorted { similarity($0.sk, w.sk) > similarity($1.sk, w.sk) }
        var options = [w.sk]
        for p in similar where options.count < 4 && !options.contains(where: { $0.lowercased() == p.sk.lowercased() }) {
            options.append(p.sk)
        }
        var e = Exercise(kind: .choice, instruction: "Что вы услышали?")
        e.listening = true
        e.promptAudio = w.sk
        e.autoplay = true
        e.options = options.shuffled()
        e.optionsSlovak = false   // не проговариваем варианты — иначе слишком просто
        e.answer = w.sk
        e.answerIsSlovak = true
        e.wordKey = w.sk
        e.note = "\(w.sk) — \(w.ru)"
        return e
    }

    static func match(_ pairs: [WordPair], audio: Bool = false) -> Exercise {
        var e = Exercise(kind: .match, instruction: audio ? "Найдите пары на слух" : "Найдите пары")
        e.pairs = pairs
        e.audioPairs = audio
        return e
    }

    static func typeWord(_ w: WordPair) -> Exercise {
        var e = Exercise(kind: .typing, instruction: "Напишите по-словацки")
        e.prompt = w.ru
        e.answer = w.sk
        e.answerIsSlovak = true
        e.speakAfter = w.sk
        e.wordKey = w.sk
        applyTrap(w, to: &e)
        return e
    }

    static func buildSlovak(_ s: SentencePair, tilePool: [String], listening: Bool) -> Exercise {
        let answerTokens = tokens(s.sk)
        var e = Exercise(kind: .build, instruction: listening ? "Нажмите на то, что услышите" : "Переведите на словацкий")
        e.prompt = listening ? "" : s.ru
        e.listening = listening
        e.promptAudio = listening ? s.sk : nil
        e.autoplay = listening
        e.options = (answerTokens + distractors(for: answerTokens, from: tilePool, count: 3)).shuffled()
        e.optionsSlovak = true
        e.answer = answerTokens.joined(separator: " ")
        e.answerIsSlovak = true
        e.speakAfter = listening ? nil : s.sk
        e.note = s.ru
        if !listening {
            e.hints = s.ruw ?? HintDictionary.words(s.ru, slovak: false)
        }
        return e
    }

    static func buildRussian(_ s: SentencePair, tilePool: [String]) -> Exercise {
        let answerTokens = tokens(s.ru)
        var e = Exercise(kind: .build, instruction: "Переведите на русский")
        e.prompt = s.sk
        e.promptAudio = s.sk
        e.autoplay = true
        e.options = (answerTokens + distractors(for: answerTokens, from: tilePool, count: 3)).shuffled()
        e.answer = answerTokens.joined(separator: " ")
        e.answerIsSlovak = false
        e.hints = s.skw ?? HintDictionary.words(s.sk, slovak: true)
        e.hintsSlovak = true
        return e
    }

    /// «Выберите правильный перевод»: варианты отличаются одним словом (окончанием, формой).
    static func sentenceChoice(_ s: SentencePair, tilePool: [String]) -> Exercise? {
        let words = s.sk.split(separator: " ").map(String.init)
        let core = words.map { $0.trimmingCharacters(in: trimSet) }
        var variants: [String] = []
        for index in core.indices.shuffled() where variants.count < 2 && core[index].count >= 3 {
            let target = core[index].lowercased()
            let prefix = String(target.prefix(3))
            let candidates = tilePool.filter {
                let t = $0.lowercased()
                return t != target && t.hasPrefix(prefix)
            }
            guard let replacement = candidates.randomElement() else { continue }
            var changed = words
            changed[index] = words[index].replacingOccurrences(of: core[index], with: replacement)
            let variant = changed.joined(separator: " ")
            let key = Checker.normalize(variant)
            if key != Checker.normalize(s.sk) && !variants.contains(where: { Checker.normalize($0) == key }) {
                variants.append(variant)
            }
        }
        guard variants.count == 2 else { return nil }
        var e = Exercise(kind: .choice, instruction: "Выберите правильный перевод")
        e.prompt = s.ru
        e.hints = s.ruw ?? HintDictionary.words(s.ru, slovak: false)
        e.options = ([s.sk] + variants).shuffled()
        e.optionsSlovak = true
        e.answer = s.sk
        e.answerIsSlovak = true
        e.speakAfter = s.sk
        return e
    }

    static func dictation(_ s: SentencePair) -> Exercise {
        var e = Exercise(kind: .typing, instruction: "Напишите, что услышите")
        e.listening = true
        e.promptAudio = s.sk
        e.autoplay = true
        e.answer = s.sk
        e.answerIsSlovak = true
        e.note = s.ru
        return e
    }

    static func speak(_ s: SentencePair) -> Exercise {
        var e = Exercise(kind: .speak, instruction: "Произнесите вслух")
        e.prompt = s.sk
        e.promptAudio = s.sk
        e.autoplay = true
        e.hints = s.skw ?? HintDictionary.words(s.sk, slovak: true)
        e.hintsSlovak = true
        e.answer = s.sk
        e.answerIsSlovak = true
        e.note = s.ru
        return e
    }

    static func fill(_ f: FillItem) -> Exercise {
        var options = [f.answer]
        for o in f.options where !options.contains(where: { $0.lowercased() == o.lowercased() }) {
            options.append(o)
        }
        var e = Exercise(kind: .fill, instruction: "Вставьте пропущенное слово")
        e.template = f.text
        e.prompt = f.ru
        e.options = options.shuffled()
        e.optionsSlovak = true
        e.answer = f.answer
        e.answerIsSlovak = true
        e.speakAfter = f.text.replacingOccurrences(of: "___", with: f.answer)
        e.hints = f.w ?? HintDictionary.words(f.text, slovak: true)
        e.hintsSlovak = true
        e.tip = f.tip
        return e
    }

    /// «Найдите ошибку»: в предложение подставлен неверный вариант — его нужно нажать.
    static func spotError(_ f: FillItem) -> Exercise? {
        guard let wrong = f.options.randomElement() else { return nil }
        var tokens = f.text.split(separator: " ").map(String.init)
        guard let index = tokens.firstIndex(where: { $0.contains("___") }) else { return nil }
        tokens[index] = tokens[index].replacingOccurrences(of: "___", with: wrong)
        let correct = f.text.replacingOccurrences(of: "___", with: f.answer)
        var e = Exercise(kind: .spot, instruction: "Найдите ошибку в предложении")
        e.prompt = f.ru
        e.spotTokens = tokens
        e.answer = "\(index)"
        e.answerIsSlovak = false
        e.speakAfter = correct
        e.note = "Правильно: \(correct)"
        e.tip = f.tip
        return e
    }

    // MARK: - Вспомогательное

    private static func applyTrap(_ w: WordPair, to e: inout Exercise) {
        guard let trap = w.trap else { return }
        e.tip = "⚠️ Ложный друг: **\(w.sk)** — это «\(w.ru)», а не «\(trap)»."
        e.tipAlways = true
    }

    /// Насколько слова похожи: общий префикс + общие буквы.
    private static func similarity(_ a: String, _ b: String) -> Int {
        let x = Array(a.lowercased()), y = Array(b.lowercased())
        var prefix = 0
        while prefix < min(x.count, y.count) && x[prefix] == y[prefix] { prefix += 1 }
        let common = Set(x).intersection(Set(y)).count
        let lengthPenalty = abs(x.count - y.count)
        return prefix * 3 + common - lengthPenalty
    }

    private static func distractors(for answer: [String], from pool: [String], count: Int) -> [String] {
        var seen = Set(answer.map { Checker.normalize($0) })
        var result: [String] = []
        for t in pool.shuffled() {
            let n = Checker.normalize(t)
            if n.isEmpty || seen.contains(n) { continue }
            seen.insert(n)
            result.append(t)
            if result.count == count { break }
        }
        return result
    }

    private static func distinctPairs(_ words: [WordPair]) -> [WordPair] {
        var sk = Set<String>(), ru = Set<String>()
        var out: [WordPair] = []
        for w in words where !sk.contains(w.sk.lowercased()) && meanings(w.ru).isDisjoint(with: ru) {
            sk.insert(w.sk.lowercased())
            ru.formUnion(meanings(w.ru))
            out.append(w)
        }
        return out
    }

    /// «потому что (разг.)» → ["потому что"]; «привет / пока» → ["привет", "пока"].
    private static func meanings(_ ru: String) -> Set<String> {
        let noParens = ru.replacingOccurrences(of: "\\([^)]*\\)", with: "", options: .regularExpression)
        let parts = noParens.lowercased()
            .split(whereSeparator: { ",/;".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return Set(parts)
    }
}
