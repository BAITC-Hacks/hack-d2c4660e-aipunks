import 'package:event_match/features/matching/domain/models.dart';
import 'package:event_match/features/planning/domain/event_plan.dart';
import 'package:event_match/features/planning/domain/event_plan_engine.dart';
import 'package:event_match/features/workspace/domain/workspace_models.dart';
import 'package:flutter_test/flutter_test.dart';

final now = DateTime.utc(2026, 9, 23, 10);
final event = ClientEvent(
  id: 'event',
  name: 'Наша свадьба',
  city: 'Алматы',
  date: DateTime(2026, 11, 14),
  format: 'свадьба',
  preferences: 'Спокойная программа',
);

ProfileContent content({
  String city = 'Алматы',
  List<String> categories = const ['Ведущий'],
  int price = 100000,
  List<String> formats = const ['свадьба'],
  List<String> languages = const ['русский'],
  double? maxHours = 5,
}) => ProfileContent(
  name: 'Айжан',
  city: city,
  categories: categories,
  price: price,
  formats: formats,
  languages: languages,
  maxHours: maxHours,
  description: 'Камерные события со спокойной программой.',
  contact: 'contact@example.com',
);

PublishedProfile published(
  String id, {
  ProfileContent? profile,
  bool visible = true,
}) => PublishedProfile(
  ownerId: id,
  content: profile ?? content(),
  revision: 2,
  profileRevision: 3,
  published: visible,
);

CalendarMonth calendar(
  String id, {
  List<int> busyDays = const [],
  DateTime? confirmedAt,
  int month = 11,
}) => CalendarMonth(
  ownerId: id,
  year: 2026,
  month: month,
  busyDays: busyDays,
  confirmedAt: confirmedAt ?? now,
);

SavedSelection selection({
  String id = 'selection',
  String eventId = 'event',
  String category = 'Ведущий',
  List<String> contractorIds = const ['a'],
  String city = 'Алматы',
  DateTime? date,
  String format = 'свадьба',
  String preferences = 'Спокойная программа',
  int budget = 200000,
  int price = 100000,
  double? hours = 4,
  String? language = 'русский',
}) => SavedSelection(
  id: id,
  eventId: eventId,
  name: '$category · Свадьба',
  request: MatchRequest(
    city: city,
    date: date ?? event.date,
    format: format,
    preferences: preferences,
    category: category,
    budget: budget,
    hours: hours,
    language: language,
  ),
  entries: [
    for (final id in contractorIds)
      Recommendation(
        content(categories: [category], price: price).toContractor(id),
        'Историческое объяснение для $id.',
      ),
  ],
);

EventPlan chosenPlan({int? budget = 300000}) => EventPlan(
  eventId: event.id,
  totalBudgetKzt: budget,
  choices: const {
    'Ведущий': PlanChoice(selectionId: 'selection', contractorId: 'a'),
  },
);

EventPlanReview review({
  ClientEvent? currentEvent,
  List<SavedSelection>? selections,
  EventPlan? plan,
  Map<String, PublishedProfile>? profiles,
  Map<String, CalendarMonth?>? calendars,
}) => const EventPlanEngine().build(
  event: currentEvent ?? event,
  selections: selections ?? [selection()],
  plan: plan ?? chosenPlan(),
  published: profiles ?? {'a': published('a')},
  calendars: calendars ?? {'a': calendar('a')},
  now: now,
);

void main() {
  test(
    'plan roundtrip preserves decisions and supports clearing the budget',
    () {
      final original = chosenPlan().copyWith(
        notes: 'Попросить смету',
        completedTaskIds: {'confirm_scope'},
        revision: 4,
      );
      final map = original.toMap();
      expect(map['schemaVersion'], 1);
      expect(map.containsKey('eventId'), isFalse);
      expect(map.containsKey('ownerId'), isFalse);
      final decoded = EventPlan.fromMap('event', {...map, 'updatedAt': now});
      expect(decoded.toMap(), map);
      expect(decoded.copyWith(notes: 'Новая заметка').totalBudgetKzt, 300000);
      expect(decoded.copyWith(totalBudgetKzt: null).totalBudgetKzt, isNull);
      expect(decoded.remove('Ведущий').choices, isEmpty);
      expect(decoded.choices, hasLength(1));
    },
  );

  test('plan validates bounds, known fields and safe document references', () {
    final invalid = [
      const EventPlan(eventId: ''),
      const EventPlan(eventId: 'a/b'),
      const EventPlan(eventId: '.'),
      const EventPlan(eventId: '..'),
      const EventPlan(eventId: 'event', totalBudgetKzt: 0),
      const EventPlan(eventId: 'event', totalBudgetKzt: 1000000001),
      EventPlan(eventId: 'event', notes: 'a' * 2001),
      const EventPlan(eventId: 'event', revision: -1),
      const EventPlan(
        eventId: 'event',
        completedTaskIds: {'confirmed_booking'},
      ),
      const EventPlan(
        eventId: 'event',
        choices: {
          'Несуществующая': PlanChoice(selectionId: 's', contractorId: 'a'),
        },
      ),
      const EventPlan(
        eventId: 'event',
        choices: {'Ведущий': PlanChoice(selectionId: 's/b', contractorId: 'a')},
      ),
      const EventPlan(
        eventId: 'event',
        choices: {'Ведущий': PlanChoice(selectionId: '.', contractorId: 'a')},
      ),
      const EventPlan(
        eventId: 'event',
        choices: {'Ведущий': PlanChoice(selectionId: 's', contractorId: '..')},
      ),
      EventPlan(
        eventId: 'event',
        choices: {
          'Ведущий': PlanChoice(selectionId: 's', contractorId: 'a' * 161),
        },
      ),
    ];
    for (final plan in invalid) {
      expect(plan.validate, throwsArgumentError);
    }
    expect(
      () => EventPlan.fromMap('event', {
        ...chosenPlan().toMap(),
        'schemaVersion': 2,
      }),
      throwsFormatException,
    );
    expect(
      const EventPlan(eventId: 'event', totalBudgetKzt: 1000000000).validate,
      returnsNormally,
    );
  });

  test('one supplier cannot be counted twice across categories', () {
    expect(
      () => chosenPlan().choose(
        'Фотограф',
        const PlanChoice(selectionId: 'photos', contractorId: 'a'),
      ),
      throwsArgumentError,
    );
    final result = review(
      selections: [
        selection(),
        selection(id: 'photos', category: 'Фотограф'),
      ],
      profiles: {
        'a': published(
          'a',
          profile: content(categories: ['Ведущий', 'Фотограф']),
        ),
      },
    );
    expect(result.groups.last.candidates.single.canChoose, isFalse);
    expect(result.estimatedFromKzt, 100000);
    expect(result.unresolvedCategories, ['Фотограф']);
  });

  test(
    'comparison preserves input order, caps at three and ignores foreign events',
    () {
      final selections = [
        selection(id: 'foreign', eventId: 'other-event'),
        selection(contractorIds: ['c', 'a', 'b', 'd']),
      ];
      final result = review(selections: selections);
      expect(result.groups, hasLength(1));
      expect(result.groups.single.candidates.map((c) => c.contractorId), [
        'c',
        'a',
        'b',
      ]);
      expect(selections.last.entries, hasLength(4));
      expect(
        result.groups.single.candidates[1].recommendation.explanation,
        contains('Историческое'),
      );
      expect(
        review(
          selections: selections,
        ).groups.single.candidates.map((c) => c.contractorId),
        ['c', 'a', 'b'],
      );
    },
  );

  test(
    'current price is a lower bound; changed price warns without mutating snapshot',
    () {
      final result = review(
        profiles: {'a': published('a', profile: content(price: 140000))},
      );
      final candidate = result.groups.single.candidates.single;
      expect(candidate.canChoose, isTrue);
      expect(candidate.warnings.single, contains('140000'));
      expect(candidate.recommendation.contractor.price, 100000);
      expect(candidate.currentPriceKzt, 140000);
      expect(result.selectedCount, 1);
      expect(result.estimatedFromKzt, 140000);
      expect(result.remainingBudgetKzt, 160000);
    },
  );

  test(
    'changed conditions invalidate saved selection even when current supplier fits',
    () {
      for (final saved in [
        selection(city: 'Астана'),
        selection(date: DateTime(2026, 11, 15)),
        selection(format: 'той'),
      ]) {
        final result = review(selections: [saved]);
        expect(result.groups.single.staleBrief, isTrue);
        expect(result.groups.single.candidates.single.canChoose, isFalse);
        expect(result.groups.single.candidates.single.isSelected, isTrue);
        expect(result.unresolvedCount, 1);
        expect(result.estimatedFromKzt, isNull);
        expect(result.remainingBudgetKzt, isNull);
      }
    },
  );

  test(
    'category wishes do not invalidate otherwise current saved selection',
    () {
      final result = review(
        selections: [selection(preferences: 'Без конкурсов')],
      );
      expect(result.groups.single.staleBrief, isFalse);
      expect(result.groups.single.candidates.single.canChoose, isTrue);
      expect(result.unresolvedCount, 0);
    },
  );

  test('calendar is checked at current event date, including stale brief', () {
    final movedEvent = ClientEvent(
      id: event.id,
      name: event.name,
      city: event.city,
      date: DateTime(2026, 11, 15),
      format: event.format,
      preferences: event.preferences,
    );
    final result = review(
      currentEvent: movedEvent,
      calendars: {
        'a': calendar('a', busyDays: [15]),
      },
    );
    expect(
      result.groups.single.candidates.single.blockers,
      contains('Дата мероприятия занята.'),
    );
  });

  test('busy, unknown, wrong owner/month and stale calendars fail closed', () {
    for (final value in <CalendarMonth?>[
      null,
      calendar('a', busyDays: [14]),
      calendar('another-owner'),
      calendar('a', month: 12),
      calendar('a', confirmedAt: now.subtract(const Duration(days: 30))),
      calendar('a', confirmedAt: now.add(const Duration(seconds: 1))),
    ]) {
      final result = review(calendars: {'a': value});
      expect(result.groups.single.candidates.single.canChoose, isFalse);
      expect(result.selectedCandidates, isEmpty);
      expect(result.unresolvedCount, 1);
    }
  });

  test(
    'withdrawn publication remains historical and cannot contribute to total',
    () {
      for (final profiles in <Map<String, PublishedProfile>>[
        {},
        {'a': published('a', visible: false)},
        {'a': published('different-owner')},
      ]) {
        final result = review(profiles: profiles);
        final candidate = result.groups.single.candidates.single;
        expect(candidate.currentContractor, isNull);
        expect(candidate.name, 'Айжан');
        expect(candidate.canChoose, isFalse);
        expect(result.estimatedFromKzt, isNull);
      }
    },
  );

  test(
    'current incompatibility and invalid prices disable chosen suppliers',
    () {
      for (final profile in [
        content(price: 250000),
        content(price: 0),
        content(price: 1000000001),
        content(city: 'Астана'),
        content(categories: ['Фотограф']),
        content(formats: ['корпоратив']),
        content(languages: ['казахский']),
        content(maxHours: 3),
      ]) {
        final result = review(
          profiles: {'a': published('a', profile: profile)},
        );
        expect(result.groups.single.candidates.single.canChoose, isFalse);
        expect(result.selectedCount, 0);
        expect(result.remainingBudgetKzt, isNull);
      }
      expect(
        review(
          profiles: {'a': published('a', profile: content(maxHours: null))},
        ).groups.single.candidates.single.canChoose,
        isTrue,
      );
    },
  );

  test(
    'missing choices and deleted selections keep partial estimates incomplete',
    () {
      final result = review(
        selections: [
          selection(),
          selection(id: 'flowers', category: 'Флорист', contractorIds: []),
        ],
      );
      expect(result.estimatedFromKzt, 100000);
      expect(result.categoryCount, 2);
      expect(result.unresolvedCategories, ['Флорист']);
      expect(result.remainingBudgetKzt, isNull);
      final deleted = review(selections: []);
      expect(deleted.categoryCount, 1);
      expect(deleted.unresolvedCount, 1);
      expect(deleted.estimatedFromKzt, isNull);
      expect(deleted.remainingBudgetKzt, isNull);
      final empty = review(
        selections: [],
        plan: const EventPlan(eventId: 'event', totalBudgetKzt: 300000),
      );
      expect(empty.estimatedFromKzt, isNull);
      expect(empty.remainingBudgetKzt, isNull);
    },
  );

  test(
    'event budget is separate from category limit and overspend is explicit',
    () {
      final result = review(plan: chosenPlan(budget: 80000));
      expect(result.selectedCount, 1);
      expect(result.estimatedFromKzt, 100000);
      expect(result.remainingBudgetKzt, -20000);
      expect(result.exceedsBudget, isTrue);
      expect(review(plan: chosenPlan(budget: null)).remainingBudgetKzt, isNull);
    },
  );

  test(
    'choice must reference candidate in its own category and exact selection',
    () {
      for (final choice in [
        const PlanChoice(selectionId: 'other-selection', contractorId: 'a'),
        const PlanChoice(selectionId: 'selection', contractorId: 'unknown'),
      ]) {
        final result = review(plan: chosenPlan().choose('Ведущий', choice));
        expect(result.selectedCandidates, isEmpty);
        expect(result.unresolvedCount, 1);
      }
      expect(
        () => review(plan: const EventPlan(eventId: 'other-event')),
        throwsArgumentError,
      );
    },
  );

  test(
    'unsupported categories and malformed saved conditions cannot be chosen',
    () {
      for (final saved in [
        selection(category: 'Неизвестная'),
        selection(hours: double.nan),
        selection(hours: 49),
        selection(budget: 1000000001),
      ]) {
        expect(
          review(
            selections: [saved],
            plan: const EventPlan(eventId: 'event'),
          ).groups.single.candidates.single.canChoose,
          isFalse,
        );
      }
    },
  );

  test(
    'brief is a draft with actual event, constraints and confirmation request',
    () {
      final draft = review().groups.single.candidates.single.draftBrief;
      for (final fact in [
        'Айжан',
        'Ведущий',
        'Наша свадьба',
        '2026-11-14',
        'Алматы',
        'свадьба',
        '200000',
        '4.0 ч',
        'русский',
        'Спокойная программа',
        'доступность',
        'состав услуг',
        'итоговую стоимость',
        'условия договора',
      ]) {
        expect(draft, contains(fact));
      }
      expect(draft, isNot(contains('300000')));
      expect(draft, isNot(contains('забронирован')));
      final complete = review(
        plan: chosenPlan().copyWith(
          completedTaskIds: planningTasks.keys.toSet(),
        ),
      );
      expect(complete.groups.single.candidates.single.draftBrief, draft);
    },
  );

  test(
    'candidate brief preserves event context and category-specific wishes',
    () {
      final draft = review(
        selections: [selection(preferences: 'Никаких конкурсов')],
      ).groups.single.candidates.single.draftBrief;
      expect(draft, contains('Пожелания: Спокойная программа'));
      expect(draft, contains('Пожелания к специалисту: Никаких конкурсов'));
      expect(draft, contains('2026-11-14'));
      expect(draft, contains('Бюджет категории: до 200000'));
    },
  );
}
