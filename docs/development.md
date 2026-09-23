# Разработка Event Match

Текущий этап расширяет исходный подбор рабочими аккаунтами. Кабинеты, сохранение, заявки, переписка и поддержка реализованы. Бронирование и оплата не входят в этот этап.

## Контракты

- `MatchRequest`: city/date/format/category/budget и необязательные hours/language/preferences. JSON совместим; `fromJson` восстанавливает сохранённый запрос, `validate(datePolicy:)` различает demo/live.
- `Contractor` — публичная модель; добавлены `isLive`, деловой контакт и портфолио. Поля исходного набора сохранены.
- `RecommendationService.recommend()` сохраняет асинхронный контракт. `LocalRecommendationService` работает с JSONL, `LiveRecommendationService` — с публикациями и календарями Firestore. Свободные пожелания в этих сервисах не ранжируются, что отмечено в форме.
- `WorkspaceRepository` отделяет UI от Firestore: аккаунты, версии, календарь, модерация, события, подборки, избранное. Production-операции проверяются совместно с Rules; fake-репозитории используются только в widget-тестах.
- `AuthGateway` и `SessionController` управляют входом, подтверждением почты, возвратом к действию и очисткой сессии. Параметры виджета не являются доверенными полномочиями.

- `CommunicationRepository` отделяет заявки и поддержку от UI. `FirestoreCommunicationRepository` использует транзакции, стабильные идентификаторы повторов и приватные потоки без выдачи кеша до подтверждения доступа сервером. [Коммуникация и изолированный Chrome-тест](communications.md).

## Изменение и проверки

При изменении Firestore-схемы обновляйте сериализацию Dart, Rules, Node-тесты прямого доступа и CLI обслуживания. Особое внимание — атомарной публикации/аудиту, замороженной версии, неподтверждённой почте и отзыву роли. Публичные поля выбираются явно: Rules не могут сделать часть приватного документа публичной.

Из `apps/event_match`: `dart format --output=none --set-exit-if-changed lib test`, `flutter analyze`, `flutter test`, `flutter build web`, `flutter build apk --debug`. Из корня: `npm --prefix backend test`. Анализатор исключает сгенерированные `build/**`, включая копии iOS-плагинов; собственный код и тесты проверяются целиком.

Local/cloud настройка — в [firebase.md](firebase.md), серверные сценарии — в [accounts-backend.md](accounts-backend.md). Отдельный AI-контракт — [assistant-contract.md](assistant-contract.md); он не меняет права и данные живых кабинетов.
