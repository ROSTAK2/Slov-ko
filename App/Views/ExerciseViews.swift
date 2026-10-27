import SwiftUI

// MARK: - Общий блок с заданием

struct PromptBubble: View {
    let exercise: Exercise

    var body: some View {
        Group {
            if exercise.listening, let audio = exercise.promptAudio {
                HStack(spacing: 18) {
                    SpeakerButton(text: audio, big: true)
                    SpeakerButton(text: audio, slow: true)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            } else if !exercise.prompt.isEmpty {
                HStack(alignment: .center, spacing: 12) {
                    Mascot(size: 54)
                    HStack(alignment: .top, spacing: 10) {
                        if let audio = exercise.promptAudio {
                            SpeakerButton(text: audio)
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            if exercise.isNew {
                                NewWordBadge()
                            }
                            if let hints = exercise.hints {
                                HintedText(words: hints, slovak: exercise.hintsSlovak)
                            } else {
                                Text(exercise.prompt)
                                    .font(.title3.weight(.semibold))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemGroupedBackground)))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(.systemGray4), lineWidth: 1.5))
                }
            }
        }
        .onAppear {
            guard exercise.autoplay, let audio = exercise.promptAudio else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                Speech.shared.speak(audio)
            }
        }
    }
}

/// Талисман приложения — герб в звёздах ЕС.
struct Mascot: View {
    var size: CGFloat = 54

    var body: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: [Color(hex: 0x1856C4), Color(hex: 0x003399)],
                                     startPoint: .top, endPoint: .bottom))
            ForEach(0..<12, id: \.self) { i in
                Image(systemName: "star.fill")
                    .font(.system(size: size * 0.085))
                    .foregroundColor(Color(hex: 0xFFCC00))
                    .offset(y: -size * 0.39)
                    .frame(width: size, height: size)   // поворот вокруг центра круга
                    .rotationEffect(.degrees(Double(i) * 30))
            }
            CoatOfArms()
                .frame(width: size * 0.44, height: size * 0.52)
                .offset(y: size * 0.02)
        }
        .frame(width: size, height: size)
    }
}

/// Стилизованный герб: красный щит, белый двойной крест на синих холмах.
struct CoatOfArms: View {
    private let red = Color(hex: 0xEE1C25)
    private let blue = Color(hex: 0x0B4EA2)

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                ShieldShape().fill(red)
                Circle().fill(blue).frame(width: w * 0.46, height: w * 0.46).position(x: w * 0.5, y: h * 0.86)
                Circle().fill(blue).frame(width: w * 0.42, height: w * 0.42).position(x: w * 0.14, y: h * 0.94)
                Circle().fill(blue).frame(width: w * 0.42, height: w * 0.42).position(x: w * 0.86, y: h * 0.94)
                Rectangle().fill(Color.white).frame(width: w * 0.12, height: h * 0.6).position(x: w * 0.5, y: h * 0.43)
                Rectangle().fill(Color.white).frame(width: w * 0.44, height: w * 0.11).position(x: w * 0.5, y: h * 0.28)
                Rectangle().fill(Color.white).frame(width: w * 0.66, height: w * 0.12).position(x: w * 0.5, y: h * 0.45)
            }
            .clipShape(ShieldShape())
            .overlay(ShieldShape().stroke(Color.white, lineWidth: max(1, w * 0.05)))
        }
    }
}

struct ShieldShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let straight = rect.minY + rect.height * 0.45
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: straight))
        path.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.maxY),
                          control: CGPoint(x: rect.maxX, y: rect.maxY - rect.height * 0.1))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: straight),
                          control: CGPoint(x: rect.minX, y: rect.maxY - rect.height * 0.1))
        path.closeSubpath()
        return path
    }
}

struct InstructionText: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.title2.weight(.heavy))
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Цвет варианта после проверки: правильный — зелёный, выбранный неверный — красный.
enum OptionState {
    case normal, selected, correct, wrong, dimmed

    static func of(_ option: String, selection: String?, answer: String, result: CheckResult?) -> OptionState {
        guard let result else { return selection == option ? .selected : .normal }
        if Checker.normalize(option) == Checker.normalize(answer) { return .correct }
        if selection == option && result == .wrong { return .wrong }
        return .dimmed
    }

    var tint: Color {
        switch self {
        case .correct: return Theme.green
        case .wrong: return Theme.red
        case .selected: return Theme.blue
        default: return Color(.systemGray4)
        }
    }

    var highlighted: Bool { self == .selected || self == .correct || self == .wrong }
}

// MARK: - Выбор варианта

struct ChoiceExerciseView: View {
    let exercise: Exercise
    @Binding var selection: String?
    let result: CheckResult?

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            InstructionText(text: exercise.instruction)
            PromptBubble(exercise: exercise)
            VStack(spacing: 12) {
                ForEach(Array(exercise.options.enumerated()), id: \.offset) { index, option in
                    let state = OptionState.of(option, selection: selection, answer: exercise.answer, result: result)
                    Button {
                        guard result == nil else { return }
                        Haptics.tap()
                        selection = option
                        if exercise.optionsSlovak { Speech.shared.speak(option) }
                    } label: {
                        HStack(spacing: 12) {
                            Text("\(index + 1)")
                                .font(.subheadline.weight(.bold))
                                .foregroundColor(state.highlighted ? state.tint : .secondary)
                                .frame(width: 26, height: 26)
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(state.highlighted ? state.tint : Color(.systemGray4), lineWidth: 1.5))
                            Text(option)
                                .font(.body.weight(.semibold))
                                .foregroundColor(state == .dimmed ? .secondary : .primary)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                            if state == .correct {
                                Image(systemName: "checkmark.circle.fill").foregroundColor(Theme.green)
                            } else if state == .wrong {
                                Image(systemName: "xmark.circle.fill").foregroundColor(Theme.red)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(state.highlighted ? state.tint.opacity(0.12) : Color(.secondarySystemGroupedBackground))
                        )
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(state.tint, lineWidth: 2))
                        .shadow(color: state.highlighted ? .clear : Color(.systemGray4), radius: 0, x: 0, y: 2)
                    }
                    .buttonStyle(PressScale())
                    .animation(.easeOut(duration: 0.2), value: state)
                }
            }
        }
    }
}

// MARK: - Собрать из плиток

struct WordTile: View {
    let text: String
    var ghost = false
    var tint: Color? = nil

    var body: some View {
        Text(text)
            .font(.body.weight(.semibold))
            .foregroundColor(ghost ? .clear : (tint ?? .primary))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(ghost ? Color(.systemGray5) : (tint?.opacity(0.12) ?? Color(.secondarySystemGroupedBackground)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(tint ?? Color(.systemGray4), lineWidth: ghost ? 0 : 1.5)
            )
            .shadow(color: ghost ? .clear : Color(.systemGray4), radius: 0, x: 0, y: 2)
    }
}

struct BuildExerciseView: View {
    let exercise: Exercise
    @Binding var answer: String?
    let result: CheckResult?
    @State private var picked: [Int] = []

    private var answerTint: Color? {
        guard let result else { return nil }
        return result == .wrong ? Theme.red : Theme.green
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            InstructionText(text: exercise.instruction)
            PromptBubble(exercise: exercise)

            FlowLayout(spacing: 8) {
                ForEach(picked, id: \.self) { index in
                    Button {
                        guard result == nil else { return }
                        Haptics.tap()
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                            picked.removeAll { $0 == index }
                        }
                        update()
                    } label: {
                        WordTile(text: exercise.options[index], tint: answerTint)
                    }
                    .buttonStyle(PressScale())
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
            .padding(.vertical, 6)
            .background(alignment: .top) {
                VStack(spacing: 50) {
                    Divider()
                    Divider()
                }
                .padding(.top, 52)
            }

            FlowLayout(spacing: 8) {
                ForEach(exercise.options.indices, id: \.self) { index in
                    let used = picked.contains(index)
                    Button {
                        guard result == nil, !used else { return }
                        Haptics.tap()
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                            picked.append(index)
                        }
                        update()
                        if exercise.optionsSlovak { Speech.shared.speak(exercise.options[index]) }
                    } label: {
                        WordTile(text: exercise.options[index], ghost: used)
                    }
                    .buttonStyle(PressScale())
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func update() {
        answer = picked.isEmpty ? nil : picked.map { exercise.options[$0] }.joined(separator: " ")
    }
}

// MARK: - Напечатать

struct TypeExerciseView: View {
    let exercise: Exercise
    @Binding var answer: String?
    let result: CheckResult?
    var onSubmit: () -> Void = {}
    @State private var text = ""

    private var borderColor: Color {
        guard let result else { return Color(.systemGray4) }
        return result == .wrong ? Theme.red : Theme.green
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            InstructionText(text: exercise.instruction)
            PromptBubble(exercise: exercise)
            KeyboardTextField(
                text: $text,
                placeholder: exercise.answerIsSlovak ? "Napíšte po slovensky…" : "Напишите ответ",
                language: exercise.answerIsSlovak ? "sk" : "ru",
                isEnabled: result == nil,
                onSubmit: onSubmit
            )
            .frame(height: 30)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemGroupedBackground)))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(borderColor, lineWidth: 2))
            .onChange(of: text) { value in
                answer = value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : value
            }
            if exercise.answerIsSlovak && result == nil && !Keyboards.hasSlovak {
                DiacriticsBar { letter in text.append(letter) }
                SlovakKeyboardHint()
            }
        }
    }
}

// MARK: - Пропуск в предложении

struct FillExerciseView: View {
    let exercise: Exercise
    @Binding var selection: String?
    let result: CheckResult?

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            InstructionText(text: exercise.instruction)
            HStack(alignment: .top, spacing: 12) {
                Mascot(size: 54)
                VStack(alignment: .leading, spacing: 8) {
                    if let hints = exercise.hints {
                        HintedText(words: hints, slovak: true, blank: selection)
                    } else {
                        sentence
                            .font(.title3.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !exercise.prompt.isEmpty {
                        Text(exercise.prompt)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemGroupedBackground)))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(.systemGray4), lineWidth: 1.5))
            }
            FlowLayout(spacing: 10) {
                ForEach(exercise.options, id: \.self) { option in
                    let state = OptionState.of(option, selection: selection, answer: exercise.answer, result: result)
                    Button {
                        guard result == nil else { return }
                        Haptics.tap()
                        selection = option
                        Speech.shared.speak(option)
                    } label: {
                        Text(option)
                            .font(.body.weight(.semibold))
                            .foregroundColor(state == .dimmed ? .secondary : .primary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(state.highlighted ? state.tint.opacity(0.12) : Color(.secondarySystemGroupedBackground))
                            )
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(state.tint, lineWidth: 2))
                            .shadow(color: state.highlighted ? .clear : Color(.systemGray4), radius: 0, x: 0, y: 2)
                    }
                    .buttonStyle(PressScale())
                    .animation(.easeOut(duration: 0.2), value: state)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var sentence: Text {
        let template = exercise.template ?? ""
        let parts = template.components(separatedBy: "___")
        let before = parts.first ?? ""
        let after = parts.count > 1 ? parts[1...].joined(separator: "___") : ""
        let blank = selection ?? "_____"
        return Text(before)
            + Text(blank).foregroundColor(Theme.blue).underline()
            + Text(after)
    }
}

// MARK: - Найдите ошибку

struct SpotErrorView: View {
    let exercise: Exercise
    @Binding var selection: String?
    let result: CheckResult?

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            InstructionText(text: exercise.instruction)
            HStack(alignment: .top, spacing: 12) {
                Mascot(size: 54)
                Text(exercise.prompt)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemGroupedBackground)))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(.systemGray4), lineWidth: 1.5))
            }
            Text("Нажмите на неправильное слово:")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)
            FlowLayout(spacing: 8) {
                ForEach(Array(exercise.spotTokens.enumerated()), id: \.offset) { index, token in
                    let key = "\(index)"
                    let state = OptionState.of(key, selection: selection, answer: exercise.answer, result: result)
                    Button {
                        guard result == nil else { return }
                        Haptics.tap()
                        selection = key
                    } label: {
                        Text(token)
                            .font(.title3.weight(.semibold))
                            .foregroundColor(state.highlighted ? state.tint : .primary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(state.highlighted ? state.tint.opacity(0.14) : Color(.secondarySystemGroupedBackground))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(state.highlighted ? state.tint : Color(.systemGray5), lineWidth: 2)
                            )
                    }
                    .buttonStyle(PressScale())
                    .animation(.easeOut(duration: 0.2), value: state)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Произнесите вслух

struct SpeakExerciseView: View {
    let exercise: Exercise
    @Binding var answer: String?
    let result: CheckResult?
    let onSkip: () -> Void
    @StateObject private var recognizer = SpeechRecognizer()
    @State private var pulse = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            InstructionText(text: exercise.instruction)
            PromptBubble(exercise: exercise)
            VStack(spacing: 14) {
                Button {
                    Haptics.tap()
                    recognizer.toggle()
                } label: {
                    ZStack {
                        if recognizer.isRecording {
                            Circle()
                                .stroke(Theme.red.opacity(0.35), lineWidth: 8)
                                .frame(width: 122, height: 122)
                                .scaleEffect(pulse ? 1.18 : 0.95)
                                .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: pulse)
                                .onAppear { pulse = true }
                                .onDisappear { pulse = false }
                        }
                        Circle()
                            .fill(recognizer.isRecording ? Theme.red : Theme.blue)
                            .frame(width: 96, height: 96)
                            .shadow(color: (recognizer.isRecording ? Theme.red : Theme.blue).opacity(0.4), radius: 10, y: 4)
                        Image(systemName: recognizer.isRecording ? "stop.fill" : "mic.fill")
                            .font(.system(size: 36, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .frame(width: 130, height: 130)
                }
                .buttonStyle(PressScale())
                .disabled(result != nil)

                Text(statusText)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                if !recognizer.transcript.isEmpty {
                    Text(recognizer.transcript)
                        .font(.title3.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .transition(.opacity)
                }
                if let error = recognizer.error {
                    Text(error)
                        .font(.footnote)
                        .foregroundColor(Theme.red)
                        .multilineTextAlignment(.center)
                }
                if result == nil {
                    Button("Сейчас не могу говорить") {
                        recognizer.stop()
                        onSkip()
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .onChange(of: recognizer.transcript) { value in
            answer = value.isEmpty ? nil : value
        }
        .onDisappear { recognizer.stop() }
    }

    private var statusText: String {
        if recognizer.isRecording { return "Говорите… Нажмите ещё раз, чтобы закончить" }
        if recognizer.transcript.isEmpty { return "Нажмите на микрофон и прочитайте фразу вслух" }
        return "Распознано:"
    }
}

// MARK: - Пары

struct MatchExerciseView: View {
    let exercise: Exercise
    let onComplete: () -> Void

    @State private var left: [WordPair] = []
    @State private var right: [WordPair] = []
    @State private var selectedLeft: String?
    @State private var selectedRight: String?
    @State private var matched: Set<String> = []
    @State private var wrongLeft: String?
    @State private var wrongRight: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            InstructionText(text: exercise.instruction)
            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 12) {
                    ForEach(left, id: \.sk) { pair in
                        cell(text: pair.sk, key: pair.sk, audio: exercise.audioPairs,
                             selected: selectedLeft == pair.sk, wrong: wrongLeft == pair.sk) {
                            selectedLeft = pair.sk
                            Speech.shared.speak(pair.sk)
                            tryMatch()
                        }
                    }
                }
                VStack(spacing: 12) {
                    ForEach(right, id: \.sk) { pair in
                        cell(text: pair.ru, key: pair.sk, audio: false,
                             selected: selectedRight == pair.sk, wrong: wrongRight == pair.sk) {
                            selectedRight = pair.sk
                            tryMatch()
                        }
                    }
                }
            }
        }
        .onAppear {
            if left.isEmpty {
                left = exercise.pairs.shuffled()
                right = exercise.pairs.shuffled()
            }
        }
    }

    private func cell(text: String, key: String, audio: Bool, selected: Bool, wrong: Bool,
                      action: @escaping () -> Void) -> some View {
        let done = matched.contains(key)
        let tint: Color = done ? Theme.green : (wrong ? Theme.red : (selected ? Theme.blue : Color(.systemGray4)))
        return Button {
            guard !done else { return }
            Haptics.tap()
            action()
        } label: {
            Group {
                if audio && !done {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.title3.weight(.bold))
                        .foregroundColor(selected ? Theme.blue : .secondary)
                } else {
                    Text(text)
                        .font(.body.weight(.semibold))
                        .foregroundColor(done ? Theme.green.opacity(0.7) : (wrong ? Theme.red : .primary))
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 54)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(done ? Theme.green.opacity(0.08) : (selected ? Theme.blue.opacity(0.12) : Color(.secondarySystemGroupedBackground)))
            )
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(tint, lineWidth: 2))
            .scaleEffect(done ? 0.96 : 1)
            .opacity(done ? 0.6 : 1)
        }
        .buttonStyle(PressScale())
        .modifier(Shake(amount: 6, shakes: 3, animatableData: wrong ? 1 : 0))
        .animation(.easeOut(duration: 0.3), value: wrong)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: done)
        .disabled(done)
    }

    private func tryMatch() {
        guard let l = selectedLeft, let r = selectedRight else { return }
        if l == r {
            withAnimation(.easeOut(duration: 0.2)) {
                _ = matched.insert(l)
            }
            if matched.count < exercise.pairs.count { SoundFX.shared.play(.pop) }
            selectedLeft = nil
            selectedRight = nil
            if matched.count == exercise.pairs.count {
                onComplete()
            }
        } else {
            Haptics.error()
            SoundFX.shared.play(.wrong)
            wrongLeft = l
            wrongRight = r
            selectedLeft = nil
            selectedRight = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                wrongLeft = nil
                wrongRight = nil
            }
        }
    }
}
