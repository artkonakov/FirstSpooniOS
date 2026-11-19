import SwiftUI

/// Белая карточка со скруглением 28 — основной блок интерфейса.
/// Карточки не красим в цвет статуса: статус показывает `StatusBadge`.
struct AppCard<Content: View>: View {
    var padding: EdgeInsets = EdgeInsets(top: 20, leading: 20, bottom: 20, trailing: 20)
    var spacing: CGFloat = 16
    var selected = false
    var onTap: (() -> Void)?
    @ViewBuilder var content: () -> Content

    var body: some View {
        let card = VStack(alignment: .leading, spacing: spacing) { content() }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.surface, in: RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous))
            .overlay {
                if selected {
                    RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous).strokeBorder(AppColors.primary, lineWidth: 2)
                }
            }
            .softShadow()
        if let onTap {
            Button(action: onTap) { card.contentShape(RoundedRectangle(cornerRadius: AppRadius.large)) }
                .buttonStyle(PressableStyle())
        } else {
            card
        }
    }
}

/// Лёгкое затемнение при нажатии для карточек-кнопок.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.75 : 1)
            .scaleEffect(configuration.isPressed ? 0.99 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Заголовок экрана — крупный, 40.
struct ScreenTitle: View {
    let text: String
    var subtitle: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(text).font(AppFont.displaySmall).foregroundStyle(AppColors.ink)
            if let subtitle {
                Text(subtitle).font(AppFont.bodyLarge).foregroundStyle(AppColors.inkMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }
}

/// Заголовок секции — 26, с воздухом сверху.
struct SectionTitle<Trailing: View>: View {
    let text: String
    @ViewBuilder var trailing: () -> Trailing
    var body: some View {
        HStack {
            Text(text).font(AppFont.headlineSmall).foregroundStyle(AppColors.ink)
            Spacer()
            trailing()
        }
        .padding(.top, 20)
        .padding(.bottom, 4)
    }
}

extension SectionTitle where Trailing == EmptyView {
    init(_ text: String) { self.init(text: text, trailing: { EmptyView() }) }
}

/// Небольшая подпись над полем/группой («Количество», «Реакция»).
struct FieldLabel: View {
    let text: String
    var inset: CGFloat = 6
    init(_ text: String, inset: CGFloat = 6) { self.text = text; self.inset = inset }
    var body: some View {
        Text(text).font(AppFont.titleSmall).foregroundStyle(AppColors.inkMuted)
            .padding(.leading, inset)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Строка-действие в белой карточке: иконка, заголовок, значение справа, шеврон при `onTap`.
struct ActionRow: View {
    let title: String
    var value: String?
    var icon: String?
    var titleColor: Color = AppColors.ink
    var onTap: (() -> Void)?

    var body: some View {
        AppCard(padding: EdgeInsets(top: 18, leading: 20, bottom: 18, trailing: 20), onTap: onTap) {
            HStack(spacing: 14) {
                if let icon {
                    Image(systemName: icon).font(.system(size: 22, weight: .semibold)).foregroundStyle(AppColors.primary)
                }
                Text(title).font(AppFont.titleMedium).foregroundStyle(titleColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let value { Text(value).font(AppFont.bodyLarge).foregroundStyle(AppColors.inkMuted) }
                if onTap != nil { Chevron() }
            }
        }
    }
}

/// Пустое состояние: крупный эмодзи, заголовок, пояснение.
struct EmptyState: View {
    let emoji: String
    let title: String
    let text: String
    var body: some View {
        VStack(spacing: 10) {
            Text(emoji).font(.system(size: 56))
            Text(title).font(AppFont.titleLarge).foregroundStyle(AppColors.ink)
            Text(text).font(AppFont.bodyLarge).foregroundStyle(AppColors.inkMuted)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .padding(.horizontal, 12)
    }
}

/// Прогресс шагов онбординга: сегменты, пройденные — фиолетовые.
struct StepIndicator: View {
    let current: Int
    let total: Int
    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<total, id: \.self) { i in
                Capsule().fill(i <= current ? AppColors.primary : AppColors.surfaceSoft).frame(height: 6)
            }
        }
    }
}

/// Строка-переключатель в белой карточке: заголовок, пояснение, Toggle справа.
struct SwitchRow: View {
    let title: String
    var subtitle: String?
    @Binding var isOn: Bool
    var body: some View {
        AppCard(padding: EdgeInsets(top: 16, leading: 20, bottom: 16, trailing: 20)) {
            Toggle(isOn: $isOn) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(AppFont.titleMedium).foregroundStyle(AppColors.ink)
                    if let subtitle { Text(subtitle).font(AppFont.bodyMedium).foregroundStyle(AppColors.inkMuted) }
                }
            }
            .tint(AppColors.primary)
        }
    }
}

struct Chevron: View {
    var body: some View {
        Image(systemName: "chevron.right").font(.system(size: 18, weight: .bold)).foregroundStyle(AppColors.ink)
            .padding(.leading, 4)
    }
}

/// Перенос элементов по строкам (чипы).
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(proposal.width ?? .infinity, subviews)
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0,
                      height: rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(rows.count - 1, 0)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(bounds.width, subviews) {
            var x = bounds.minX
            for i in row.items {
                let size = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var items: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(_ maxWidth: CGFloat, _ subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for i in subviews.indices {
            let size = subviews[i].sizeThatFits(.unspecified)
            if !rows[rows.count - 1].items.isEmpty && rows[rows.count - 1].width + spacing + size.width > maxWidth {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width += (row.items.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.items.append(i)
            rows[rows.count - 1] = row
        }
        return rows
    }
}

/// Экран на тёплом фоне. Навигационная панель — системная (заголовок через `.navigationTitle`).
struct ScreenBackground: ViewModifier {
    func body(content: Content) -> some View {
        content.background(AppColors.background.ignoresSafeArea())
    }
}

extension View {
    func appScreen() -> some View { modifier(ScreenBackground()) }
}

extension View {
    /// Главная кнопка экрана внизу (над таб-баром / home indicator) на мягкой подложке цвета фона.
    func bottomAction<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) {
            // Подложка уходит и под home indicator — иначе ниже кнопки просвечивает прокручиваемое содержимое.
            content().background {
                LinearGradient(colors: [AppColors.background.opacity(0), AppColors.background, AppColors.background],
                               startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea(edges: .bottom)
            }
        }
    }
}
