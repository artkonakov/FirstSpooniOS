import SwiftUI
import FirstSpoonCore

/// Карточка «одна рекомендация» (Android `docs/product-rules.md` «Главный экран»): продукт и одна главная причина абзацем.
/// Записывают пробу общей кнопкой внизу экрана (форма открывается с этим продуктом), поэтому кнопки записи здесь нет.
/// «Предложить другой» — только для нового продукта: серию не подменяем. Порт Android `RecommendationCard.kt`.
struct RecommendationCard: View {
    let rec: Recommendation
    let catalog: Catalog
    let onOpenProduct: (String) -> Void
    let onOther: (String) -> Void
    /// «Малыш уже держит голову и сидит» на карточке «Пока готовимся»; nil — кнопку не показываем.
    var onMarkReady: (() -> Void)?

    var body: some View {
        switch rec {
        case .notReady(let readiness, _):
            let tooEarly = readiness == .tooEarly
            AppCard(spacing: 10) {
                FieldLabel(L.s("rec_title_not_ready"), inset: 0).padding(.bottom, 4)
                Text(L.s(tooEarly ? "rec_not_ready_too_early" : "rec_not_ready_skills"))
                    .font(AppFont.bodyLarge).foregroundStyle(AppColors.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                // Младше 6 месяцев кнопки нет: дело в возрасте, навыки не помогут.
                if !tooEarly, let onMarkReady {
                    AppButton(L.s("rec_mark_ready"), kind: .soft, size: .medium, action: onMarkReady)
                }
            }
        case .done:
            TextCard(title: L.s("rec_title_done"), text: L.s("rec_reason_done"))
        case .nothing:
            TextCard(title: L.s("rec_title_nothing"), text: L.s("rec_reason_nothing"))
        case .wait(_, _, let reasons):
            TextCard(title: L.s("rec_title_wait"), text: reasons.first.map { reasonText($0, catalog) } ?? "",
                     note: L.s("rec_reason_pause_doctor"), emphasize: true)
        case .tryNew(let id, let reasons), .continueSeries(let id, _, let reasons):
            AppCard(spacing: 14) {
                FieldLabel(L.s(isContinue ? "rec_title_continue" : "rec_title_try"), inset: 0)
                // Тап по продукту — его страница (без шеврона, как в Android).
                Button { onOpenProduct(id) } label: {
                    ProductRow(productId: id, name: catalog.productsById[id]?.name ?? id, supporting: { EmptyView() }, trailing: { EmptyView() })
                }
                .buttonStyle(PressableStyle())
                // Одна главная причина (самая весомая), законченной фразой — без маркеров списка.
                Text(reasonText(reasons.first ?? Reason(.INTRO_ORDER), catalog))
                    .font(AppFont.bodyLarge).foregroundStyle(AppColors.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                if !isContinue {
                    AppButton(L.s("rec_other"), kind: .soft, size: .medium, icon: "ic_refresh") { onOther(id) }
                }
            }
        }
    }

    private var isContinue: Bool { if case .continueSeries = rec { return true } else { return false } }
}

/// Карточка без продукта: заголовок и абзац; `note` — второй абзац мельче (например, когда к врачу).
private struct TextCard: View {
    let title: String
    let text: String
    var note: String?
    var emphasize = false
    var body: some View {
        AppCard(spacing: 10) {
            FieldLabel(title, inset: 0).padding(.bottom, 4)
            Text(text).font(AppFont.bodyLarge).foregroundStyle(emphasize ? AppColors.ink : AppColors.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
            if let note {
                Text(note).font(AppFont.bodyMedium).foregroundStyle(AppColors.inkMuted).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Текст причины для пользователя. Коды фильтров сюда не попадают (они только в debug).
func reasonText(_ r: Reason, _ catalog: Catalog) -> String {
    let a0 = r.args.first ?? ""
    switch r.code {
    case .CONTINUE_SERIES: return L.s("rec_reason_continue", r.args.first ?? "1")
    case .PAUSE_AFTER_REACTION:
        let date = r.args.count > 1 ? LocalDate.parse(r.args[1]).map { UiLocale.dayMonth($0).replacingOccurrences(of: " ", with: "\u{00A0}") } ?? "" : ""
        return L.s("rec_reason_pause", catalog.productsById[a0]?.name ?? a0, date)
    case .NEW_CATEGORY:
        return L.s("rec_reason_new_category", catalog.categories.first { $0.id == a0 }?.name.lowercased(with: UiLocale.locale) ?? a0)
    case .ALLERGEN_DUE: return L.s("rec_reason_allergen_due")
    case .FAVORITE: return L.s("rec_reason_favorite")
    case .AGE_FITS: return L.s("rec_reason_age")
    case .NOTHING_LEFT: return L.s("rec_reason_nothing")
    case .DONE_TODAY: return L.s("rec_reason_done")
    case .STAGE: return Strategies.stageReason(a0, lang: AppLocale.current().rawValue) ?? L.s("rec_reason_basic")
    default: return L.s("rec_reason_basic")
    }
}
