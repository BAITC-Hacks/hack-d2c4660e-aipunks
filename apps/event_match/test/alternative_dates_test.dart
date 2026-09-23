import 'package:flutter_test/flutter_test.dart';
import 'package:event_match/features/matching/domain/alternative_dates.dart';
import 'package:event_match/features/matching/domain/models.dart';

Contractor profile(
  String id, {
  List<String> busy = const [],
  int price = 100,
  String city = 'Алматы',
  String category = 'Фотограф',
  String language = 'казахский',
  String format = 'свадьба',
  double? hours = 6,
}) => Contractor(
  id: id,
  name: id,
  city: city,
  categories: [category],
  price: price,
  formats: [format],
  languages: [language],
  busyDates: busy,
  description: id,
  maxHours: hours,
);
final query = MatchRequest(
  city: 'Алматы',
  date: DateTime(2026, 10, 10),
  format: 'свадьба',
  category: 'Фотограф',
  budget: 200,
  language: 'казахский',
  hours: 5,
);

void main() {
  test('date counts include all matches and enforce every existing filter', () {
    final profiles = [
      for (var i = 0; i < 5; i++) profile('good-$i'),
      profile('busy', busy: ['2026-10-10']),
      profile('expensive', price: 300),
      profile('wrong-city', city: 'Астана'),
      profile('wrong-category', category: 'Ведущий'),
      profile('wrong-language', language: 'русский'),
      profile('wrong-format', format: 'той'),
      profile('short', hours: 4),
    ];
    final days = alternativeDates(profiles, query);
    expect(days, hasLength(7));
    expect(days[3].date, query.date);
    expect(days[3].count, 5);
    expect(days[2].count, 6);
    expect(days[4].count, 6);
    expect(query.toJson()['date'], '2026-10-10');
  });
  test(
    'calendar edges stay inside dataset and always include selected day',
    () {
      for (final day in [DateTime(2026, 9, 23), DateTime(2026, 12, 31)]) {
        final days = alternativeDates([], query.copyWith(date: day));
        expect(days, hasLength(7));
        expect(days.any((d) => d.date == day), isTrue);
        expect(
          days.every(
            (d) =>
                !d.date.isBefore(DateTime(2026, 9, 23)) &&
                !d.date.isAfter(DateTime(2026, 12, 31)),
          ),
          isTrue,
        );
        expect(days.every((d) => d.count == 0), isTrue);
      }
    },
  );
  test('venues use calendars and null hours does not exclude a contractor', () {
    final days = alternativeDates([
      profile(
        'venue',
        category: 'Банкетный зал',
        busy: ['2026-10-10'],
        hours: null,
      ),
    ], query.copyWith(category: 'Банкетный зал', hours: 20));
    expect(days[3].count, 0);
    expect(days[2].count, 1);
  });
}
