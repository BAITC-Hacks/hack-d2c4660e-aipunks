import 'package:flutter_test/flutter_test.dart';
import 'package:event_match/features/matching/domain/models.dart';
import 'package:event_match/features/workspace/domain/workspace_models.dart';
import 'package:event_match/features/workspace/domain/workspace_repository.dart';
import 'package:event_match/features/workspace/data/workspace_catalog_repository.dart';

final now = DateTime.utc(2026, 9, 23, 10);
const content = ProfileContent(
  name: 'Подрядчик',
  city: 'Алматы',
  categories: ['Ведущий'],
  price: 100000,
  formats: ['свадьба'],
  languages: ['русский'],
  description: 'Камерные свадьбы, спокойное ведение.',
  contact: 'info@example.com',
);

class MatchingWorkspace extends WorkspaceRepository {
  List<PublishedProfile> profiles = [];
  final calendars = <String, CalendarMonth>{};
  @override
  Future<List<PublishedProfile>> listPublished() async => profiles;
  @override
  Future<CalendarMonth?> getCalendar(String uid, DateTime month) async =>
      calendars[uid];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

PublishedProfile published(String id) => PublishedProfile(
  ownerId: id,
  content: content,
  revision: 1,
  profileRevision: 3,
  published: true,
);
MatchRequest request([DateTime? date]) => MatchRequest(
  city: 'Алматы',
  date: date ?? DateTime(2026, 11, 14),
  format: 'свадьба',
  category: 'Ведущий',
  budget: 200000,
);

void main() {
  test(
    'live calendar expires exactly after 30 days and never predicts unknown months',
    () {
      final c = CalendarMonth(
        ownerId: 'supplier',
        year: 2026,
        month: 11,
        busyDays: [15],
        confirmedAt: now,
      );
      expect(
        c.availabilityOn(DateTime(2026, 11, 14), now),
        AvailabilityStatus.available,
      );
      expect(
        c.availabilityOn(DateTime(2026, 11, 15), now),
        AvailabilityStatus.busy,
      );
      expect(
        c.availabilityOn(DateTime(2026, 12, 14), now),
        AvailabilityStatus.unconfirmed,
      );
      expect(
        c.availabilityOn(
          DateTime(2026, 11, 14),
          now.add(const Duration(days: 30)),
        ),
        AvailabilityStatus.unconfirmed,
      );
      expect(
        c.availabilityOn(
          DateTime(2026, 11, 14),
          now.subtract(const Duration(seconds: 1)),
        ),
        AvailabilityStatus.unconfirmed,
      );
    },
  );
  test('malformed calendar does not become available by omission', () {
    expect(
      () => CalendarMonth.fromMap({
        'ownerId': 'supplier',
        'year': 2027,
        'month': 2,
        'busyDays': [29],
        'confirmedAt': now,
      }),
      throwsFormatException,
    );
    expect(
      () => CalendarMonth.fromMap({
        'ownerId': 'supplier',
        'year': 2026,
        'month': 13,
        'busyDays': [],
        'confirmedAt': now,
      }),
      throwsFormatException,
    );
    expect(
      CalendarMonth(
        ownerId: 'supplier',
        year: 2026,
        month: 11,
      ).availabilityOn(DateTime(2026, 11, 14), now),
      AvailabilityStatus.unconfirmed,
    );
  });
  test(
    'date policy separates dataset from live window and uses Kazakhstan day',
    () {
      expect(eventToday(DateTime.utc(2026, 9, 22, 20)), DateTime(2026, 9, 23));
      final policy = MatchDatePolicy.live(now);
      expect(policy.contains(DateTime(2027, 9, 23)), isTrue);
      expect(policy.contains(DateTime(2027, 9, 24)), isFalse);
      expect(policy.contains(DateTime(2026, 9, 22)), isFalse);
      expect(
        () => request(DateTime(2027, 1, 1)).validate(),
        throwsArgumentError,
      );
      expect(
        () => request(DateTime(2027, 1, 1)).validate(datePolicy: policy),
        returnsNormally,
      );
      expect(
        MatchRequest.fromJson(request().toJson()).toJson(),
        request().toJson(),
      );
    },
  );
  test(
    'live matching excludes busy unknown stale calendars and is deterministic',
    () async {
      final repo = MatchingWorkspace()
        ..profiles = [
          published('z'),
          published('busy'),
          published('a'),
          published('stale'),
          published('unknown'),
        ];
      for (final id in ['z', 'a']) {
        repo.calendars[id] = CalendarMonth(
          ownerId: id,
          year: 2026,
          month: 11,
          confirmedAt: now,
        );
      }
      repo.calendars['busy'] = CalendarMonth(
        ownerId: 'busy',
        year: 2026,
        month: 11,
        confirmedAt: now,
        busyDays: [14],
      );
      repo.calendars['stale'] = CalendarMonth(
        ownerId: 'stale',
        year: 2026,
        month: 11,
        confirmedAt: now.subtract(const Duration(days: 31)),
      );
      final service = LiveRecommendationService(repo, clock: () => now);
      final first = await service.recommend(request());
      final second = await service.recommend(request());
      expect(first.recommendations.map((r) => r.contractor.id), ['a', 'z']);
      expect(second.recommendations.map((r) => r.contractor.id), ['a', 'z']);
      expect(first.summary, contains('2 — доступность не подтверждена'));
      expect(first.summary, contains('1 — заняты на дату'));
      expect(
        first.recommendations.first.unchecked,
        contains('Доступность по календарю — это не бронирование'),
      );
      expect(first.recommendations.every((r) => r.contractor.isLive), isTrue);
    },
  );
  test(
    'empty live catalogue never falls back to demo; three outcomes remain distinct',
    () async {
      final repo = MatchingWorkspace();
      final service = LiveRecommendationService(repo, clock: () => now);
      expect(
        (await service.recommend(request())).outcome,
        MatchOutcome.categoryAbsent,
      );
      repo.profiles = [published('unknown')];
      expect(
        (await service.recommend(request())).outcome,
        MatchOutcome.noEligible,
      );
      repo.calendars['unknown'] = CalendarMonth(
        ownerId: 'unknown',
        year: 2026,
        month: 11,
        confirmedAt: now,
      );
      expect(
        (await service.recommend(request())).outcome,
        MatchOutcome.matched,
      );
    },
  );
  test(
    'saved public snapshots preserve provenance and business contact only',
    () {
      final c = content.toContractor('supplier');
      final snapshot = contractorSnapshot(c);
      final decoded = Contractor.fromJson(snapshot);
      expect(decoded.isLive, isTrue);
      expect(decoded.contact, 'info@example.com');
      expect(snapshot.containsKey('email'), isFalse);
      expect(snapshot.containsKey('status'), isFalse);
      final saved = SavedSelection.fromMap('selection', {
        'eventId': 'event',
        'name': 'Ведущий',
        'request': request().toJson(),
        'entries': [
          {'contractor': snapshot, 'explanation': 'Снимок объяснения'},
        ],
        'savedAt': now,
      });
      expect(saved.entries.single.explanation, 'Снимок объяснения');
      expect(saved.savedAt, now);
    },
  );
}
