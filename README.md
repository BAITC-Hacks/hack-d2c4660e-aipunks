# Event Match · aipunks

Подбор event-подрядчиков в Казахстане: один аккаунт для заказчика и исполнителя, проверяемые профили, актуальные календари и сохранённые подборки до трёх карточек. Flutter Web и Android, Firebase Auth + Firestore на Spark. iOS пока поддерживает только локальное демо.

- [Подключение Firebase, email/Google и Android](docs/firebase.md)
- [Кабинеты, правила доступа, модерация и служебные инструменты](docs/accounts-backend.md)
- [Приёмка кабинетов и границы выполненной проверки](docs/accounts-acceptance.md)
- [Архитектура](docs/architecture.md) · [подбор](docs/pipeline.md) · [разработка](docs/development.md)
- [Дизайн-система](design-system/event-match/MASTER.md)

## Что работает в коде

| Раздел | Возможности |
| --- | --- |
| Каталог `/` | Опубликованные живые карточки, жёсткие фильтры, актуальность календаря, объяснения и избранное |
| Заказчик `/client/events` | Мероприятия, подбор по категориям, постоянные подборки, изменения цены и доступности |
| Подрядчик `/contractor/overview` | Черновик, замороженная версия на проверке, замечания, календарь, снятие публикации |
| Команда `/admin/overview` | Модерация с версиями, блокировки, модераторы, качество каталога и журнал |
| Демо `/demo` | Исходные 66 анонимизированных анкет и окно дат 23.09–31.12.2026 |

Email должен быть подтверждён для личных данных. Кабинет подрядчика добавляется к тому же аккаунту; переключение кабинета не выдаёт служебных прав. Первый администратор назначается доверенным инструментом после регистрации.

Подтверждение календарного месяца действует 30 дней. Отсутствующий или устаревший месяц не означает свободную дату: профиль остаётся в каталоге, но не входит в подбор. Цена «от» и календарь не являются бронированием. Заявок, оплат и загрузки файлов нет; портфолио — HTTPS-ссылки.

## Локальный запуск

Проверяемая среда: Flutter 3.44.1 / Dart 3.12.1, Node.js 22+, Java 21+. Из корня:

```sh
cd backend
npm ci
npm run emulators
```

В другом терминале:

```sh
cd apps/event_match
flutter pub get
flutter run -d chrome --dart-define=USE_FIREBASE_EMULATORS=true
```

Эмуляторы используют `demo-event-match`, Auth 9099 и Firestore 8080. Для Android Emulator замените Chrome на ID устройства; адрес компьютера определяется как `10.0.2.2`. Нестандартный адрес задаётся `FIREBASE_EMULATOR_HOST`. Эмуляторные аккаунты изолированы от облака. Для сохранения состояния между перезапусками эмулятора используйте `--import`/`--export-on-exit` Firebase CLI.

Письма подтверждения эмулятора не отправляются реальным адресатам; ссылки доступны через Auth Emulator. Настройка Google OAuth и Android — в [Firebase](docs/firebase.md). Bootstrap администратора и удаление по запросу — в [документации аккаунтов](docs/accounts-backend.md).

Без флага эмуляторов приложение обращается к `hackalem-84547`. Наличие клиентской конфигурации не означает, что провайдеры Auth, Firestore и правила уже включены в облаке. Облачный deploy этой реализации не выполнен: локальный Firebase CLI не авторизован. При недоступности backend показывается ошибка и повтор; демоданные не подменяют живой каталог.

## Проверки

```sh
cd apps/event_match
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build web
flutter build apk --debug
```

Прямые проверки серверных правил (из корня): `npm --prefix backend test`. CI отдельно проверяет Flutter и Auth/Firestore Emulator. Widget-тесты покрывают 375, 768, 1024, 1440 px, крупный текст и действия кабинетов. Опциональные визуальные снимки: `flutter test test/client_workspace_test.dart --dart-define=WORKSPACE_VISUAL_PREVIEW=true`; файлы в `build/previews/` используют тестовые профили.

Android-сборке нужен установленный Android SDK; инструкция Firebase содержит обязательные настройки Google Sign-In. Проверка Web не заменяет проверку Google OAuth на зарегистрированном устройстве.

## Данные и совместимость

`data/catalog.csv` сохранён без изменений. `assets/data/catalog.jsonl` содержит 66 исходных профилей, включая 13 синтетических. Признаки `synthetic`, `city_imputed`, `price_imputed` сохранены; анкеты не связаны с UID пользователей. Воспроизводимое преобразование:

```sh
python3 scripts/import_catalog.py data/catalog.csv apps/event_match/assets/data/catalog.jsonl
```

Демо: Алматы → Ведущий → свадьба → 14.11.2026 → 1 000 000 ₸; затем 10.10.2026 для изменения занятости. Флорист показывает редкую категорию, бюджет 1 ₸ — объяснённый пустой результат. Живой каталог наполняется отдельно через регистрацию и модерацию.

## Структура

```text
apps/event_match/lib/app/                 тема, маршруты, оболочка
apps/event_match/lib/features/auth/       Firebase gateway, сессия, вход
apps/event_match/lib/features/workspace/  модели, Firestore, кабинеты
apps/event_match/lib/features/matching/   формы, карточки, ядро подбора
firestore.rules                          серверный доступ и аудит
backend/                                 эмуляторы, tests, служебная CLI
```
