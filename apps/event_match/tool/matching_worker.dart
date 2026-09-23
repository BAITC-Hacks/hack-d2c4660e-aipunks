// Shared pure-Dart engine for server-side verification. No Flutter runtime.
import 'dart:convert';
import 'dart:io';
import 'package:event_match/features/matching/domain/matching_engine.dart';
import 'package:event_match/features/matching/domain/models.dart';

Future<void> main() async {
  stdout.writeln(jsonEncode({'ready': true}));
  await for (final line
      in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
    Object? id;
    try {
      final input = jsonDecode(line) as Map<String, dynamic>;
      id = input['id'];
      final q = input['request'] as Map<String, dynamic>;
      final request = MatchRequest(
        city: q['city'] as String,
        date: DateTime.parse(q['date'] as String),
        category: q['category'] as String,
        format: q['event_format'] as String,
        budget: q['budget_kzt'] as int,
        hours: (q['hours'] as num?)?.toDouble(),
        language: q['language'] as String?,
        preferences: q['preferences'] as String? ?? '',
      ).normalized();
      final catalog = (input['catalog'] as List)
          .map((p) => Contractor.fromJson(p as Map<String, dynamic>))
          .toList();
      final result = const MatchingEngine().match(catalog, request);
      stdout.writeln(
        jsonEncode({
          'id': id,
          'result': {
            'request': request.toJson(),
            'catalog_version': result.catalogVersion,
            'algorithm_version': result.algorithmVersion,
            'outcome': result.outcome.name,
            'summary': result.summary,
            'eligible_count': result.evaluations.where((e) => e.passed).length,
            'cards': result.recommendations
                .map(
                  (r) => {
                    'id': r.contractor.id,
                    'main_fact': r.mainFact,
                    'fit_fact': r.fitFact,
                    'template': r.explanation,
                    'explanation_options': r.explanationOptions,
                    'unchecked': r.unchecked,
                    'equivalent': r.equivalent,
                    'score': r.score,
                    'features': r.features,
                  },
                )
                .toList(),
            'relaxations': result.relaxations
                .map(
                  (s) => {
                    'field': s.field,
                    'count': s.count,
                    'added': s.added,
                    'label': s.label,
                    'request': s.request.toJson(),
                  },
                )
                .toList(),
          },
        }),
      );
    } catch (_) {
      stdout.writeln(jsonEncode({'id': id, 'error': 'invalid-request'}));
    }
  }
}
