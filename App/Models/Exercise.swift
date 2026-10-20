import Foundation

enum ExerciseKind {
    case choice   // выбрать вариант
    case match    // найти пары
    case build    // собрать предложение из плиток
    case typing   // напечатать ответ
    case fill     // вставить пропущенное слово
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
        for scalar in s.lowercased().unicodeScalars {
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
            return .almost("Внимание на диакритику: \(answer)")
        }
        if user.count >= 5, targets.contains(where: { levenshtein($0, user) <= 1 }) {
            return .almost("Опечатка. Правильно: \(answer)")
        }
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
    static func make(lesson: Lesson, unitWords: [WordPair], allWords: [WordPair],
                     unitSentences: [SentencePair], known: Set<String>) -> [Exercise] {
        let pool = unitWords.shuffled() + allWords.shuffled()
        let sentencePool = unitSentences + lesson.sentences
        if lesson.isReview {
            return review(lesson: lesson, pool: pool, sentencePool: sentencePool)
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
        for w in words.dropFirst(3).prefix(2) {
            body.append(choice(w, toSlovak: true, pool: pool))
        }
        if let w = (words.count > 5 ? Optional(words[5]) : words.last) {
            body.append(typeWord(w))
        }
        body += sentenceExercises(Array(lesson.sentences.shuffled().prefix(5)), pool: sentencePool)
        body += lesson.fills.prefix(3).map(fill)
        return head + body.shuffled()
    }

    /// «Повторение» в конце раздела: всё вперемешку, больше письма и аудирования.
    static func review(lesson: Lesson, pool: [WordPair], sentencePool: [SentencePair]) -> [Exercise] {
        let words = lesson.words.shuffled()
        var out: [Exercise] = []
        for (i, w) in words.prefix(4).enumerated() {
            out.append(i.isMultiple(of: 2) ? choice(w, toSlovak: true, pool: pool) : typeWord(w))
        }
        out += sentenceExercises(Array(lesson.sentences.shuffled().prefix(6)), pool: sentencePool)
        out += lesson.fills.shuffled().prefix(3).map(fill)
        let matchable = distinctPairs(Array(words.dropFirst(4)))
        let first = matchable.count >= 3 ? [match(Array(matchable.prefix(5)))] : []
        return first + out.shuffled()
    }

    /// Тренировка (вкладка «Повтор»): выученные слова + предложения из пройденных уроков.
    static func practice(words: [WordPair], pool: [WordPair], sentences: [SentencePair]) -> [Exercise] {
        let selected = Array(words.shuffled().prefix(8))
        var out: [Exercise] = []
        let matchable = distinctPairs(selected)
        if matchable.count >= 3 {
            out.append(match(Array(matchable.prefix(5))))
        }
        let shuffledPool = pool.shuffled()
        var rest: [Exercise] = []
        for (i, w) in selected.enumerated() {
            switch i % 3 {
            case 0: rest.append(choice(w, toSlovak: false, pool: shuffledPool))
            case 1: rest.append(choice(w, toSlovak: true, pool: shuffledPool))
            default: rest.append(typeWord(w))
            }
        }
        let picked = Array(sentences.shuffled().prefix(4))
        rest += sentenceExercises(picked, pool: sentences)
        return out + rest.shuffled()
    }

    /// Предложения по кругу: перевод на словацкий, аудирование, перевод на русский, диктант.
    private static func sentenceExercises(_ sentences: [SentencePair], pool: [SentencePair]) -> [Exercise] {
        let skTiles = pool.flatMap { tokens($0.sk) }
        let ruTiles = pool.flatMap { tokens($0.ru) }
        return sentences.enumerated().map { (i, s) -> Exercise in
            switch i % 4 {
            case 0: return buildSlovak(s, tilePool: skTiles, listening: false)
            case 1: return buildSlovak(s, tilePool: skTiles, listening: true)
            case 2: return buildRussian(s, tilePool: ruTiles)
            default:
                return tokens(s.sk).count <= 8 ? dictation(s) : buildSlovak(s, tilePool: skTiles, listening: false)
            }
        }
    }

    // MARK: - Отдельные типы

    static func choice(_ w: WordPair, toSlovak: Bool, pool: [WordPair], isNew: Bool = false) -> Exercise {
        let correct = toSlovak ? w.sk : w.ru
        var options = [correct]
        var usedMeanings = meanings(w.ru)
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
        return e
    }

    static func match(_ pairs: [WordPair]) -> Exercise {
        var e = Exercise(kind: .match, instruction: "Найдите пары")
        e.pairs = pairs
        return e
    }

    static func typeWord(_ w: WordPair) -> Exercise {
        var e = Exercise(kind: .typing, instruction: "Напишите по-словацки")
        e.prompt = w.ru
        e.answer = w.sk
        e.answerIsSlovak = true
        e.speakAfter = w.sk
        e.wordKey = w.sk
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

    // MARK: - Вспомогательное

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
