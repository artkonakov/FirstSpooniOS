import SwiftUI
import FirstSpoonCore

/// Карточка «одна рекомендация»: продукт, почему (причины из движка), «Записать пробу» и «Другой».
/// Для паузы — объяснение без продукта-действия.
struct RecommendationCard: View {
    let rec: Recommendation
    let catalog: Catalog
    let onOpenProduct: (String) -> Void
    let onRecord: (String) -> Void
    let onOther: (String) -> Void

    var body: some View {
        if case .nothing = rec { EmptyView() } else if let id = rec.productId {
            AppCard(spacing: 14) {
                FieldLabel(title, inset: 0)
                if case .wait = rec {
                    ForEach(Array(rec.reasons.enumerated()), id: \.offset) { ReasonLine(text: reasonText($0.element, catalog)) }
                } else {
                    Button { onOpenProduct(id) } label: {
                        ProductRow(productId: id, name: catalog.productsById[id]?.name ?? id, supporting: { EmptyView() }, trailing: { Chevron() })
                    }
                    .buttonStyle(PressableStyle())
                    VStack(alignment: .leading, spacing: 6) {
                        let reasons = rec.reasons.isEmpty ? [Reason(.INTRO_ORDER)] : rec.reasons
                        ForEach(Array(reasons.enumerated()), id: \.offset) { ReasonLine(text: reasonText($0.element, catalog)) }
                    }
                    HStack(spacing: 10) {
                        AppButton(L.s("rec_record"), size: .medium, icon: "plus") { onRecord(id) }
                        if case .tryNew = rec {
                            AppButton(L.s("rec_other"), kind: .ghost, size: .medium, fill: false) { onOther(id) }
                        }
                    }
                }
            }
        }
    }

    private var title: String {
        switch rec {
        case .continueSeries: return L.s("rec_title_continue")
        case .wait: return L.s("rec_title_wait")
        default: return L.s("rec_title_try")
        }
    }
}

private struct ReasonLine: View {
    let text: String
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("•").font(AppFont.bodyLarge).foregroundStyle(AppColors.primary)
            Text(text).font(AppFont.bodyLarge).foregroundStyle(AppColors.inkMuted).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Текст причины для пользователя. Коды фильтров сюда не попадают (они только в debug).
func reasonText(_ r: Reason, _ catalog: Catalog) -> String {
    let a0 = r.args.first ?? ""
    switch r.code {
    case .CONTINUE_SERIES: return L.s("rec_reason_continue", r.args.first ?? "1")
    case .PAUSE_AFTER_REACTION:
        let date = r.args.count > 1 ? LocalDate.parse(r.args[1]).map(UiLocale.dayMonth) ?? "" : ""
        return L.s("rec_reason_pause", catalog.productsById[a0]?.name ?? a0, date)
    case .NEW_CATEGORY:
        return L.s("rec_reason_new_category", catalog.categories.first { $0.id == a0 }?.name.lowercased(with: UiLocale.locale) ?? a0)
    case .ALLERGEN_DUE: return L.s("rec_reason_allergen_due")
    case .FAVORITE: return L.s("rec_reason_favorite")
    case .AGE_FITS: return L.s("rec_reason_age")
    case .NOTHING_LEFT: return L.s("rec_reason_nothing")
    default: return L.s("rec_reason_basic")
    }
}
