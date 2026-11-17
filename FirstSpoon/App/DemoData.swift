#if DEBUG
import Foundation
import FirstSpoonCore

/// Только debug: демо-данные для скриншотов в App Store — те же, что Android `DemoDataActivity`
/// (ребёнок «Маша», серии проб, отметки, избранное, «Требуют внимания», «Вводим сейчас»).
///
/// Запуск на **чистой установке** вместе с `-debug_offline YES`, чтобы гость не создал аккаунт на боевом сервере:
///     xcrun simctl launch <udid> app.littlebite.dev -demo_data YES -debug_offline YES
/// Существующие данные не стираются: если дети уже есть, ничего не делаем.
@MainActor
enum DemoData {
    static func seedIfRequested(_ app: AppContainer, defaults: UserDefaults = .standard) {
        guard defaults.bool(forKey: "demo_data"), app.diary.children.isEmpty else { return }
        app.auth.startAnonymous()
        let diary = app.diary
        let today = LocalDate.today()
        do {
            let childId = try diary.saveChild(id: nil, name: AppLocale.current() == .ru ? "Маша" : "Mia", birthDate: today.minusMonths(7).minusDays(5),
                                              sex: .female, profile: ChildProfile())
            diary.selectChild(childId)

            // Введены сериями по 3 пробы.
            let series = ["zucchini", "broccoli", "cauliflower", "pumpkin", "apple", "pear", "buckwheat-groats", "rice"]
            let amounts: [Amount] = [.halfTsp, .tsp, .twoTsp]
            for (i, id) in series.enumerated() {
                let start = today.minusDays(40 - i * 4)
                for day in 0..<3 {
                    try diary.addEntry(productId: id, date: start.plusDays(day), time: LocalTime(10, 30), meal: .breakfast,
                                       amount: amounts[day], reaction: .good)
                }
            }
            // Были до приложения.
            for id in ["potato", "carrot", "banana", "oat-groats", "turkey"] { try diary.setMark(id, .known) }
            for id in ["apple", "pear", "banana"] { try diary.setLiked(id, true) }

            // Сомнительная реакция — попадёт в «Требуют внимания».
            try diary.addEntry(productId: "peach", date: today.minusDays(6), time: LocalTime(12, 0), meal: .lunch,
                               amount: .halfTsp, reaction: .unsure, symptoms: [.redness])

            // Вводим сейчас: слива (1-я проба вчера, 2-я сегодня), говядина — первая проба сегодня.
            try diary.addEntry(productId: "plum", date: today.minusDays(1), time: LocalTime(10, 0), meal: .breakfast,
                               amount: .halfTsp, reaction: .good)
            try diary.addEntry(productId: "plum", date: today, time: LocalTime(9, 30), meal: .breakfast,
                               amount: .tsp, reaction: .good)
            try diary.addEntry(productId: "beef", date: today, time: LocalTime(13, 0), meal: .lunch, amount: .halfTsp)

            app.onboarding.set(true)
            // Разрешение на уведомления не спрашиваем — на скриншотах не нужен системный диалог.
            app.reminderSettings.permissionAsked = true
        } catch {
            assertionFailure("DemoData: \(error)")
        }
    }
}

/// Только debug: какой экран открыть сразу после запуска — для скриншотов без касаний.
/// `-demo_screen home_progress | diary | catalog | product:<slug> | entry` (entry — новая проба брокколи).
enum DemoScreen {
    static var current: String? { UserDefaults.standard.string(forKey: "demo_screen") }
}
#endif
