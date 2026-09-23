# Firebase: подключение Event Match

## Состояние на 23 сентября 2026

- Подтверждён доступ к проекту `hackalem-84547`.
- Зарегистрированы приложения `Event Match Web` и `Event Match Android`.
- Android package: `com.example.event_match`.
- Реальные публичные настройки приложений сохранены в `apps/event_match/lib/firebase_options.dart`.
- `main.dart` инициализирует Firebase SDK для Web и Android. На остальных платформах пока остаётся локальный режим без Firebase.
- Подбор и каталог пока локальные: Cloud Functions и GPT ещё не подключены, Firestore не настроен. Firestore API при проверке отключён.
- Проверка Cloud Billing вернула `billingEnabled: false`. Платный тариф агент не включал.

## Что нужно для серверного GPT

Владелец проекта должен включить тариф **Blaze** в Firebase Console и привязать биллинг. Это допускает платное использование ресурсов; уведомление о бюджете не является жёстким ограничением расходов.

После этого можно продолжить реализацию:

1. Создать Firebase callable Function для подбора и настроить серверный источник каталога.
2. Хранить `OPENAI_API_KEY` в Secret Manager, не в Dart, assets или `--dart-define`.
3. Проверять параметры и жёсткие ограничения на сервере до вызова GPT; не позволять модели менять цену или доступность.
4. Добавить аутентификацию, ограничение запросов и расходов, обработку таймаута и честный fallback без AI.
5. Подключить реализацию `RecommendationService` через Firebase Functions и проверить полный запрос из Chrome и Android.

Пока этих шагов нет, запуск приложения не вызывает OpenAI и не тратит его API-бюджет. Наличие Firebase SDK само по себе не означает, что GPT-бэкенд развёрнут.

## Запуск из корня репозитория

```powershell
cd apps/event_match
flutter pub get
flutter run -d chrome
```

Для Android: `flutter devices`, затем `flutter run -d <device-id>`. iOS-конфигурация Firebase ещё не создана; сборка iOS требует macOS.

## Документация

- [Firebase: подготовка и развёртывание Functions, включая требование Blaze](https://firebase.google.com/docs/functions/get-started)
- [Firebase: серверные секреты](https://firebase.google.com/docs/functions/config-env)
- [OpenAI: структурированные ответы для будущего серверного контракта](https://developers.openai.com/api/docs/guides/structured-outputs)
