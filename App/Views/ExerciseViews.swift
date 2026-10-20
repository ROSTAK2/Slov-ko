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

/// Талисман приложения — словечко в облачке.
struct Mascot: View {
    var size: CGFloat = 54

    var body: some View {
        ZStack {
            Circle().fill(Theme.blue)
            Circle().stroke(Color.white, lineWidth: size * 0.06).padding(size * 0.08)
            Text("Sk")
                .font(.system(size: size * 0.38, weight: .black, design: .rounded))
                .foregroundColor(.white)
            Circle()
                .fill(Theme.red)
                .frame(width: size * 0.22, height: size * 0.22)
                .offset(x: size * 0.34, y: -size * 0.34)
        }
        .frame(width: size, height: size)
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

// MARK: - Выбор варианта

struct ChoiceExerciseView: View {
    let exercise: Exercise
    @Binding var selection: String?
    let locked: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            InstructionText(text: exercise.instruction)
            PromptBubble(exercise: exercise)
            VStack(spacing: 12) {
                ForEach(Array(exercise.options.enumerated()), id: \.offset) { index, option in
                    Button {
                        guard !locked else { return }
                        Haptics.tap()
                        selection = option
                        if exercise.optionsSlovak { Speech.shared.speak(option) }
                    } label: {
                        OptionCard(selected: selection == option) {
                            HStack(spacing: 12) {
                                Text("\(index + 1)")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundColor(.secondary)
                                    .frame(width: 26, height: 26)
                                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(.systemGray4), lineWidth: 1.5))
                                Text(option)
                                    .font(.body.weight(.semibold))
                                    .foregroundColor(.primary)
                                    .multilineTextAlignment(.leading)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Собрать из плиток

struct WordTile: View {
    let text: String
    var ghost = false

    var body: some View {
        Text(text)
            .font(.body.weight(.semibold))
            .foregroundColor(ghost ? .clear : .primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(ghost ? Color(.systemGray5) : Color(.secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(.systemGray4), lineWidth: ghost ? 0 : 1.5)
            )
            .shadow(color: ghost ? .clear : Color(.systemGray4), radius: 0, x: 0, y: 2)
    }
}

struct BuildExerciseView: View {
    let exercise: Exercise
    @Binding var answer: String?
    let locked: Bool
    @State private var picked: [Int] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            InstructionText(text: exercise.instruction)
            PromptBubble(exercise: exercise)

            FlowLayout(spacing: 8) {
                ForEach(picked, id: \.self) { index in
                    Button {
                        guard !locked else { return }
                        Haptics.tap()
                        picked.removeAll { $0 == index }
                        update()
                    } label: {
                        WordTile(text: exercise.options[index])
                    }
                    .buttonStyle(.plain)
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
                        guard !locked, !used else { return }
                        Haptics.tap()
                        picked.append(index)
                        update()
                        if exercise.optionsSlovak { Speech.shared.speak(exercise.options[index]) }
                    } label: {
                        WordTile(text: exercise.options[index], ghost: used)
                    }
                    .buttonStyle(.plain)
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
    let locked: Bool
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            InstructionText(text: exercise.instruction)
            PromptBubble(exercise: exercise)
            TextField(exercise.answerIsSlovak ? "Напишите по-словацки" : "Напишите ответ", text: $text, axis: .vertical)
                .lineLimit(2...5)
                .font(.title3)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focused)
                .disabled(locked)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemGroupedBackground)))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(.systemGray4), lineWidth: 1.5))
                .onChange(of: text) { value in
                    answer = value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : value
                }
            if exercise.answerIsSlovak && !locked {
                DiacriticsBar { letter in text.append(letter) }
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { focused = true }
        }
    }
}

// MARK: - Пропуск в предложении

struct FillExerciseView: View {
    let exercise: Exercise
    @Binding var selection: String?
    let locked: Bool

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
                    Button {
                        guard !locked else { return }
                        Haptics.tap()
                        selection = option
                        Speech.shared.speak(option)
                    } label: {
                        Text(option)
                            .font(.body.weight(.semibold))
                            .foregroundColor(.primary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(selection == option ? Theme.blue.opacity(0.12) : Color(.secondarySystemGroupedBackground))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(selection == option ? Theme.blue : Color(.systemGray4), lineWidth: 2)
                            )
                    }
                    .buttonStyle(.plain)
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
                        cell(text: pair.sk, key: pair.sk, selected: selectedLeft == pair.sk, wrong: wrongLeft == pair.sk) {
                            selectedLeft = pair.sk
                            Speech.shared.speak(pair.sk)
                            tryMatch()
                        }
                    }
                }
                VStack(spacing: 12) {
                    ForEach(right, id: \.sk) { pair in
                        cell(text: pair.ru, key: pair.sk, selected: selectedRight == pair.sk, wrong: wrongRight == pair.sk) {
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

    private func cell(text: String, key: String, selected: Bool, wrong: Bool, action: @escaping () -> Void) -> some View {
        let done = matched.contains(key)
        let tint: Color = wrong ? Theme.red : (selected ? Theme.blue : Color(.systemGray4))
        return Button {
            guard !done else { return }
            Haptics.tap()
            action()
        } label: {
            Text(text)
                .font(.body.weight(.semibold))
                .foregroundColor(done ? Color(.systemGray3) : (wrong ? Theme.red : .primary))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 54)
                .padding(.horizontal, 6)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(selected && !done ? Theme.blue.opacity(0.12) : Color(.secondarySystemGroupedBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(done ? Color(.systemGray5) : tint, lineWidth: 2)
                )
        }
        .buttonStyle(.plain)
        .disabled(done)
    }

    private func tryMatch() {
        guard let l = selectedLeft, let r = selectedRight else { return }
        if l == r {
            withAnimation(.easeOut(duration: 0.2)) {
                _ = matched.insert(l)
            }
            selectedLeft = nil
            selectedRight = nil
            if matched.count == exercise.pairs.count {
                onComplete()
            }
        } else {
            Haptics.error()
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
