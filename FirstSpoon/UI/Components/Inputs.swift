import SwiftUI

/// Поле ввода: белое, 64, скругление 20, при фокусе — фиолетовая рамка. `error` — текст ошибки под полем.
struct AppTextField: View {
    @Binding var text: String
    var placeholder: String?
    var icon: String?
    var error: String?
    var multiline = false
    var keyboard: UIKeyboardType = .default
    var contentType: UITextContentType?
    var capitalization: TextInputAutocapitalization = .sentences
    var capsule = false
    var onSubmit: () -> Void = {}
    @FocusState private var focused: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: capsule ? 32 : AppRadius.medium, style: .continuous)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: multiline ? .top : .center, spacing: 14) {
                if let icon {
                    Image(systemName: icon).font(.system(size: 22, weight: .semibold)).foregroundStyle(AppColors.inkFaint)
                }
                Group {
                    if multiline {
                        TextField("", text: $text, prompt: prompt, axis: .vertical).lineLimit(3...8)
                    } else {
                        TextField("", text: $text, prompt: prompt)
                    }
                }
                .font(AppFont.onest(19, 400))
                .foregroundStyle(AppColors.ink)
                .tint(AppColors.primary)
                .keyboardType(keyboard)
                .textContentType(contentType)
                .textInputAutocapitalization(capitalization)
                .autocorrectionDisabled(keyboard == .emailAddress || keyboard == .numberPad)
                .focused($focused)
                .onSubmit(onSubmit)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 18)
            .frame(minHeight: 64)
            .background(AppColors.surface, in: shape)
            .overlay(shape.strokeBorder(error != nil ? AppColors.alert : (focused ? AppColors.primary : .clear), lineWidth: 2))
            .softShadow(radius: 6)
            .contentShape(shape)
            .onTapGesture { focused = true }
            if let error {
                Text(error).font(AppFont.bodyMedium).foregroundStyle(AppColors.alert).padding(.leading, 6)
            }
        }
    }

    private var prompt: Text? {
        placeholder.map { Text($0).foregroundStyle(AppColors.inkFaint) }
    }
}

/// Плитка выбора (реакция, приём пищи): белая, выбранная — фиолетовая рамка и светлый фон. С `emoji` — над подписью.
struct ChoiceTile: View {
    let label: String
    let selected: Bool
    var emoji: String?
    var minHeight: CGFloat = 64
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
        Button(action: action) {
            VStack(spacing: 8) {
                if let emoji { Text(emoji).font(.system(size: 34)) }
                Text(label).font(AppFont.labelLarge).foregroundStyle(AppColors.ink).multilineTextAlignment(.center)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, minHeight: minHeight, maxHeight: .infinity)
            .background(selected ? AppColors.primarySoft : AppColors.surface, in: shape)
            .overlay(shape.strokeBorder(selected ? AppColors.primary : .clear, lineWidth: 2))
            .softShadow(radius: selected ? 0 : 6)
            .contentShape(shape)
        }
        .buttonStyle(PressableStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Вариант ответа на всю ширину: эмодзи слева, подпись. Для вопросов с 3+ ответами.
struct ChoiceRow: View {
    let label: String
    let selected: Bool
    var emoji: String?
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
        Button(action: action) {
            HStack(spacing: 16) {
                if let emoji { Text(emoji).font(.system(size: 32)) }
                Text(label).font(AppFont.titleMedium).foregroundStyle(AppColors.ink)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .frame(minHeight: 76)
            .background(selected ? AppColors.primarySoft : AppColors.surface, in: shape)
            .overlay(shape.strokeBorder(selected ? AppColors.primary : .clear, lineWidth: 2))
            .softShadow(radius: selected ? 0 : 6)
            .contentShape(shape)
        }
        .buttonStyle(PressableStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Сегментированный переключатель на серо-бежевой подложке; выбранный сегмент — белый.
struct SegmentedControl<T: Hashable>: View {
    let options: [T]
    let selected: T?
    let label: (T) -> String
    let onSelect: (T) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.self) { option in
                let on = option == selected
                Button { onSelect(option) } label: {
                    Text(label(option)).font(AppFont.labelLarge).foregroundStyle(on ? AppColors.ink : AppColors.inkMuted)
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(on ? AppColors.surface : .clear, in: Capsule())
                        .softShadow(radius: on ? 4 : 0)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(5)
        .background(AppColors.surfaceSoft, in: Capsule())
    }
}

/// Чип-фильтр: белый с рамкой, выбранный — тёмный.
struct AppChip: View {
    let label: String
    let selected: Bool
    var expand = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label).font(AppFont.labelLarge).foregroundStyle(selected ? AppColors.surface : AppColors.ink).lineLimit(1)
                .padding(.horizontal, 20)
                .frame(maxWidth: expand ? .infinity : nil, minHeight: 48)
                .background(selected ? AppColors.ink : AppColors.surface, in: Capsule())
                .overlay(Capsule().strokeBorder(selected ? AppColors.ink : AppColors.line, lineWidth: 1.5))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
