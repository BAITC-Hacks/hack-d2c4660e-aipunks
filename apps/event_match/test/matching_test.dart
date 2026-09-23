import 'package:flutter_test/flutter_test.dart';
import 'package:event_match/features/matching/data/catalog_repository.dart';
import 'package:event_match/features/matching/domain/matching_engine.dart';
import 'package:event_match/features/matching/domain/models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const engine = MatchingEngine();
  late List<Contractor> catalog;
  setUp(() async {
    catalog = await AssetCatalogRepository(
      path: 'assets/data/demo.jsonl',
    ).load();
  });
  MatchRequest request({
    String city = 'Алматы',
    String category = 'Ведущий',
    int budget = 300000,
    int month = 10,
    int day = 10,
    String format = 'свадьба',
    String? language,
    double? hours,
  }) => MatchRequest(
    city: city,
    category: category,
    budget: budget,
    date: DateTime(2026, month, day),
    format: format,
    language: language,
    hours: hours,
  );

  test('top three are stable regardless of catalog order', () {
    final a = engine.match(catalog, request());
    final b = engine.match(catalog.reversed.toList(), request());
    expect(a.recommendations.length, 3);
    expect(
      a.recommendations.map((r) => r.contractor.id),
      b.recommendations.map((r) => r.contractor.id),
    );
    expect(a.recommendations.map((r) => r.explanation).toSet().length, 3);
  });
  test('busy contractor excluded on a different date', () {
    final a = engine.match(catalog, request());
    final b = engine.match(catalog, request(month: 11, day: 14));
    expect(a.recommendations.first.contractor.id, 'demo-01');
    expect(
      b.recommendations.map((r) => r.contractor.id),
      isNot(contains('demo-01')),
    );
    expect(b.summary, contains('заняты на дату'));
  });
  test('rare category and null duration', () {
    final r = engine.match(catalog, request(category: 'Флорист', hours: 12));
    expect(r.recommendations.length, 1);
    expect(r.summary, contains('всего 1'));
  });
  test('empty outcomes are distinct', () {
    expect(
      engine.match(catalog, request(category: 'Фотограф')).outcome,
      MatchOutcome.categoryAbsent,
    );
    final r = engine.match(catalog, request(budget: 1));
    expect(r.outcome, MatchOutcome.noEligible);
    expect(r.summary, contains('выше бюджета'));
  });
  test('language, format and duration are enforced', () {
    expect(
      engine
          .match(catalog, request(language: 'английский'))
          .recommendations
          .single
          .contractor
          .id,
      'demo-02',
    );
    expect(
      engine
          .match(catalog, request(format: 'конференция'))
          .recommendations
          .single
          .contractor
          .id,
      'demo-02',
    );
    expect(
      engine
          .match(catalog, request(hours: 8))
          .recommendations
          .single
          .contractor
          .id,
      'demo-02',
    );
  });
  test('venues use the same busy calendar', () {
    expect(
      engine
          .match(
            catalog,
            request(
              city: 'Астана',
              category: 'Банкетный зал',
              budget: 500000,
              month: 11,
              day: 14,
            ),
          )
          .outcome,
      MatchOutcome.noEligible,
    );
  });
}
