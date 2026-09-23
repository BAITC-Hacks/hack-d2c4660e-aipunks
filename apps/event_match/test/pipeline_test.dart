import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:event_match/features/matching/domain/matching_engine.dart';
import 'package:event_match/features/matching/domain/models.dart';
import 'package:event_match/features/matching/domain/normalization.dart';

void main() {
  const engine = MatchingEngine();
  final catalog = File('assets/data/catalog.jsonl')
      .readAsLinesSync()
      .where((v) => v.isNotEmpty)
      .map((s) => Contractor.fromJson(jsonDecode(s)))
      .toList();
  MatchRequest request({
    String category = 'Ведущий',
    String city = 'Алматы',
    int budget = 1000000,
    DateTime? date,
  }) => MatchRequest(
    city: city,
    category: category,
    date: date ?? DateTime(2026, 10, 6),
    format: 'свадьба',
    budget: budget,
  );
  test('all violations retained, primary is format before busy and budget', () {
    final c = Contractor(
      id: 'test',
      name: 'Test',
      city: 'Алматы',
      categories: ['Ведущий'],
      price: 2000000,
      formats: ['той'],
      languages: ['русский'],
      busyDates: ['2026-10-06'],
      description: 'Тест',
      maxHours: 2,
    );
    final e = engine.evaluate([
      c,
    ], request().copyWith(hours: 4, language: 'казахский')).single;
    expect(
      e.violations,
      Violation.values.where((v) => v != Violation.unconfirmed).toSet(),
    );
    expect(e.primary, Violation.format);
  });
  test(
    'score and normalization are deterministic; not simply cheapest first',
    () {
      final result = engine.match(catalog, request());
      expect(result.evaluations.where((e) => e.passed).length, greaterThan(4));
      final reversed = engine.match(catalog.reversed.toList(), request());
      expect(result.catalogVersion, reversed.catalogVersion);
      expect(
        result.recommendations.map((r) => r.contractor.id),
        reversed.recommendations.map((r) => r.contractor.id),
      );
      final alias = engine.match(
        catalog,
        request().copyWith(city: ' Almaty ', category: 'MC', format: 'Wedding'),
      );
      expect(
        result.recommendations.map((r) => r.contractor.id),
        alias.recommendations.map((r) => r.contractor.id),
      );
      for (final card in result.recommendations) {
        expect(card.score, inInclusiveRange(0, 1));
      }
      final a = Contractor(
        id: 'a',
        name: 'A',
        city: 'Алматы',
        categories: ['Ведущий'],
        price: 350000,
        formats: ['свадьба', 'той', 'корпоратив', 'юбилей', 'день рождения'],
        languages: ['русский'],
        busyDates: [],
        description: 'Ведущий',
        maxHours: 5,
      );
      final b = Contractor(
        id: 'b',
        name: 'B',
        city: 'Алматы',
        categories: ['Ведущий'],
        price: 700000,
        formats: ['свадьба', 'той'],
        languages: ['русский', 'казахский'],
        busyDates: [],
        description: 'Свадьбы и никах',
        maxHours: 8,
      );
      expect(
        engine.match([a, b], request()).recommendations.first.contractor.id,
        'b',
      );
    },
  );
  test(
    'real duplicate regression never hides equivalence or invents differences',
    () {
      final result = engine.match(
        catalog,
        request(
          category: 'Лайв-бэнд',
          budget: 2000000,
          date: DateTime(2026, 9, 23),
        ),
      );
      final texts = <String>{};
      for (final card in result.recommendations) {
        if (!texts.add(card.explanation)) expect(card.equivalent, isTrue);
        expect(card.explanation, isNot(contains('Приветствую всех')));
      }
    },
  );
  test(
    'expanded demo retains date changes, rare categories and both empty outcomes',
    () {
      final autumn = engine.match(catalog, request());
      final adjacent = engine.match(
        catalog,
        request(date: DateTime(2026, 10, 5)),
      );
      expect(autumn.recommendations.length, 3);
      expect(
        autumn.recommendations.any((c) => c.contractor.id.startsWith('DEMO-')),
        isTrue,
      );
      expect(
        autumn.recommendations.map((c) => c.contractor.id).toList(),
        isNot(adjacent.recommendations.map((c) => c.contractor.id).toList()),
      );
      expect(autumn.summary, contains('занят'));
      expect(adjacent.summary, contains('занят'));
      final rare = engine.match(
        catalog,
        request(category: 'Флорист', date: DateTime(2026, 10, 10)),
      );
      expect(rare.outcome, MatchOutcome.matched);
      expect(rare.recommendations.length, 1);
      expect(rare.summary, isNotEmpty);
      expect(
        engine.match(catalog, request(budget: 1)).outcome,
        MatchOutcome.noEligible,
      );
      expect(
        engine
            .match(catalog, request(city: 'Зарубежье', category: 'Флорист'))
            .outcome,
        MatchOutcome.categoryAbsent,
      );
    },
  );
  test(
    'all cities/categories, bounded explanations, exact single-change suggestions',
    () {
      var checked = 0;
      for (final city in catalog.map((c) => c.city).toSet()) {
        for (final category in catalog.expand((c) => c.categories).toSet()) {
          for (final date in [
            DateTime(2026, 9, 23),
            DateTime(2026, 10, 6),
            DateTime(2026, 11, 14),
            DateTime(2026, 12, 26),
            DateTime(2026, 12, 31),
          ]) {
            final q = request(city: city, category: category, date: date);
            final result = engine.match(catalog, q);
            checked++;
            expect(result.recommendations.length, lessThanOrEqualTo(3));
            for (final card in result.recommendations) {
              expect(card.contractor.busyDates, isNot(contains(dateKey(date))));
              expect(card.contractor.price, lessThanOrEqualTo(q.budget));
              expect(card.explanation.length, lessThanOrEqualTo(300));
              expect(
                genericPhrases.any(normalize(card.explanation).contains),
                isFalse,
              );
            }
            for (final suggestion in result.relaxations) {
              final next = suggestion.request.toJson(), before = q.toJson();
              expect(before.keys.where((k) => before[k] != next[k]).length, 1);
              final passed = engine
                  .evaluate(catalog, suggestion.request)
                  .where((e) => e.passed)
                  .map((e) => e.contractor.id)
                  .toSet();
              final previous = result.evaluations
                  .where((e) => e.passed)
                  .map((e) => e.contractor.id)
                  .toSet();
              expect(suggestion.count, passed.length);
              expect(suggestion.added, passed.difference(previous).length);
              expect(suggestion.added, greaterThan(0));
            }
          }
        }
      }
      expect(checked, greaterThan(100));
    },
  );
}
