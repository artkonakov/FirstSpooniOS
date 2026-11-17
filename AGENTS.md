# AGENTS.md — FirstSpoon iOS

Инструкция для AI-агентов. Читать перед любой правкой.

## Что это

Нативная iOS-версия дневника прикорма «Ложку за маму»: Swift, SwiftUI, GRDB (SQLite), async/await, URLSession.
Аналог Android-версии `~/Documents/Claude/FirstSpoon Android` — её `AGENTS.md` и `ARCHITECTURE.md` остаются источником
правды по функциональности, инвариантам и API. Бизнес-правила перенесены **один в один**; меняется правило — менять обе платформы.
Сервер — `~/Documents/auth-function` (API в `API.md`), только боевой `https://api.littlebite.app/`.
Старый RN-клиент `~/Documents/First-spoon` — только источник данных, код оттуда не копируется.

- Bundle ID: release `app.littlebite`, debug `app.littlebite.dev` (как applicationId в Android; для App Store ещё не согласовано).
- iOS 17+, Xcode 27, Swift 6 toolchain (язык Swift 5 в приложении), GRDB 7 через SPM.
- `FirstSpoon.xcodeproj` написан руками без генераторов: папка `FirstSpoon/` — synchronized folder
  (новые файлы попадают в таргет сами, pbxproj править не нужно).

## Состояние (2026-11-15)

| Функция | Статус | Где |
|---|---|---|
| Доменные правила: FeedingRules, ChildProfile, рекомендации (Gate/Filter/Scorer), ReminderRules, Subscription/Entitlement | ✅ 62 XCTest; сценарии и golden-симуляции — **те же файлы, что в Android**, совпадают байт в байт | `Core/Sources/FirstSpoonCore` |
| Приветствие: «Продолжить» (гость), «У меня уже есть аккаунт», документы в SFSafariViewController | ✅ проверено в симуляторе | `UI/Auth/WelcomeView.swift` |
| Гость: флаг сразу, `POST /auth/anonymous` в фоне (повтор при старте) | ✅ код; в симуляторе — только с `debug_offline` (без сервера) | `AuthRepository.startAnonymous/ensureAnonymous` |
| Вход email + OTP на боевом сервере | ✅ проверено в симуляторе 2026-11-15 (e2e-ios): `/auth/email` и `/auth/email/verify` → 200, сессия, онбординг, почта в настройках | `UI/Auth/AuthViews.swift`, `AuthRepository` |
| Повтор кода (60 с), привязка почты в настройках, «Войти в этот аккаунт» | ✅ код, вживую не проверено | `AuthViewModel`, `LinkEmailFlow` |
| Refresh на 401 (один на всех), 410 ACCOUNT_DELETED → выход и очистка | ✅ код, тестов нет | `Core/Network/ApiClient.swift` |
| Онбординг: имя → пол → дата рождения → аллергены → экзема → аллергия в семье → питание | ✅ проверено в симуляторе | `UI/Onboarding/*` |
| Системный таб-бар (`TabView`) Главная / Дневник / Продукты / Профиль, у каждой вкладки свой `NavigationStack` | ✅ проверено | `UI/Navigation/MainFlow.swift` |
| Главная: имя ребёнка в навбаре + меню выбора ребёнка, рекомендация («Другой»), прогресс X/100, «Требуют внимания», «Вводим сейчас», «Сегодня» с быстрой реакцией | ✅ проверено (рекомендация → проба → «Продолжите серию») | `UI/Home/*`, `UI/Recommendation/*` |
| Дневник по дням, тап — редактирование | ✅ проверено | `UI/Diary/*` |
| Продукты: системный поиск (`.searchable`), фильтры, категории, ♥; свой продукт («+» в навбаре) | ✅ список и поиск-поле проверены; свой продукт — нет | `UI/Catalog/*` |
| Страница продукта: описание, первая порция, статус, отметки, пробы, ♥ в навбаре, предупреждение об аллергене, удаление своего | ✅ проверено открытие | `UI/Product/*` |
| Проба: новая/редактирование, дата-время, приём пищи, количество, реакция, симптомы, заметка, удаление | ✅ сохранение проверено | `UI/Entry/*` |
| Дети: добавить/редактировать (имя, дата, пол, вопросы профиля)/удалить/переключить | ✅ код, вживую не проверено | `UI/Profile/*` |
| Настройки: напоминания, привязка почты / выход, удаление данных/аккаунта; debug: «Пройти онбординг заново» | ✅ код | `UI/Settings/*` |
| Локальные напоминания (UNUserNotificationCenter, тихие часы, запрос разрешения один раз) | ✅ код; запрос разрешения проверен, срабатывание — нет | `Core/Notifications/ReminderScheduler.swift` |
| Аналитика AppMetrica (ключ **общий с Android**): сессии, падения + каталог из 17 событий с теми же именами; без IDFA и геолокации; debug не отправляет | ✅ тест `AnalyticsCatalogTests` (сверка с docs/analytics.md и с Android); в симуляторе: SDK активируется, события `login`, `child_added`, `onboarding_completed` в логе; ⏳ данные в консоли — после релизной сборки | `Core/.../Analytics.swift`, `Core/Analytics/AppMetricaTracker.swift`, [docs/analytics.md](docs/analytics.md) |
| Экспорт дневника в PDF: Профиль → «Экспорт дневника в PDF» (активный ребёнок), A4 на устройстве, лист «Поделиться» / «Сохранить в Файлы»; «Дневник прикорма — <Имя> — yyyy-MM-dd.pdf» | ✅ проверено в симуляторе 2026-11-15 (1 страница; многостраничная разбивка — по коду) | `Data/Export/DiaryPdfExporter.swift`, `ProfileView` |
| Фото ребёнка: PhotosPicker без разрешений, квадрат 512 px JPEG, только локально; редактор ребёнка и шаг с именем в онбординге; аватар на главной, в меню выбора ребёнка, в Профиле | ✅ проверено в симуляторе (редактор, сохранение, показ) | `Data/Local/PhotoStore.swift`, `UI/Components/PhotoPicker.swift` |
| Фото своего продукта: создание и **новое** редактирование своего продукта (карандаш на его странице); вместо буквы в карточках, на странице, в выборе продукта | ✅ проверено (создание с фото, удаление фото → файл стёрт) | `CustomProductView(editId:)`, `ProductThumb` |
| Блокирующий экран «Нет доступа к интернету» при запрете сети для приложения (не авиарежим, не сбой сети), «Открыть настройки», снимается сам | ✅ экран проверен через debug-флаг; реальный запрет в симуляторе не воспроизвести | `Core/Network/NetworkAccessMonitor.swift` |
| Локализация ru / en по языку телефона (ru + СНГ → русский, иначе английский): интерфейс, каталог, даты, время, plurals, PDF; название «Ложку за маму» / «LittleBite» | ✅ тесты `AppLocaleTests`; проверено в симуляторе на en (iPhone, iPad) | `AppLocale` (Core), `UI/Common/Strings.swift`, `Resources/*.xcstrings` |
| Скриншоты App Store ru и en (iPhone 6.9", iPad 13") — без касаний: `-demo_data YES -debug_offline YES`, затем `-demo_screen home_progress\|diary\|catalog\|product:broccoli\|entry` (только debug) | ✅ | `store/screenshots`, `store/screenshots-en`, `App/DemoData.swift` |
| Подписка «Плюс» (StoreKit), синхронизация дневника | ❌ не делаем на первом этапе (логика Entitlement уже в Core) | — |
| Debug-экраны рекомендаций/уведомлений, витрина компонентов, демо-данные, тап по уведомлению → экран | ❌ ещё нет | — |

## Структура

```
Core/                         Swift-пакет FirstSpoonCore: чистый Swift (только Foundation), без UIKit/SwiftUI/GRDB
  Sources/FirstSpoonCore/     LocalDate/LocalTime/LocalDateTime (без часовых поясов, как java.time), Models, FeedingRules,
                              ChildProfile, ReminderRules, Recommendation/*, Billing/Subscription, CatalogPayload
  Tests/FirstSpoonCoreTests/  порт Android unit-тестов; Resources/ = копия Android src/test/resources/recommendation
FirstSpoon/
  App/                        FirstSpoonApp (точка входа, RootView), AppContainer (ручной DI, rootGraph)
  Core/Analytics/             AppMetricaTracker, LogTracker (debug) — каталог событий в Core/Analytics.swift
  Core/Network/               ApiClient (ApiResult/ApiError, refresh, 410, debug_offline), Dto
  Core/Session/               TokenStore (Keychain), SessionManager
  Core/Notifications/         ReminderScheduler
  Data/Local/                 AppDatabase (GRDB, миграции), Records, PhotoStore (фото на устройстве)
  Data/Export/                DiaryPdfExporter (PDF дневника)
  Data/Repository/            Auth, Catalog, Diary, Recommendation, Stores (онбординг, активный ребёнок, напоминания)
  UI/Theme                    цвета, шрифт Onest, внешний вид системных панелей (SystemBars)
  UI/Components               общие компоненты (аналоги ui/components/* в Android)
  UI/Common                   L (строки), UiLocale (даты, plurals), Labels (подписи перечислений и вопросов)
  UI/<feature>/               экраны; UI/Navigation/MainFlow — вкладки и маршруты
  Resources/                  catalog.json, Assets.xcassets (иконка, Products/product_*), Fonts/Onest.ttf,
                              Localizable.xcstrings (ru+en, генерируется), IOS.xcstrings (ru+en, руками),
                              InfoPlist.xcstrings (название: «Ложку за маму» / «LittleBite»)
tools/import_android_assets.py   импорт каталога, картинок, строк, шрифта и иконки из Android
docs/screenshots/             скриншоты из симулятора
```

## Ключевые правила и инварианты

Всё из раздела «Ключевые правила» Android `AGENTS.md` действует и здесь. Отличия и iOS-специфика:

**Доменная логика**
- Только в `Core`. Новое правило → Core + XCTest → то же правило и тест в Android (и наоборот).
- Даты — `LocalDate`/`LocalDateTime` из Core (дни/минуты от эпохи), не `Date`/`Calendar`: арифметика совпадает с Android.
- `scenarios.json` и `simulation_*.golden.txt` — копии из Android. Изменились там → скопировать сюда.
  Принять новое поведение: `UPDATE_GOLDEN=1 swift test` (и в Android тоже).
- Порядок обхода словарей в Swift случайный: где Android опирается на порядок `LinkedHashMap` (серии, «Вводим сейчас»),
  порядок восстановлен явно — по первому появлению продукта в пробах (дата ↓). Не заменять на `Dictionary.values`.

**Состояние и навигация**
- Корневой граф — только `AppContainer.rootGraph` (auth → onboarding → main). Экраны после входа/выхода/онбординга никуда не переходят.
- Репозитории — `@MainActor @Observable`, читают GRDB синхронно и перечитывают состояние после каждой записи (`reload()`).
  Экраны берут данные из репозиториев через `@Environment(AppContainer.self)`.
- **Навигация нативная** (решение пользователя): системный `TabView` и системный навбар. Заголовок — `.navigationTitle`
  (большой на корне вкладки, `.inline` на странице продукта и в онбординге), «назад» — системная, действия — `.toolbar`,
  поиск — `.searchable`, выбор ребёнка — `Menu` в навбаре. Самодельные верхние панели и таб-бар не возвращать.
  Шрифт Onest в заголовках навбара задаётся через `SystemBars.configure()` (UINavigationBarAppearance), фон — системный.
- Экраны поверх вкладки — `Route` в `NavigationStack` этой вкладки (`TabStack`), переходы через `Navigator` из environment.
  Таб-бар на вложенных экранах остаётся (стандарт iOS).
- Главная кнопка экрана внизу («Новая запись», «Сохранить») — `.bottomAction { AppButton(...) }`, не в VStack под ScrollView.
- **SwiftUI-ловушка:** не создавать модель в `.onAppear` у `Group { if let model {…} }` — у пустого контейнера `onAppear`
  не вызывается, получается белый экран (был такой баг). Создавать в `@State` дочернего view или в непустом контейнере.

**Хранение**
- БД `first_spoon.sqlite` (Application Support, исключена из бэкапа). Схема пользовательских таблиц совпадает с Room v4
  (UUID, `created_at/updated_at/deleted_at`, мягкое удаление, `entries.product_id` без FK). Изменение схемы — новая миграция в
  `AppDatabase.migrator`, старые не трогать.
- Фото ребёнка и своего продукта — **только на устройстве**: `Application Support/photos/<uuid>.jpg` (не в бэкапе),
  в БД — имя файла (`children.photo`, `custom_products.photo`, миграция `v2_photos`); не синхронизируются.
  Файл стирается при замене/удалении фото, удалении ребёнка или продукта, выходе и удалении данных (`PhotoStore.deleteAll`).
  На экранах редактирования — `PhotoDraft`: выбранные, но не сохранённые снимки стираются при уходе с экрана.
  `saveChild(photo:)`: `.none` — не трогать фото (иначе повторный онбординг стёр бы его).
- Каталог в БД **не** хранится (отличие от Android): read-only, читается из `catalog.json` (`CatalogSource`). Свои продукты — в `custom_products`.
- Токены и почта — Keychain, `AfterFirstUnlockThisDeviceOnly`. Keychain переживает удаление приложения → на первом запуске
  новой установки (`installed` в UserDefaults) сессия стирается.
- Настройки устройства (онбординг, активный ребёнок, гость, владелец данных, напоминания) — UserDefaults, ключи как в Android prefs.

**Сеть**
- Блокирующий экран — только при запрете сети для приложения: `NWPath.status == .unsatisfied` и
  `unsatisfiedReason` = `.cellularDenied` / `.wifiDenied`. Авиарежим, нет сети, ошибки сервера — приложение работает офлайн,
  экран не показываем. Debug: `defaults write app.littlebite.dev debug_network_blocked -bool YES` (снять: `defaults delete`).

**PDF дневника** — `DiaryPdfExporter`: A4, Onest, всегда светлые цвета; вёрстка в два прохода (раскладка → «стр. N из M»).
Содержимое и имя файла — как в Android (общая спецификация 2026-11-15); меняется одно — менять обе платформы.

**Аналитика** — подробно в [docs/analytics.md](docs/analytics.md)
- Код шлёт события только через `Analytics.track(.x)`; SDK AppMetrica — только в `AppMetricaTracker`.
- Ключ, имена и параметры событий — **общие с Android**. Новое событие: case в `AnalyticsEvent` + `allNames` → вызов там,
  где действие точно произошло → строка в docs/analytics.md → то же в Android. `AnalyticsCatalogTests` сверяет всё это.
- Никаких личных данных в параметрах. Состав данных меняется → обновить «Конфиденциальность приложения» в App Store Connect до выпуска.

**Тексты и язык (ru / en)** — решение пользователя 2026-11-16, то же правило в Android
- Язык — по **первому** языку телефона, переключателя в приложении нет: ru и языки СНГ (be, uk, kk, ky, uz, tg, tk, hy, az, ka) →
  русский, всё остальное → английский. Правило — `AppLocale.resolve` в Core (тесты `AppLocaleTests`). Системный выбор iOS так не
  умеет, поэтому `L` читает строки из `<язык>.lproj` явно. Название на экране «Домой» (`InfoPlist.xcstrings`) выбирает система —
  там правило не действует (казахский телефон без русского в списке покажет «LittleBite»).
- Все тексты — по ключам из String Catalog, хардкода во View нет:
  - `Localizable.xcstrings` — генерирует `tools/import_android_assets.py` из Android `values/strings.xml` (ru) и
    `values-en/strings.xml` (en); ключи те же, что в Android, руками не править. Если английского ключа в Android нет —
    берётся из `tools/strings.en.json`, нет и там — скрипт падает со списком ключей;
  - `IOS.xcstrings` — только строки, которых нет в Android (сейчас `catalog_custom_category`, `custom_edit`), правится руками.
- В коде — `L.s("key", args…)`, plurals — `L.plural("key", n, args…)` (ключи `<name>#one|few|many` в ru, `#one|other` в en;
  категория — по выбранному языку), даты и время — `UiLocale` (`dayMonth`, `dayMonthYear`, `time`: «13:00» / «1:00 PM»),
  форматтеры с явной локалью, не системной. Каталог (названия, описания, первая порция, категории, аллергены) — из
  `catalog.json` на выбранном языке (`CatalogPayload.toCatalog`). PDF — тоже на выбранном языке (ключи `export_*` как в Android).

**UI**
- Внутри экранов — «крупно и мягко», как в Android: Onest (вариативный, вес через ось `wght` — `AppFont`), белые карточки 28
  на тёплом фоне, кнопки-пилюли 64. **Карточки всегда белые**, цвет статуса — только у бейджа/текста. Цвета — только `AppColors`.
- Экраны собираются из `UI/Components` (`AppCard`, `SectionTitle`, `AppButton`, `AppTextField`, `ChoiceTile`, `ChoiceRow`,
  `SegmentedControl`, `AppChip`, `ProductCard`, `StatusBadge`, `ActionRow`, `EmptyState`, `FlowLayout`…).

## Команды

```bash
cd Core && swift test                                   # 62 теста домена (на macOS, ~1 с)
cd Core && UPDATE_GOLDEN=1 swift test                   # принять новые траектории симуляции
xcodebuild -project FirstSpoon.xcodeproj -scheme FirstSpoon -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=27.2' -derivedDataPath build/DerivedData build
python3 tools/import_android_assets.py --icon ~/Documents/First-spoon/assets/icon.png   # обновить каталог/картинки/строки из Android
xcrun simctl spawn booted defaults write app.littlebite.dev debug_offline -bool YES     # debug: сеть выключена, сервер не трогаем (снять: defaults delete …)
xcrun simctl spawn booted log stream --predicate 'category == "Analytics"'              # события аналитики в debug
xcrun simctl install booted build/DerivedData/Build/Products/Debug-iphonesimulator/FirstSpoon.app && xcrun simctl launch booted app.littlebite.dev
tools/upload_testflight.sh 2                              # сборка №2 → TestFlight (номер растёт с каждой загрузкой)
node tools/asc_api.mjs builds                           # статус обработки сборок
```

## Выкладка (App Store Connect)

- Приложение «Ложку за маму», Bundle ID `app.littlebite`, Apple ID приложения 6835090508, Team ID `93DY8Q8W67` (в проекте,
  подпись автоматическая). Debug — `app.littlebite.dev`, в App Store Connect не регистрируется.
- `tools/upload_testflight.sh [номер]` — Release-архив → подпись → загрузка в App Store Connect. Номер сборки
  (CFBundleVersion) растёт с каждой загрузкой. Подпись для App Store делает Apple Account, в который вошли в Xcode
  (Settings → Accounts): ключу с ролью App Manager облачная подпись недоступна.
- `node tools/asc_api.mjs apps|builds|whats-new|groups|add-to-group|versions|listing` — App Store Connect API (описание —
  в начале скрипта). Ключ — `~/.littlebite-keys/AuthKey_A2VCF6W9QB.p8` (роль App Manager; создаёт пользователь, вне git,
  не читать и не печатать). Key ID и Issuer ID — в скрипте, не секреты.
- `node tools/asc_api.mjs listing-set` / `screenshots` — тексты (`store/appstore.ru.json`) и скриншоты (`store/screenshots/{iphone,ipad}`,
  снимаются в debug с `-demo_data YES -debug_offline YES -demo_screen …`); `submit <сборка> --yes` — на проверку App Store.
  1.0 (2) отправлена на проверку 2026-11-16; на 2026-11-17 API показывает её как `REJECTED`.
- Английская страница (en-US): тексты `store/appstore.en.json` (из Android `store/listing.en.json`; имя «LittleBite», запасное —
  `nameFallback`; ссылки на `littlebite.app/en/…`), скриншоты `store/screenshots-en`:
  `node tools/asc_api.mjs listing-set store/appstore.en.json [--version X]` и
  `node tools/asc_api.mjs screenshots store/screenshots-en --locale en-US [--version X]`. Локализация создаётся сама.
  Новая версия — `version-create <номер>` (пока предыдущая не одобрена/отклонена-открыта, App Store Connect её не даст).
- Загрузка в TestFlight и выдача внутренним тестировщикам — по просьбе пользователя. Отправка версии на проверку
  в App Store и публикация — только с его подтверждения.
- Анкета App Privacy — по факту сборки: AppMetrica (взаимодействие с приложением, сбои, диагностика, идентификатор
  устройства), без рекламного ID и геолокации; почта — для входа.

## Осторожно

- API только боевой. Агент **не создаёт аккаунты**: «Продолжить» создаёт анонимный аккаунт на сервере, поэтому гостевой поток
  в симуляторе проверять только с `debug_offline`. Вход по почте — пользователь или e2e-аккаунт `e2e-ios@littlebite.app`
  (код в `~/Documents/First-spoon/.maestro/.env.local`, не печатать).
- Ключи, пароли, сертификаты — не читать и не выводить.
- Git: свой репозиторий, ветка `main`, веток под задачи не создаём. Коммитить и пушить — только по просьбе пользователя.
- Вход e2e в симуляторе: код не вводить руками и не печатать — положить в настройки приложения из `.env.local`
  (`defaults write app.littlebite.dev debug_otp -string "$(…)"`), экран кода (debug) подставит его один раз и сотрёт.
- Симулятор, загруженный (`simctl boot`) или приложение, запущенное из песочницы агента, наследует её сетевые ограничения →
  «Нет соединения». Загружать/запускать вне песочницы (или инструментом симулятора).
- `api.littlebite.app` (Yandex API Gateway) из сети этого Mac 2026-11-15 отвечал нестабильно (~1 из 5 TCP-соединений) —
  при «Нет соединения» сначала проверить `curl https://api.littlebite.app/warmup` вне песочницы.
- Инструмент симулятора не печатает кириллицу (нет вставки) — вводить латиницей; его скриншоты иногда отстают на одно действие.
- После изменения функциональности обновить таблицу «Состояние».
