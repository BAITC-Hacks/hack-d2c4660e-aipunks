import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:event_match/features/assistant/data/basic_assistant_service.dart';
import 'package:event_match/features/assistant/domain/assistant_models.dart';
import 'package:event_match/features/assistant/domain/assistant_service.dart';
import 'package:event_match/features/assistant/presentation/assistant_controller.dart';
import 'package:event_match/features/assistant/presentation/assistant_host.dart';
import 'package:event_match/features/matching/data/catalog_repository.dart';
import 'package:event_match/features/matching/domain/models.dart';
import 'package:event_match/features/workspace/domain/workspace_models.dart'
    show CalendarMonth;

class _Catalog implements CatalogRepository {
  _Catalog(this.profiles);
  final List<Contractor> profiles;
  @override
  Future<List<Contractor>> load() async => profiles;
}

class _Delayed implements AssistantService {
  final pending = <Completer<AssistantTurn>>[];
  final histories = <List<AssistantMessage>>[];
  @override
  bool get supportsFreeText => true;
  @override
  Future<AssistantTurn> send({
    required AssistantBrief brief,
    String? message,
    AssistantAction? action,
    List<AssistantMessage> history = const [],
  }) {
    histories.add(history);
    final future = Completer<AssistantTurn>();
    pending.add(future);
    return future.future;
  }
}

AssistantAction _set(String field, Object value) => AssistantAction(
  id: 'manual:$field',
  label: '$value',
  type: 'set_field',
  field: field,
  value: value,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Catalog catalog;
  late BasicAssistantService basic;
  setUpAll(() async {
    catalog = _Catalog(await AssetCatalogRepository().load());
    basic = BasicAssistantService(catalog);
  });
  const initial = AssistantBrief(
    city: 'Алматы',
    category: 'Ведущий',
    eventFormat: 'свадьба',
  );
  const show = AssistantAction(
    id: 'manual:show',
    label: 'Показать',
    type: 'show_results',
  );

  test('empty brief contains no demonstration conditions', () {
    const b = AssistantBrief();
    expect(b.canRecommend, false);
    expect(b.city, isNull);
    expect(b.date, isNull);
    expect(b.budgetKzt, isNull);
  });

  test(
    'confirmed live request uses its own date policy, retaining demo default',
    () {
      final policy = MatchDatePolicy.live(DateTime.utc(2027, 1, 10));
      final brief = initial
          .withField('date', '2027-02-14')
          .withField('budget_kzt', 300000);
      expect(() => brief.toMatchRequest(), throwsStateError);
      expect(
        dateKey(brief.toMatchRequest(datePolicy: policy).date),
        '2027-02-14',
      );
      expect(
        () => brief
            .withField('date', '2028-02-14')
            .toMatchRequest(datePolicy: policy),
        throwsStateError,
      );
    },
  );

  test(
    'live fallback requires fresh matching calendars and rereads them every turn',
    () async {
      final now = DateTime.utc(2027, 1, 10, 10);
      const ids = [
        'available',
        'busy',
        'missing',
        'stale',
        'future',
        'owner',
        'month',
        'offline',
      ];
      final liveCatalog = _Catalog([
        for (final id in ids)
          Contractor(
            id: id,
            name: id,
            city: 'Алматы',
            categories: const ['Ведущий'],
            price: 100000,
            formats: const ['свадьба'],
            languages: const ['русский'],
            busyDates: const [],
            description: 'Профиль',
            isLive: true,
          ),
      ]);
      final reads = <String>[];
      var availableBecomesBusy = false;
      final live = BasicAssistantService(
        liveCatalog,
        datePolicy: MatchDatePolicy.live(now),
        clock: () => now,
        calendarResolver: (id, date) async {
          reads.add(id);
          if (id == 'offline') throw StateError('Offline');
          if (id == 'missing') return null;
          return CalendarMonth(
            ownerId: id == 'owner' ? 'someone-else' : id,
            year: date.year,
            month: id == 'month' ? date.month + 1 : date.month,
            busyDays:
                id == 'busy' || (id == 'available' && availableBecomesBusy)
                ? [date.day]
                : [],
            confirmedAt: id == 'stale'
                ? now.subtract(const Duration(days: 30))
                : id == 'future'
                ? now.add(const Duration(seconds: 1))
                : now,
          );
        },
      );
      final brief = initial
          .withField('date', '2027-02-14')
          .withField('budget_kzt', 300000);
      final first = await live.send(brief: brief, action: show);
      expect(first.result!.recommendations.map((r) => r.contractor.id), [
        'available',
      ]);
      expect(first.result!.preliminary, isFalse);
      expect(
        first.result!.recommendations.single.explanation,
        contains('подтверждённому календарю'),
      );
      expect(first.result!.summary, contains('доступность не подтверждена'));
      availableBecomesBusy = true;
      final second = await live.send(brief: brief, action: show);
      expect(second.result!.outcome, MatchOutcome.noEligible);
      expect(reads.where((id) => id == 'available').length, 2);
    },
  );

  test(
    'unknown and out-of-horizon live dates remain preliminary without calendar claims',
    () async {
      final now = DateTime.utc(2027, 1, 10);
      var reads = 0;
      final live = BasicAssistantService(
        catalog,
        datePolicy: MatchDatePolicy.live(now),
        clock: () => now,
        calendarResolver: (id, date) async {
          reads++;
          return null;
        },
      );
      for (final brief in [initial, initial.withField('date', '2028-02-14')]) {
        final turn = await live.send(
          brief: brief.withField('budget_kzt', 1000000),
          action: show,
        );
        expect(turn.result!.preliminary, isTrue);
        expect(turn.result!.recommendations, isNotEmpty);
        expect(
          turn.result!.recommendations.every(
            (r) => !r.explanation.contains('Свободен'),
          ),
          isTrue,
        );
      }
      expect(reads, 0);
      final outside = await live.send(
        brief: initial.withField('date', '2028-02-14'),
        action: show,
      );
      expect(
        outside.result!.unchecked,
        contains(contains('2027-01-10–2028-01-10')),
      );
      final withoutResolver = BasicAssistantService(
        catalog,
        datePolicy: MatchDatePolicy.live(now),
      );
      final confirmedDate = await withoutResolver.send(
        brief: initial.withField('date', '2027-02-14'),
        action: show,
      );
      expect(confirmedDate.result!.outcome, MatchOutcome.noEligible);
    },
  );

  test('session accepts injected fallback for its live source', () async {
    final delayed = _Delayed();
    final liveFallback = BasicAssistantService(
      catalog,
      datePolicy: MatchDatePolicy.live(),
    );
    final session = AssistantSession(
      repository: catalog,
      service: delayed,
      basicService: liveFallback,
      source: 'live',
    );
    expect(session.controller.service, same(delayed));
    expect(session.controller.basicService, same(liveFallback));
    expect(session.controller.timeout, const Duration(seconds: 25));
    session.dispose();
  });

  test(
    'replacing route context cancels stale responses and preserves stable-key refinements',
    () async {
      final delayed = _Delayed();
      final controller = AssistantController(
        service: delayed,
        basicService: basic,
        repository: catalog,
      );
      controller.replaceContext(initial, 'event-1');
      final old = controller.sendMessage('На старое мероприятие');
      final next = initial.withField('category', 'Фотограф');
      controller.replaceContext(next, 'event-2');
      expect(controller.messages, isEmpty);
      expect(controller.turn, isNull);
      expect(controller.busy, isFalse);
      await controller.retry();
      expect(delayed.pending.length, 1);
      delayed.pending.single.complete(
        const AssistantTurn(brief: initial, message: 'Старый результат'),
      );
      await old;
      expect(controller.brief.category, 'Фотограф');
      final updated = controller.act(_set('budget_kzt', 300000));
      delayed.pending.last.complete(
        AssistantTurn(
          brief: next.withField('budget_kzt', 300000),
          message: 'Новый бюджет',
        ),
      );
      await updated;
      controller.replaceContext(next, 'event-2');
      expect(controller.brief.budgetKzt, 300000);
      expect(controller.turn!.message, 'Новый бюджет');
      controller.replaceContext(next, 'event-2', force: true);
      expect(controller.contextKey, 'event-2');
      expect(controller.brief.budgetKzt, isNull);
      expect(controller.messages, isEmpty);
      expect(controller.turn, isNull);
      controller.dispose();
    },
  );

  test(
    'new applied catalog request replaces previous conversation conditions',
    () async {
      final controller = AssistantController(
        service: basic,
        basicService: basic,
        repository: catalog,
      );
      final first = initial
          .withField('date', '2026-11-14')
          .withField('budget_kzt', 300000)
          .toMatchRequest();
      controller.seedFromRequest(first);
      await controller.act(show);
      expect(controller.messages, isNotEmpty);
      final next = initial
          .withField('date', '2026-11-15')
          .withField('budget_kzt', 500000)
          .toMatchRequest();
      controller.seedFromRequest(next);
      expect(controller.brief.date, '2026-11-15');
      expect(controller.brief.budgetKzt, 500000);
      expect(controller.messages, isEmpty);
      expect(controller.turn, isNull);
      controller.dispose();
    },
  );

  test(
    'partial brief gives honest preliminary results before asking date',
    () async {
      final turn = await basic.send(brief: initial, action: show);
      expect(turn.result!.recommendations.length, 3);
      expect(turn.result!.preliminary, true);
      expect(turn.result!.unchecked, contains('Дата не проверена'));
      expect(turn.questionField, 'date');
      expect(turn.mode, 'basic');
      expect(
        turn.result!.recommendations.every(
          (r) => !r.explanation.contains('Свободен'),
        ),
        true,
      );
    },
  );

  test('skipped date is not asked again and corrections clear skip', () async {
    final skipped = await basic.send(
      brief: initial,
      action: const AssistantAction(
        id: 'skip',
        label: 'Пока не знаю',
        type: 'skip_field',
        field: 'date',
      ),
    );
    expect(skipped.questionField, 'budget_kzt');
    final budget = await basic.send(
      brief: skipped.brief,
      action: _set('budget_kzt', 1000000),
    );
    expect(budget.questionField, isNull);
    final corrected = await basic.send(
      brief: budget.brief,
      action: _set('date', '2026-11-14'),
    );
    expect(corrected.brief.skippedFields, isNot(contains('date')));
    expect(corrected.result!.preliminary, false);
  });

  test(
    'complete request filters busy profiles and order stays stable',
    () async {
      final b = initial
          .withField('budget_kzt', 1000000)
          .withField('date', '2026-11-14');
      final first = await basic.send(brief: b, action: show);
      final second = await basic.send(brief: b, action: show);
      expect(
        first.result!.recommendations.map((r) => r.contractor.id),
        second.result!.recommendations.map((r) => r.contractor.id),
      );
      for (final r in first.result!.recommendations) {
        expect(r.contractor.busyDates, isNot(contains('2026-11-14')));
        expect(r.contractor.price, lessThanOrEqualTo(1000000));
      }
      final changed = await basic.send(
        brief: b,
        action: _set('date', '2026-10-10'),
      );
      expect(
        changed.result!.recommendations.map((r) => r.contractor.id).toList(),
        isNot(
          first.result!.recommendations.map((r) => r.contractor.id).toList(),
        ),
      );
    },
  );

  test('rare, absent and filtered-out categories are distinct', () async {
    final rare = await basic.send(
      brief: initial
          .withField('category', 'Флорист')
          .withField('date', '2026-10-10')
          .withField('budget_kzt', 1000000),
      action: show,
    );
    expect(rare.result!.outcome, MatchOutcome.matched);
    expect(rare.result!.recommendations.length, lessThan(3));
    final absent = await basic.send(
      brief: initial
          .withField('city', 'Зарубежье')
          .withField('category', 'Флорист'),
      action: show,
    );
    expect(absent.result!.outcome, MatchOutcome.categoryAbsent);
    final expensive = await basic.send(
      brief: initial.withField('budget_kzt', 1),
      action: show,
    );
    expect(expensive.result!.outcome, MatchOutcome.noEligible);
    expect(expensive.result!.summary, contains('выше бюджета'));
  });

  test(
    'unknown wishes and outside date never promise full suitability',
    () async {
      final b = AssistantBrief.fromJson({
        ...initial.toJson(),
        'date': '2027-01-10',
        'budget_kzt': 1000000,
        'preferences': [
          const AssistantPreference(
            text: 'Строго без конкурсов',
            importance: 'required',
            polarity: 'negative',
          ).toJson(),
        ],
      });
      final turn = await basic.send(brief: b, action: show);
      expect(turn.result!.preliminary, true);
      expect(turn.result!.unchecked.length, 2);
      expect(() => b.toMatchRequest(), throwsStateError);
      expect(
        () => basic.send(brief: initial, action: _set('date', '2026-02-31')),
        throwsA(isA<AssistantServiceException>()),
      );
    },
  );

  test('event budget does not constrain a single contractor', () async {
    final turn = await basic.send(
      brief: AssistantBrief.fromJson({
        ...initial.toJson(),
        'budget_kzt': 1,
        'budget_scope': 'event',
      }),
      action: show,
    );
    expect(turn.result!.recommendations, isNotEmpty);
    expect(turn.result!.unchecked, contains('Бюджет подрядчика не задан'));
  });

  test(
    'manual results keep unsupported city and unknown hours honest',
    () async {
      final absent = await basic.send(
        brief: initial.withField('city', 'Город вне каталога'),
        action: show,
      );
      expect(absent.result!.outcome, MatchOutcome.categoryAbsent);
      final contractor = catalog.profiles.firstWhere((c) => c.maxHours == null);
      final service = BasicAssistantService(_Catalog([contractor]));
      final date = List.generate(
        100,
        (i) => dateKey(DateTime(2026, 9, 23).add(Duration(days: i))),
      ).firstWhere((date) => !contractor.busyDates.contains(date));
      final turn = await service.send(
        brief: AssistantBrief(
          city: contractor.city,
          category: contractor.categories.first,
          eventFormat: contractor.formats.first,
          date: date,
          budgetKzt: 1000000000,
          hours: 8,
        ),
        action: show,
      );
      expect(turn.result!.preliminary, true);
      expect(
        turn.result!.recommendations.single.unchecked,
        contains('Длительность не подтверждена'),
      );
    },
  );

  test('next specialist keeps only shared event conditions', () async {
    final b = initial
        .withField('date', '2026-11-14')
        .withField('budget_kzt', 1000000)
        .withField('language', 'русский');
    final turn = await basic.send(
      brief: b,
      action: const AssistantAction(
        id: 'next',
        label: 'Дальше',
        type: 'next_category',
        value: 'Фотограф',
      ),
    );
    expect(turn.brief.city, b.city);
    expect(turn.brief.date, b.date);
    expect(turn.brief.eventFormat, b.eventFormat);
    expect(turn.brief.category, 'Фотограф');
    expect(turn.brief.budgetKzt, isNull);
    expect(turn.brief.language, isNull);
  });

  test('category correction preserves other conditions', () async {
    final b = initial
        .withField('budget_kzt', 1000000)
        .withField('language', 'русский');
    final turn = await basic.send(
      brief: b,
      action: _set('category', 'Фотограф'),
    );
    expect(turn.brief.budgetKzt, 1000000);
    expect(turn.brief.language, 'русский');
  });

  test(
    'manual service rejects free text rather than inventing understanding',
    () async {
      expect(
        () => basic.send(brief: initial, message: 'Нет, Астана'),
        throwsA(isA<AssistantServiceException>()),
      );
    },
  );

  test('reset and newer input invalidate late replies', () async {
    final delayed = _Delayed();
    final controller = AssistantController(
      service: delayed,
      basicService: basic,
      repository: catalog,
    );
    final first = controller.sendMessage('Нужен ведущий');
    controller.reset();
    final second = controller.sendMessage('Нужен фотограф');
    delayed.pending.last.complete(
      AssistantTurn(
        brief: initial.withField('category', 'Фотограф'),
        message: 'На какую дату?',
      ),
    );
    await second;
    delayed.pending.first.complete(
      const AssistantTurn(brief: initial, message: 'Старый ответ'),
    );
    await first;
    expect(controller.brief.category, 'Фотограф');
    expect(controller.messages.any((m) => m.text == 'Старый ответ'), false);
    controller.dispose();
  });

  test(
    'retry does not duplicate user messages and errors preserve brief',
    () async {
      final delayed = _Delayed();
      final controller = AssistantController(
        service: delayed,
        basicService: basic,
        repository: catalog,
      );
      controller.brief = initial;
      final first = controller.sendMessage('Дата 14 ноября');
      delayed.pending.first.completeError(
        const AssistantServiceException('offline'),
      );
      await first;
      expect(controller.brief, initial);
      final retry = controller.retry();
      delayed.pending.last.complete(
        AssistantTurn(
          brief: initial.withField('date', '2026-11-14'),
          message: 'Учёл дату',
        ),
      );
      await retry;
      expect(controller.messages.where((m) => m.role == 'user').length, 1);
      expect(controller.error, isNull);
      controller.dispose();
    },
  );

  test('manual fallback applies the pending typed correction', () async {
    final delayed = _Delayed();
    final controller = AssistantController(
      service: delayed,
      basicService: basic,
      repository: catalog,
    );
    controller.brief = initial;
    final failed = controller.act(_set('budget_kzt', 250000));
    delayed.pending.first.completeError(
      const AssistantServiceException('offline'),
    );
    await failed;
    await controller.useBasicMode();
    expect(controller.brief.budgetKzt, 250000);
    expect(controller.brief.city, initial.city);
    expect(controller.messages.where((m) => m.role == 'user').length, 1);
    expect(controller.turn!.mode, 'basic');
    controller.dispose();
  });

  test(
    'switching to basic mode preserves conditions and ignores pending AI',
    () async {
      final delayed = _Delayed();
      final controller = AssistantController(
        service: delayed,
        basicService: basic,
        repository: catalog,
      );
      controller.brief = initial;
      final old = controller.sendMessage('Покажи');
      await controller.useBasicMode();
      delayed.pending.first.complete(
        const AssistantTurn(brief: AssistantBrief(), message: 'Old'),
      );
      await old;
      expect(controller.brief.city, initial.city);
      expect(controller.turn!.mode, 'basic');
      controller.reset();
      expect(controller.service, same(delayed));
      controller.dispose();
    },
  );
}
