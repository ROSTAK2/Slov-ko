import SwiftUI
import UIKit

enum Keyboards {
    /// Установлена ли на iPhone словацкая клавиатура.
    static var hasSlovak: Bool {
        UITextInputMode.activeInputModes.contains { ($0.primaryLanguage ?? "").hasPrefix("sk") }
    }
}

/// UITextField, который просит систему открыть клавиатуру нужного языка
/// (если она добавлена в Настройках). Так для словацких ответов сразу
/// открывается словацкая клавиатура с č, š, ž, ä, ô…
final class LanguageTextField: UITextField {
    var preferredLanguage = "sk"

    override var textInputMode: UITextInputMode? {
        UITextInputMode.activeInputModes.first { ($0.primaryLanguage ?? "").hasPrefix(preferredLanguage) }
            ?? super.textInputMode
    }
}

struct KeyboardTextField: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var language: String = "sk"
    var isEnabled: Bool = true
    var autoFocus: Bool = true
    var fontSize: CGFloat = 20
    var onSubmit: () -> Void = {}

    func makeUIView(context: Context) -> LanguageTextField {
        let field = LanguageTextField()
        field.preferredLanguage = language
        field.placeholder = placeholder
        field.font = UIFont.systemFont(ofSize: fontSize, weight: .medium)
        field.autocorrectionType = .no
        field.autocapitalizationType = .none
        field.spellCheckingType = .no
        field.smartQuotesType = .no
        field.smartDashesType = .no
        field.returnKeyType = .done
        field.clearButtonMode = .whileEditing
        field.delegate = context.coordinator
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        if autoFocus {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if field.window != nil { field.becomeFirstResponder() }
            }
        }
        return field
    }

    func updateUIView(_ field: LanguageTextField, context: Context) {
        context.coordinator.parent = self
        if field.text != text {
            field.text = text
        }
        if field.isEnabled != isEnabled {
            field.isEnabled = isEnabled
            if !isEnabled { field.resignFirstResponder() }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: KeyboardTextField

        init(parent: KeyboardTextField) {
            self.parent = parent
        }

        @objc func changed(_ field: UITextField) {
            parent.text = field.text ?? ""
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            parent.onSubmit()
            return false
        }
    }
}

/// Подсказка, если словацкая клавиатура не установлена.
struct SlovakKeyboardHint: View {
    @State private var showHelp = false

    var body: some View {
        Button {
            showHelp = true
        } label: {
            Label("Добавьте словацкую клавиатуру — она откроется здесь сама", systemImage: "keyboard")
                .font(.footnote)
                .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
        .alert("Словацкая клавиатура", isPresented: $showHelp) {
            Button("Понятно", role: .cancel) {}
        } message: {
            Text("Настройки → Основные → Клавиатура → Клавиатуры → Новые клавиатуры → Словацкая.\n\nПосле этого в заданиях на словацком она будет открываться автоматически.")
        }
    }
}
