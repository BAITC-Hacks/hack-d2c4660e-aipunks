# Firebase: подключение Event Match

Кабинеты, модерация и живой каталог используют **Firebase Authentication + Cloud Firestore**. Для них достаточно Spark: Cloud Functions, Storage и платный AI не нужны. В репозитории реализованы клиент, правила доступа, индексы, локальные тесты и служебные команды; это само по себе не включает провайдеры и не развёртывает правила в Firebase Console.

Рабочая публичная конфигурация проекта `hackalem-84547` находится в `apps/event_match/lib/firebase_options.dart`. Поддерживаются **Web и Android** (`com.example.event_match`). На iOS и desktop стартовый экран объясняет ограничение и позволяет явно открыть демокаталог. Firebase-конфигурация iOS в этот релиз не входит.

## Вход и данные аккаунтов

- Email/пароль, регистрация, письмо подтверждения, восстановление пароля, изменение имени и выход.
- Google Web использует Firebase popup. Google Android использует официальный `google_sign_in` и серверный OAuth client ID.
- Один UID открывает кабинеты заказчика и подрядчика. Права сотрудников читаются отдельно из Firestore; выбор кабинета не меняет роль.
- Личные мероприятия, избранное и отправка профиля требуют подтверждённого email. После подтверждения кнопка «Я подтвердил(а) почту» обновляет пользователя и ID-токен.
- При смене пользователя, выходе, блокировке или изменении служебной роли приватное состояние кабинетов сбрасывается. Дисковый кеш Firestore отключён.
- Живой каталог не подменяется демоданными. Исходные 66 анкет доступны отдельно по `/demo`; помощник по `/assistant` также использует демонстрационный набор.

Схема, правила и безопасные служебные операции описаны в [accounts-backend.md](accounts-backend.md).

## Локальный запуск с эмуляторами

Нужны Flutter, Node.js 22+ и Java 21+. Из корня репозитория:

```sh
cd backend
npm ci
npm run emulators
```

Эта команда поднимает **Auth:9099** и **Firestore:8080** для проекта **`demo-event-match`**. В другом терминале:

```sh
cd apps/event_match
flutter pub get
flutter run -d chrome --dart-define=USE_FIREBASE_EMULATORS=true
```

Или Web Server для проверки через отдельный браузер:

```sh
flutter run -d web-server --web-hostname localhost --web-port 4173 --dart-define=USE_FIREBASE_EMULATORS=true
```

На Android Emulator:

```sh
flutter run -d DEVICE_ID --dart-define=USE_FIREBASE_EMULATORS=true
```

Открывайте Web-приложение по `http://localhost:4173`, а не `http://127.0.0.1:4173`. Установленный `firebase_auth_web` восстанавливает подключение к Auth Emulator после перезагрузки только на `localhost`; приложение проверяет это условие при старте. Адрес самого backend по умолчанию — `127.0.0.1` для Web и `10.0.2.2` для Android. Для физического Android-устройства передайте адрес компьютера через `--dart-define=FIREBASE_EMULATOR_HOST=LAN_IP`. Backend должен слушать соответствующий интерфейс; доступ к эмуляторам предоставляется только в доверенной локальной сети. HTTP разрешён в debug Android manifest, без ослабления release manifest.

В эмуляторном режиме Firebase инициализируется отдельными тестовыми идентификаторами и проектом `demo-event-match`, без конфигурации рабочего проекта. Можно задать `--dart-define=FIREBASE_EMULATOR_PROJECT_ID=demo-custom`; такое же имя передайте Firebase CLI. Допускается только префикс `demo-`. Auth, Firestore и опциональные Functions направляются на эмуляторы.

Письма подтверждения и сброса пароля эмулятор не отправляет: ссылки появляются в терминале Firebase CLI. Откройте ссылку и затем обновите статус в приложении. Для проверки Google Web эмулятор показывает тестовый popup; локальную проверку Android можно пройти через email/пароль.

Первого администратора назначает `backend/scripts/admin.mjs` с `FIRESTORE_EMULATOR_HOST=127.0.0.1:8080`, `FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099` и `--project demo-event-match`; параметры и предварительная проверка описаны в [accounts-backend.md](accounts-backend.md#доверенное-обслуживание).

## Подключение рабочего Firebase

1. В Firebase Console для `hackalem-84547` включите **Authentication → Sign-in method → Email/Password** и **Google**. Для Google укажите support email.
2. В **Authentication → Settings → Authorized domains** добавьте реальный домен приложения и нужный локальный домен разработки, например `localhost`. Для production используйте HTTPS.
3. Создайте Cloud Firestore в Native mode, выберите регион и разверните проверенные Rules/индексы. Публикуйте только `firestore:rules,firestore:indexes`; для кабинетов не требуется развёртывать Functions или включать биллинг.
4. Настройте Android OAuth, как описано ниже, затем проверьте вход и полную цепочку публикации/подбора с реальными тестовыми аккаунтами.

Обычный запуск:

```sh
cd apps/event_match
flutter run -d chrome
```

### Google-вход на Android

Зарегистрируйте SHA-1 и SHA-256 сертификатов debug и release для Firebase Android-приложения `com.example.event_match`. При использовании Google Play App Signing добавьте также сертификат подписи приложения из Play Console. Android OAuth client должен соответствовать package name и нужному SHA-1.

Из Google Cloud Console → APIs & Services → Credentials получите **OAuth 2.0 Client ID типа Web application** для этого же Firebase-проекта. Его передают как `serverClientId`, а не Android client ID:

```sh
flutter run -d DEVICE_ID --dart-define=GOOGLE_SERVER_CLIENT_ID=WEB_OAUTH_CLIENT_ID.apps.googleusercontent.com
flutter build apk --debug --dart-define=GOOGLE_SERVER_CLIENT_ID=WEB_OAUTH_CLIENT_ID.apps.googleusercontent.com
```

Это публичный OAuth client ID, не секрет. Client secret и служебные ключи не должны попадать в приложение. Код инициализирует Firebase из Dart-конфигурации и передаёт `serverClientId` явно, поэтому `google-services.json` не обязателен для текущего способа подключения. Если define отсутствует, Google-кнопка на Android объяснит настройку и предложит вход по email; она не создаёт фиктивную сессию. Сам APK собирается без этого define.

[Официальная документация Firebase о Google-входе во Flutter](https://firebase.google.com/docs/auth/flutter/federated-auth).

## Отдельный AI-помощник

Для кабинетов и подбора по живому каталогу AI-бэкенд не вызывается. Параллельная реализация помощника и опциональных Cloud Functions описана в [assistant.md](assistant.md). Ключ OpenAI хранится только на сервере. Наличие файлов `functions/` не означает, что платный backend развёрнут. Конфигурация `firebase.assistant.json` с отдельными портами предназначена для серверных smoke-тестов помощника; обычный Flutter-режим эмуляторов использует порты 9099/8080/5001 из `firebase.json`.
