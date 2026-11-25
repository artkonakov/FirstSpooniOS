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
- Личные данные и содержимое дневника: имена, почту, личные ID, названия своих продуктов, реакции, аллергены, заметки.
- Данные из debug-сборок: `dataSendingEnabled = false`; события видны в Console / `log stream --predicate 'category == "Analytics"'`.

Отличие от Android: SwiftUI-экраны AppMetrica автоматически не видит (в Android — Activity auto-tracking), ANR нет.

### Поля прикорма и онбординга

- `product_type` принимает `catalog`, `custom` или `unknown`. `product_id` — только проверенный публичный ключ из каталога. Имена, идентификаторы и свойства своих продуктов запрещены.
- Для отметок «Аллергия» и «Исключить», снятия отметки и записи реакции ID продукта не передаётся. Значение реакции, симптомы и данные пробы не передаются.
- `onboarding_option_changed` принимает только `sex` (male/female), `milk_feeding` (breast/formula/mixed) и `known_foods` (публичный ID предложенного продукта). `selected` означает выбор или снятие. Остальные шаги учитываются в воронке показов без значения ответа.
- Действия фоновой синхронизации не пересылают события действий с продуктами. Аналитика пользовательской операции идёт после локального сохранения либо подтверждения сервером.

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
| `entry_added` | Записана новая проба (экран пробы или быстрая кнопка на главной) | `product_type`, `product_id` публичного каталога | `DiaryRepository.addEntry` |
| `product_marked` | Поставлена отметка продукта | `mark`: `known` / `excluded` / `allergy`; `product_type`; `product_id` только для `known` | `DiaryRepository.setMark` |
| `custom_product_added` | Добавлен свой продукт | `product_type: custom` | `CatalogRepository.addCustomProduct` |
| `recommendation_record` | «Записать пробу» внизу главной, когда форма открывается с продуктом из рекомендации (новый или продолжить серию) | — | `HomeView` (`bottomAction`) |
| `recommendation_other` | «Другой» на карточке рекомендации | — | `RecommendationRepository.skip` |
| `stats_opened` | Открыт экран статистики — тап по карточке «N из 100» на главной | — | `StatsView` |
| `diary_exported` | Дневник выгружен в PDF (файл готов, открыт лист «Поделиться») | `photos`: `none` / `reactions` / `all` — какие фото проб в отчёте (`none` и когда фото нет) | `ProfileView.exportDiary` |
| `entry_photo_added` | К пробе прикреплено фото (из галереи) — по событию на фото, при сохранении пробы (брошенный черновик не считается) | — | `EntryViewModel.save` |
| `child_photo_set` | Ребёнку поставлено новое фото (редактор или онбординг) | — | `DiaryRepository.saveChild` |
| `custom_product_photo_set` | Своему продукту поставлено новое фото | `product_type: custom` | `CatalogRepository.add/updateCustomProduct` |
| `network_blocked_shown` | Показан блокирующий экран «Нет доступа к интернету» (запрет сети для приложения) | — | `NetworkAccessMonitor` |
| `paywall_opened` | Открыт экран «Плюс» (на iOS пока нет) | — | — |
| `purchase_started` | Нажата кнопка оформления подписки (на iOS пока нет) | `product`: ID тарифа | — |
| `purchase_completed` | Магазин подтвердил покупку (на iOS пока нет) | `product`: ID тарифа | — |
| `purchase_failed` | Оплата не прошла, отмена не считается (на iOS пока нет) | `product`: ID тарифа | — |
| `restore_tapped` | «Восстановить покупки» / «Проверить снова» (на iOS пока нет) | — | — |

| `diary_sync_enabled` | Подключение дневника подтверждено и сохранено на устройстве | — | `DiarySync` |
| `diary_sync_disabled` | Сервер подтвердил удаление облачной копии | — | `DiarySync` |
| `device_sessions_opened` | Открыт список устройств из профиля | — | `Profile` |
| `device_session_revoked` | Сервер подтвердил отзыв активной сессии | — | `Devices` |
| `theme_changed` | Сохранён новый режим оформления | `mode`: `system` / `light` / `dark` | `Settings` |
| `legal_document_opened` | Открыт документ из настроек | `document`: `privacy` / `terms` | `Settings` |
| `assistant_source_opened` | Открыт источник из ИИ-чата | — | `AssistantChat` |
| `assistant_retried` | Принята повторная отправка вопроса | — | `AssistantChat` |
| `assistant_feedback_tapped` | Применено нажатие оценки ответа, включая снятие оценки | `vote`: `like` / `dislike` | `AssistantViewModel` |

| `assistant_opened` | Открыт чат из приложения | `source`: `home` / `product` / `settings` | `AssistantChat` |
| `assistant_history_opened` | Открыта история бесед | — | `AssistantChat` |
| `assistant_chat_created` | Сохранена беседа с первым вопросом | — | `AssistantChat` |
| `assistant_chat_selected` | Пользователь переключился на другую беседу из истории | — | `AssistantChat` |
| `assistant_chat_deleted` | Беседа удалена из истории | — | `AssistantChat` |
| `assistant_message_sent` | Первичная отправка вопроса принята приложением | — | `AssistantChat` |
| `assistant_reply_received` | Ответ получен и сохранён | — | `AssistantChat` |
| `assistant_request_failed` | Запрос в ИИ-чат завершился ошибкой | `reason`: `network` / `quota` / `auth` / `server` / `other` | `AssistantChat` |
| `assistant_request_stopped` | Пользователь остановил выполняющийся запрос | — | `AssistantChat` |
| `assistant_answer_copied` | Ответ скопирован | — | `AssistantChat` |
| `assistant_share_opened` | Открыто системное меню «Поделиться» | — | `AssistantChat` |
| `device_sessions_failed` | Не удалось загрузить список устройств или завершить сеанс | `operation`: `list` / `revoke` | `Devices` |

| `entry_updated` | Проба сохранена после редактирования | `product_type`, `product_id` публичного каталога | `DiaryRepository` |
| `entry_deleted` | Проба удалена | `product_type`, `product_id` публичного каталога | `DiaryRepository` |
| `entry_reaction_changed` | Изменена реакция в сохранённой пробе | `product_type`; значение реакции и ID отсутствуют | `DiaryRepository` |
| `product_opened` | Открыта карточка продукта | `product_type`, `product_id` публичного каталога | `ProductView / ProductScreen` |
| `product_favorite_changed` | Изменено избранное продукта | `product_type`, `product_id` публичного каталога, `liked` | `DiaryRepository` |
| `product_mark_removed` | Снята ручная отметка продукта | `product_type`; ID отсутствует | `DiaryRepository` |
| `custom_product_deleted` | Свой продукт удалён | `product_type: custom` | `CatalogRepository` |
| `onboarding_option_changed` | Выбран или снят допустимый вариант анкеты | `step`, `option`, `selected` для пола, типа питания и отмеченных продуктов каталога | `OnboardingViewModel` |

Автоматически: сессии, падения, версия и сборка приложения, окружение `store` = `appstore`.
