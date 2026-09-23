import 'dart:convert';
import 'dart:io';
import 'package:event_match/features/matching/domain/matching_engine.dart';
import 'package:event_match/features/matching/domain/models.dart';

void main() {
  final catalog = File('assets/data/catalog.jsonl')
      .readAsLinesSync()
      .where((s) => s.isNotEmpty)
      .map((s) => Contractor.fromJson(jsonDecode(s)))
      .toList();
  const engine = MatchingEngine();
  for (final sample in [
    ('Алматы', 'Ведущий', '2026-10-06', 1000000),
    ('Алматы', 'Ведущий', '2026-10-05', 1000000),
    ('Алматы', 'Флорист', '2026-10-10', 1000000),
    ('Алматы', 'Ведущий', '2026-12-26', 1),
    ('Зарубежье', 'Флорист', '2026-10-10', 1000000),
    ('Алматы', 'Лайв-бэнд', '2026-09-23', 2000000),
  ]) {
    final clock = Stopwatch()..start();
    final r = engine.match(
      catalog,
      MatchRequest(
        city: sample.$1,
        category: sample.$2,
        date: DateTime.parse(sample.$3),
        budget: sample.$4,
        format: 'свадьба',
      ),
    );
    clock.stop();
    stdout.writeln(
      jsonEncode({
        'query': sample.toString(),
        'outcome': r.outcome.name,
        'eligible': r.evaluations.where((e) => e.passed).length,
        'ms': clock.elapsedMilliseconds,
        'cards': r.recommendations
            .map(
              (c) => {
                'id': c.contractor.id,
                'name': c.contractor.name,
                'score': c.score,
                'text': c.explanation,
                'equivalent': c.equivalent,
              },
            )
            .toList(),
        'suggestions': r.relaxations.map((s) => s.label).toList(),
      }),
    );
  }
}
