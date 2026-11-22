# Аналитика (AppMetrica)

Продуктовая аналитика iOS-приложения. Каталог событий — `Core/Sources/FirstSpoonCore/Analytics.swift`,
трекеры — `FirstSpoon/Core/Analytics/`. Тест `AnalyticsCatalogTests` (`cd Core && swift test`) проверяет, что этот файл
и каталог в коде совпадают, и что имена те же, что в Android (`core/analytics/AnalyticsEvent.kt`).

**Ключ AppMetrica общий с Android** (одно приложение в консоли) — поэтому имена и параметры событий совпадают
с Android один в один, отчёты и воронки общие, платформа видна в разрезе «ОС».

## Как устроено

```
место в коде ──Analytics.track(.x)──▶ Analytics ──▶ AppMetricaTracker  (AppMetrica)
                                               └─▶ LogTracker        (только debug, os_log «Analytics»)
```

- **`AnalyticsEvent`** — каталог: `enum`, по case на событие, параметры типизированы (нельзя случайно отправить личные данные).
- **`Analytics`** — точка входа: `track(event)` раздаёт событие всем трекерам. Трекеры подключаются один раз в `AppDelegate`
  (`Analytics.install`). Без install события никуда не уходят (тесты, превью).
- **AppMetrica** (`AppMetricaTracker`, SPM `appmetrica-sdk-ios` 7.x, продукты `AppMetricaCore` + `AppMetricaCrashes`):
  сессии, падения + события ниже. Ключ — `AppMetricaTracker.apiKey` (тот же, что `APPMETRICA_API_KEY` в Android; не секрет).
  Окружение `store` = `appstore`.

### Что НЕ собираем

- Рекламный идентификатор (IDFA): модуль `AppMetricaAdSupport` не подключён, `advertisingIdentifierTrackingEnabled = false`,
  запроса App Tracking Transparency нет. Как и в Android: рекламы нет.
- Геолокацию: `locationTracking = false`.
- Автоматический учёт покупок StoreKit: `revenueAutoTrackingEnabled = false` (покупок пока нет).
- Личные данные и содержимое дневника: имена, почту, продукты, реакции, аллергены, заметки.
- Данные из debug-сборок: `dataSendingEnabled = false`; события видны в Console / `log stream --predicate 'category == "Analytics"'`.

Отличие от Android: SwiftUI-экраны AppMetrica автоматически не видит (в Android — Activity auto-tracking), ANR нет.

### Добавить событие

1. Case в `AnalyticsEvent` + имя в `allNames` (и **то же событие в Android**).
2. `Analytics.track(.x)` там, где действие **точно произошло** — в репозитории или модели, не во View.
3. Строка в таблице ниже (и в Android `docs/analytics.md`).
4. Новый тип данных — обновить «Конфиденциальность приложения» в App Store Connect (и анкеты Play/RuStore) **до** выпуска.

## События

| Событие | Когда | Параметры | Где в коде |
|---|---|---|---|
| `welcome_shown` | Показан экран приветствия | — | `WelcomeView` |
| `guest_started` | «Продолжить» без регистрации на экране приветствия | — | `AuthRepository.startAnonymous` |
| `login` | Успешный вход по почте и коду | `from_guest`: вход из гостевого аккаунта (дневник и подписки переходят) | `AuthRepository.verifyCode` |
| `email_linked` | Почта привязана к гостевому аккаунту | — | `AuthRepository.verifyLink` |
| `logout` | Выход из аккаунта | — | `AuthRepository.logout` |
| `account_deleted` | Аккаунт удалён (или «Удалить все данные» у гостя) | — | `AuthRepository.deleteAccount` |
| `onboarding_step` | Показан шаг онбординга — воронка по шагам (развилка: вопросы готовности только если малыш ещё не ест) | `step`: `name` / `sex` / `birth` / `known_foods` / `q_known_allergens` / `q_eczema` / `q_family_allergy` / `q_milk_feeding` / `q_head_control` / `q_sits_with_support` / `q_food_interest` / `result` | `OnboardingStepView` |
| `onboarding_back_to_welcome` | «Назад» с первого шага онбординга — снова экран приветствия | — | `AuthRepository.returnToWelcome` |
| `onboarding_completed` | Онбординг ребёнка пройден | `readiness`: `started` / `too_early` / `not_yet` / `check` / `ready`; `known_foods`: сколько основных продуктов отметили (0–19) | `OnboardingViewModel.finish` |
| `ready_marked` | На главной «Малыш уже держит голову и сидит» (карточка «Пока готовимся») | — | `HomeViewModel.markReady` |
| `child_added` | Добавлен ребёнок (в т.ч. в онбординге) | — | `DiaryRepository.saveChild` |
| `entry_added` | Записана новая проба (экран пробы или быстрая кнопка на главной) | — | `DiaryRepository.addEntry` |
| `product_marked` | Поставлена отметка продукта | `mark`: `known` / `excluded` / `allergy` | `DiaryRepository.setMark` |
| `custom_product_added` | Добавлен свой продукт | — | `CatalogRepository.addCustomProduct` |
| `recommendation_record` | «Записать пробу» внизу главной, когда форма открывается с продуктом из рекомендации (новый или продолжить серию) | — | `HomeView` (`bottomAction`) |
| `recommendation_other` | «Другой» на карточке рекомендации | — | `RecommendationRepository.skip` |
| `stats_opened` | Открыт экран статистики — тап по карточке «N из 100» на главной | — | `StatsView` |
| `diary_exported` | Дневник выгружен в PDF (файл готов, открыт лист «Поделиться») | `photos`: `none` / `reactions` / `all` — какие фото проб в отчёте (`none` и когда фото нет) | `ProfileView.exportDiary` |
| `entry_photo_added` | К пробе прикреплено фото (из галереи) — по событию на фото, при сохранении пробы (брошенный черновик не считается) | — | `EntryViewModel.save` |
| `child_photo_set` | Ребёнку поставлено новое фото (редактор или онбординг) | — | `DiaryRepository.saveChild` |
| `custom_product_photo_set` | Своему продукту поставлено новое фото | — | `CatalogRepository.add/updateCustomProduct` |
| `network_blocked_shown` | Показан блокирующий экран «Нет доступа к интернету» (запрет сети для приложения) | — | `NetworkAccessMonitor` |
| `paywall_opened` | Открыт экран «Плюс» (на iOS пока нет) | — | — |
| `purchase_started` | Нажата кнопка оформления подписки (на iOS пока нет) | `product`: ID тарифа | — |
| `purchase_completed` | Магазин подтвердил покупку (на iOS пока нет) | `product`: ID тарифа | — |
| `purchase_failed` | Оплата не прошла, отмена не считается (на iOS пока нет) | `product`: ID тарифа | — |
| `restore_tapped` | «Восстановить покупки» / «Проверить снова» (на iOS пока нет) | — | — |

Автоматически: сессии, падения, версия и сборка приложения, окружение `store` = `appstore`.
