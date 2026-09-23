import 'package:flutter_test/flutter_test.dart';
import 'package:event_match/features/matching/domain/explanation_policy.dart';
import 'package:event_match/features/matching/domain/matching_engine.dart';
import 'package:event_match/features/matching/domain/models.dart';

void main() {
  const engine = MatchingEngine();
  Contractor profile({
    String id = 'a',
    String description = '',
    double? hours = 8,
    bool live = false,
    int price = 200000,
  }) => Contractor(
    id: id,
    name: id,
    city: 'Алматы',
    categories: ['Ведущий'],
    price: price,
    formats: ['свадьба'],
    languages: ['русский'],
    busyDates: [],
    description: description,
    maxHours: hours,
    isLive: live,
  );
  final query = MatchRequest(
    city: 'Алматы',
    date: DateTime(2026, 10, 6),
    format: 'свадьба',
    category: 'Ведущий',
    budget: 300000,
    hours: 6,
    language: 'русский',
  );

  test('price from stays preliminary, duration relates to requested hours', () {
    final card = engine.match([profile()], query).recommendations.single;
    expect(card.explanation, contains('Для ваших 6 ч'));
    expect(card.explanation, contains('до 8 ч'));
    expect(
      card.explanation,
      contains('Цена от 200000 ₸ при вашем лимите 300000 ₸'),
    );
    expect(card.explanation, contains('итоговую стоимость уточните'));
    expect(card.explanation, isNot(contains('запас')));
    expect(card.explanationOptions, hasLength(2));
    for (final text in card.explanationOptions) {
      expect(RegExp(r'[.!?](?:\s|$)').allMatches(text).length, 2);
      expect(text.length, lessThanOrEqualTo(300));
    }
  });

  test(
    'complete source sentence preserves a negation outside a keyword window',
    () {
      const description =
          'Мы не проводим никакие активности из стандартных программ, включая конкурсы с переодеванием. Свадьбы ведём спокойно.';
      final quotes = relevantExcerpts(description, ['конкурс']);
      expect(quotes.single, startsWith('Мы не проводим'));
      expect(quotes.single, contains('включая конкурсы с переодеванием'));
      expect(
        relevantExcerpts('${'Длинное начало ' * 20}без конкурсов.', [
          'конкурс',
        ]),
        isEmpty,
      );
    },
  );

  test(
    'demo null hours means not tied to presence; live null remains unknown',
    () {
      final demo = engine
          .match([profile(hours: null)], query)
          .recommendations
          .single;
      expect(demo.explanation, contains('не привязана к часам присутствия'));
      expect(demo.unchecked, isNot(contains('Длительность не подтверждена')));
      final live = engine
          .match(
            [profile(hours: null, live: true)],
            query,
            availability: {'a': AvailabilityStatus.available},
            datePolicy: MatchDatePolicy.live(DateTime.utc(2026, 9, 23)),
          )
          .recommendations
          .single;
      expect(live.explanation, isNot(contains('не привязана')));
      expect(live.unchecked, contains('Длительность не подтверждена'));
      expect(RegExp(r'[.!?](?:\s|$)').allMatches(live.explanation).length, 2);
    },
  );

  test('identical evidence is disclosed instead of invented advantages', () {
    final cards = engine.match([
      profile(),
      profile(id: 'b'),
    ], query).recommendations;
    expect(cards.every((c) => c.equivalent), isTrue);
    expect(cards.map((c) => c.explanation).toSet(), hasLength(1));
    expect(
      cards.every(
        (c) =>
            c.unchecked.any((s) => s.contains('нет подтверждённого отличия')),
      ),
      isTrue,
    );
  });

  test(
    'date remains visible in result summary and price is not guaranteed',
    () {
      final result = engine.match([profile()], query);
      expect(result.summary, contains('2026-10-06'));
      expect(result.summary, contains('стартовая цена'));
      expect(result.summary, isNot(contains('укладываются в бюджет')));
    },
  );
}
