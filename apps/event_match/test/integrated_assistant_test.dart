import 'dart:async';

import 'package:event_match/features/assistant/data/basic_assistant_service.dart';
import 'package:event_match/features/assistant/domain/assistant_models.dart';
import 'package:event_match/features/assistant/domain/assistant_service.dart';
import 'package:event_match/features/assistant/presentation/assistant_controller.dart';
import 'package:event_match/features/assistant/presentation/assistant_screen.dart';
import 'package:event_match/features/matching/domain/models.dart';
import 'package:event_match/features/workspace/data/workspace_catalog_repository.dart';
import 'package:event_match/features/workspace/domain/workspace_models.dart';
import 'package:event_match/features/workspace/presentation/catalog_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'client_workspace_test.dart'
    show ClientRepository, host, pump, seedEventAndSelection;

class _TextService implements AssistantService {
  @override
  bool get supportsFreeText => true;

  @override
  Future<AssistantTurn> send({
    required AssistantBrief brief,
    String? message,
    AssistantAction? action,
    List<AssistantMessage> history = const [],
  }) async => AssistantTurn(brief: brief, message: 'Уточним условия');
}

class _DelayedTextService extends _TextService {
  final pending = <Completer<AssistantTurn>>[];

  @override
  Future<AssistantTurn> send({
    required AssistantBrief brief,
    String? message,
    AssistantAction? action,
    List<AssistantMessage> history = const [],
  }) {
    final response = Completer<AssistantTurn>();
    pending.add(response);
    return response.future;
  }
}

class _DelayedCalendarRepository extends ClientRepository {
  bool delayNextCalendar = false;
  Completer<void>? delayedCalendar;
  int selectionWrites = 0;

  @override
  Future<CalendarMonth?> getCalendar(String uid, DateTime date) async {
    if (delayNextCalendar) {
      delayNextCalendar = false;
      delayedCalendar = Completer<void>();
      await delayedCalendar!.future;
    }
    return super.getCalendar(uid, date);
  }

  @override
  Future<String> saveSelection(String uid, SavedSelection value) async {
    selectionWrites++;
    return super.saveSelection(uid, value);
  }
}

Future<AssistantController> _assistant(ClientRepository repository) async {
  final catalog = WorkspaceCatalogRepository(repository);
  final basic = BasicAssistantService(
    catalog,
    datePolicy: MatchDatePolicy.live(),
    calendarResolver: repository.getCalendar,
  );
  final controller = AssistantController(
    service: basic,
    basicService: basic,
    repository: catalog,
  );
  await controller.loadCatalog();
  addTearDown(controller.dispose);
  return controller;
}

CatalogPage _page(
  ClientRepository repository,
  AssistantController controller, {
  String? eventId = 'event-1',
  String? selectionId,
  ValueChanged<Contractor>? onCreateInquiry,
}) => CatalogPage(
  repository: repository,
  assistant: controller,
  uid: 'client',
  eventId: eventId,
  selectionId: selectionId,
  onRequireSignIn: () {},
  onCreateInquiry: onCreateInquiry,
);

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _chooseHost(WidgetTester tester) => _tap(
  tester,
  find.byKey(const Key('assistant-action-manual:category:Ведущий')),
);

void main() {
  testWidgets(
    'applying an old budget picker cannot edit a replacement context',
    (tester) async {
      final repository = ClientRepository();
      seedEventAndSelection(repository);
      final controller = await _assistant(repository);
      await pump(
        tester,
        _page(repository, controller, selectionId: 'selection-1'),
      );
      await _tap(tester, find.byKey(const Key('inline-budget_kzt')));
      expect(find.text('Бюджет подрядчика'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Сумма, ₸'),
        '220000',
      );
      final next = controller.brief
          .withField('category', 'Фотограф')
          .withField('budget_kzt', 450000);
      controller.replaceContext(next, 'another-event-context');
      await tester.pump();
      await _tap(tester, find.text('Применить'));
      expect(controller.brief, same(next));
      expect(controller.brief.budgetKzt, 450000);
      expect(controller.brief.category, 'Фотограф');
      expect(controller.messages, isEmpty);
      expect(controller.turn, isNull);
    },
  );

  testWidgets(
    'delayed save cannot write after the event and selection route changes',
    (tester) async {
      final repository = _DelayedCalendarRepository();
      seedEventAndSelection(repository);
      final firstEvent = repository.events.single;
      final firstSelection = repository.selections.single;
      repository.events.add(
        ClientEvent(
          id: 'event-2',
          name: 'Второе мероприятие',
          city: firstEvent.city,
          date: firstEvent.date,
          format: firstEvent.format,
        ),
      );
      final secondSelection = SavedSelection(
        id: 'selection-2',
        eventId: 'event-2',
        name: 'Ведущий для второго мероприятия',
        request: MatchRequest.fromJson({
          ...firstSelection.request.toJson(),
          'budget_kzt': 150000,
        }),
        entries: firstSelection.entries,
      );
      repository.selections.add(secondSelection);
      final controller = await _assistant(repository);
      await pump(
        tester,
        _page(repository, controller, selectionId: 'selection-1'),
      );
      final firstContext = controller.contextKey;
      repository.delayNextCalendar = true;
      final save = find.text('Сохранить в «Наша свадьба»');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pump();
      expect(repository.delayedCalendar, isNotNull);
      expect(repository.selectionWrites, 0);

      // Change the existing CatalogPage route while its first save is awaiting
      // a fresh calendar. Do not settle the old action's pending spinner yet.
      await tester.pumpWidget(
        host(
          _page(
            repository,
            controller,
            eventId: 'event-2',
            selectionId: 'selection-2',
          ),
        ),
      );
      await tester.pump();
      expect(controller.contextKey, isNot(firstContext));
      expect(controller.brief.budgetKzt, 150000);
      repository.delayedCalendar!.complete();
      await tester.pumpAndSettle();

      expect(repository.selectionWrites, 0);
      expect(repository.selections, [firstSelection, secondSelection]);
      expect(controller.brief.budgetKzt, 150000);
      expect(find.text('Подборка сохранена'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'late send from previous account cannot restore its private draft after a newer error',
    (tester) async {
      final catalog = WorkspaceCatalogRepository(ClientRepository());
      final service = _DelayedTextService();
      final controller = AssistantController(
        service: service,
        basicService: BasicAssistantService(catalog),
        repository: catalog,
      );
      addTearDown(controller.dispose);
      await pump(
        tester,
        AssistantScreen(controller: controller, embedded: true),
      );
      final input = find.byKey(const Key('assistant-input'));
      await tester.enterText(input, 'Приватный текст прошлого аккаунта');
      await tester.pump();
      await tester.tap(find.byKey(const Key('assistant-send')));
      await tester.pump();
      expect(service.pending.length, 1);
      controller.reset();
      final newer = controller.sendMessage('Запрос другого аккаунта');
      service.pending.last.completeError(
        const AssistantServiceException('Ошибка нового запроса'),
      );
      await newer;
      await tester.pumpAndSettle();
      service.pending.first.complete(
        const AssistantTurn(brief: AssistantBrief(), message: 'Поздний ответ'),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(input).controller!.text, isEmpty);
      expect(controller.error, 'Ошибка нового запроса');
    },
  );

  testWidgets(
    'account reset clears an unsent draft even before a route context key exists',
    (tester) async {
      final repository = ClientRepository();
      final catalog = WorkspaceCatalogRepository(repository);
      final controller = AssistantController(
        service: _TextService(),
        basicService: BasicAssistantService(catalog),
        repository: catalog,
      );
      addTearDown(controller.dispose);
      await pump(
        tester,
        AssistantScreen(controller: controller, embedded: true),
      );
      final input = find.byKey(const Key('assistant-input'));
      await tester.enterText(input, 'Приватный черновик прошлого аккаунта');
      expect(controller.contextKey, isNull);
      controller.reset();
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(input).controller!.text, isEmpty);
    },
  );

  testWidgets(
    'event entry asks only for category and keeps known event facts',
    (tester) async {
      final repository = ClientRepository();
      seedEventAndSelection(repository);
      repository.selections.clear();
      final controller = await _assistant(repository);
      await pump(tester, _page(repository, controller));
      expect(controller.brief.city, repository.events.single.city);
      expect(controller.brief.date, dateKey(repository.events.single.date));
      expect(controller.brief.eventFormat, repository.events.single.format);
      expect(controller.turn!.questionField, 'category');
      expect(controller.turn!.result, isNull);
      expect(find.byKey(const Key('integrated-assistant')), findsOneWidget);
      await _chooseHost(tester);
      expect(controller.turn!.questionField, 'budget_kzt');
      expect(
        controller.turn!.result!.recommendations.single.contractor.id,
        'provider',
      );
      expect(
        controller.turn!.result!.unchecked,
        isNot(contains('Дата не проверена')),
      );
      expect(
        find.byKey(const Key('assistant-contractor-provider')),
        findsOneWidget,
      );
      expect(
        controller.events
            .where((e) => e['event'] == 'clarification_shown')
            .map((e) => e['field']),
        ['category', 'budget_kzt'],
      );
    },
  );

  testWidgets(
    'inline recommendation exposes working favorite and inquiry actions',
    (tester) async {
      final repository = ClientRepository();
      seedEventAndSelection(repository);
      final controller = await _assistant(repository);
      Contractor? inquiry;
      await pump(
        tester,
        _page(
          repository,
          controller,
          selectionId: 'selection-1',
          onCreateInquiry: (value) => inquiry = value,
        ),
      );
      expect(
        find.byKey(const Key('assistant-contractor-provider')),
        findsOneWidget,
      );
      await _tap(tester, find.text('В избранное'));
      expect(repository.favorites.single.id, 'provider');
      expect(find.text('Убрать из избранного'), findsOneWidget);
      await _tap(tester, find.text('Обсудить мероприятие'));
      expect(inquiry!.id, 'provider');
    },
  );

  testWidgets(
    'event-aware result saves directly without asking to choose the event again',
    (tester) async {
      final repository = ClientRepository();
      seedEventAndSelection(repository);
      repository.selections.clear();
      final controller = await _assistant(repository);
      await pump(tester, _page(repository, controller));
      await _chooseHost(tester);
      await _tap(
        tester,
        find.byKey(const Key('assistant-action-manual:budget:120000')),
      );
      expect(controller.turn!.result!.preliminary, isFalse);
      await _tap(tester, find.text('Сохранить в «Наша свадьба»'));
      expect(find.text('Сохранить в мероприятие'), findsNothing);
      expect(repository.events.length, 1);
      expect(repository.selections.single.eventId, 'event-1');
      expect(repository.selections.single.request.budget, 120000);
      expect(
        repository.selections.single.entries.single.contractor.id,
        'provider',
      );
      expect(find.text('Подборка сохранена'), findsOneWidget);
    },
  );

  testWidgets(
    'cancelling required budget entry leaves the result unsaved without an error',
    (tester) async {
      final repository = ClientRepository();
      seedEventAndSelection(repository);
      repository.selections.clear();
      final controller = await _assistant(repository);
      await pump(tester, _page(repository, controller));
      await _chooseHost(tester);
      final save = find.text('Сохранить в «Наша свадьба»');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Отмена'));
      await tester.pumpAndSettle();
      expect(repository.selections, isEmpty);
      expect(controller.brief.budgetKzt, isNull);
      expect(controller.error, isNull);
      expect(find.textContaining('Для окончательного подбора'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'guest save restores full wishes after sign-in and asks where to save once',
    (tester) async {
      final repository = ClientRepository();
      seedEventAndSelection(repository);
      repository.selections.clear();
      final controller = await _assistant(repository);
      var signIns = 0;
      await pump(
        tester,
        CatalogPage(
          repository: repository,
          assistant: controller,
          onRequireSignIn: () => signIns++,
        ),
      );
      final brief = AssistantBrief(
        city: 'Алматы',
        category: 'Ведущий',
        eventFormat: 'свадьба',
        date: dateKey(repository.events.single.date),
        budgetKzt: 300000,
        preferences: const [
          AssistantPreference(
            text: 'Строго без конкурсов',
            importance: 'required',
            polarity: 'negative',
          ),
        ],
      );
      controller.replaceContext(brief, 'guest-test');
      await controller.act(
        const AssistantAction(
          id: 'show',
          label: 'Показать',
          type: 'show_results',
        ),
      );
      await tester.pumpAndSettle();
      await _tap(tester, find.text('Сохранить подборку'));
      expect(signIns, 1);
      expect(repository.selections, isEmpty);
      controller.reset();
      await pump(tester, _page(repository, controller, eventId: null));
      expect(controller.brief.preferences.single.importance, 'required');
      expect(controller.brief.preferences.single.polarity, 'negative');
      expect(find.text('Сохранить в мероприятие'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Название мероприятия'),
        'Событие гостя',
      );
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();
      expect(
        repository.selections.single.request.preferences,
        'Строго без конкурсов',
      );
      expect(repository.events.length, 2);
      expect(find.text('Подборка сохранена'), findsOneWidget);
    },
  );

  testWidgets(
    'refreshing an existing selection updates its snapshot instead of duplicating it',
    (tester) async {
      final repository = ClientRepository();
      seedEventAndSelection(repository);
      final controller = await _assistant(repository);
      await pump(
        tester,
        _page(repository, controller, selectionId: 'selection-1'),
      );
      await controller.act(
        const AssistantAction(
          id: 'test-budget',
          label: 'До 200000 ₸',
          type: 'set_field',
          field: 'budget_kzt',
          value: 200000,
        ),
      );
      await tester.pumpAndSettle();
      await _tap(tester, find.text('Сохранить в «Наша свадьба»'));
      expect(repository.selections.length, 1);
      expect(repository.selections.single.id, 'selection-1');
      expect(repository.selections.single.request.budget, 200000);
    },
  );

  testWidgets(
    'missing event or selection displays an explicit error without falling back',
    (tester) async {
      final repository = ClientRepository();
      seedEventAndSelection(repository);
      final controller = await _assistant(repository);
      await pump(
        tester,
        _page(repository, controller, eventId: 'deleted-event'),
      );
      expect(find.text('Мероприятие недоступно'), findsOneWidget);
      expect(find.textContaining('Мероприятие не найдено'), findsOneWidget);
      expect(find.byKey(const Key('integrated-assistant')), findsNothing);
      expect(controller.turn, isNull);
      await pump(
        tester,
        _page(repository, controller, selectionId: 'deleted-selection'),
      );
      expect(
        find.textContaining('Сохранённая подборка не найдена'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('integrated-assistant')), findsNothing);
      expect(controller.turn, isNull);
    },
  );

  testWidgets(
    'reopening a saved selection imports changed remote budget and wishes',
    (tester) async {
      final repository = ClientRepository();
      seedEventAndSelection(repository);
      final controller = await _assistant(repository);
      await pump(
        tester,
        _page(repository, controller, selectionId: 'selection-1'),
      );
      expect(controller.brief.budgetKzt, 1000000);
      await tester.pumpWidget(const SizedBox.shrink());
      final previous = repository.selections.single;
      repository.selections[0] = SavedSelection(
        id: previous.id,
        eventId: previous.eventId,
        name: previous.name,
        entries: previous.entries,
        request: MatchRequest.fromJson({
          ...previous.request.toJson(),
          'budget_kzt': 150000,
          'preferences': 'Камерный вечер без конкурсов',
        }),
      );
      await pump(
        tester,
        _page(repository, controller, selectionId: 'selection-1'),
      );
      expect(controller.brief.budgetKzt, 150000);
      expect(
        controller.brief.preferences.single.text,
        'Камерный вечер без конкурсов',
      );
    },
  );

  testWidgets(
    'manual filters start with current brief and preserve refinements after navigation',
    (tester) async {
      final repository = ClientRepository();
      seedEventAndSelection(repository);
      final previous = repository.selections.single;
      repository.selections[0] = SavedSelection(
        id: previous.id,
        eventId: previous.eventId,
        name: previous.name,
        entries: previous.entries,
        request: MatchRequest.fromJson({
          ...previous.request.toJson(),
          'budget_kzt': 200000,
        }),
      );
      final controller = await _assistant(repository);
      await pump(
        tester,
        _page(repository, controller, selectionId: 'selection-1'),
      );
      final routeKey = controller.contextKey;
      await _tap(tester, find.byKey(const Key('live-open-filters')));
      final budget = find.byKey(const Key('budget-input'));
      expect(tester.widget<TextFormField>(budget).controller!.text, '200000');
      await tester.enterText(budget, '150000');
      await _tap(tester, find.byKey(const Key('apply-filters')));
      expect(controller.contextKey, routeKey);
      expect(controller.brief.budgetKzt, 150000);
      await tester.pumpWidget(const SizedBox.shrink());
      await pump(
        tester,
        _page(repository, controller, selectionId: 'selection-1'),
      );
      expect(controller.brief.budgetKzt, 150000);
      expect(
        controller.turn!.result!.recommendations.single.contractor.id,
        'provider',
      );
    },
  );

  testWidgets('busy live calendar cannot become an inline recommendation', (
    tester,
  ) async {
    final repository = ClientRepository();
    seedEventAndSelection(repository);
    repository.busy = true;
    final controller = await _assistant(repository);
    await pump(
      tester,
      _page(repository, controller, selectionId: 'selection-1'),
    );
    expect(controller.turn!.result!.outcome, MatchOutcome.noEligible);
    expect(
      find.byKey(const Key('assistant-contractor-provider')),
      findsNothing,
    );
    expect(find.text('Сохранить в «Наша свадьба»'), findsNothing);
  });

  for (final width in [375.0, 768.0, 1440.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('integrated results fit $width pixels at ${scale}x text', (
        tester,
      ) async {
        final repository = ClientRepository();
        seedEventAndSelection(repository);
        final controller = await _assistant(repository);
        await pump(
          tester,
          _page(
            repository,
            controller,
            selectionId: 'selection-1',
            onCreateInquiry: (_) {},
          ),
          width: width,
          scale: scale,
        );
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.text('Сохранить в «Наша свадьба»'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final card = find.byKey(const Key('assistant-contractor-provider'));
        expect(tester.getSize(card).width, lessThanOrEqualTo(width - 32));
        for (final label in [
          'В избранное',
          'Обсудить мероприятие',
          'Сохранить в «Наша свадьба»',
        ]) {
          await tester.ensureVisible(find.text(label));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
      });
    }
  }
}
