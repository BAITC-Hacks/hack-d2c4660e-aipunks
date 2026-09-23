import 'dart:convert';
import 'package:http/http.dart' as http;
import '../domain/models.dart';
import '../domain/catalog_version.dart';
import '../domain/recommendation_service.dart';
import 'local_recommendation_service.dart';
import 'catalog_repository.dart';

class ApiRecommendationService implements RecommendationService {
  ApiRecommendationService(
    CatalogRepository repository, {
    required this.baseUrl,
    this.token = '',
    this.aiEnabled = true,
    http.Client? client,
  }) : local = LocalRecommendationService(repository),
       client = client ?? http.Client();
  final LocalRecommendationService local;
  final String baseUrl, token;
  final http.Client client;
  bool aiEnabled;
  final Map<String, String> _summaries = {};

  /// Only IDs/version go to the server; profile evidence comes from SQLite.
  Future<Map<String, String>> summarize(
    List<Contractor> profiles,
    List<Contractor> catalog,
  ) async {
    if (!aiEnabled || baseUrl.isEmpty) return {};
    final version = catalogVersion(catalog);
    final missing = profiles
        .where((c) => !_summaries.containsKey('$version:${c.id}'))
        .take(3)
        .toList();
    if (missing.isNotEmpty) {
      try {
        final response = await client
            .post(
              Uri.parse('$baseUrl/v1/summaries'),
              headers: {
                'Content-Type': 'application/json',
                if (token.isNotEmpty) 'X-Local-Token': token,
              },
              body: jsonEncode({
                'catalog_version': version,
                'ids': missing.map((c) => c.id).toList(),
              }),
            )
            .timeout(const Duration(seconds: 9));
        if (response.statusCode == 200 && response.body.length < 20000) {
          final body = jsonDecode(response.body) as Map<String, dynamic>;
          final cards = body['cards'] as List;
          if (body['catalog_version'] == version &&
              cards.length == missing.length &&
              List.generate(
                cards.length,
                (i) => cards[i]['id'] == missing[i].id,
              ).every((v) => v)) {
            for (var i = 0; i < cards.length; i++) {
              final text = cards[i]['explanation'];
              if (cards[i]['source'] == 'llm' &&
                  text is String &&
                  text.length >= 30 &&
                  text.length <= 300) {
                _summaries['$version:${missing[i].id}'] = text;
              }
            }
          }
        }
      } catch (_) {
        /* The original description stays available offline. */
      }
    }
    return {
      for (final c in profiles)
        if (_summaries.containsKey('$version:${c.id}'))
          c.id: _summaries['$version:${c.id}']!,
    };
  }

  @override
  bool get supportsPreferences => true;

  @override
  Future<MatchResult> recommend(MatchRequest request) async {
    final result = await local.recommend(request);
    if (!aiEnabled || baseUrl.isEmpty || result.recommendations.isEmpty) {
      return result;
    }
    MatchResult fallback(String text) => result.withExplanations(
      result.recommendations,
      '${result.notice} $text'.trim(),
    );
    try {
      final response = await client
          .post(
            Uri.parse('$baseUrl/v1/explanations'),
            headers: {
              'Content-Type': 'application/json',
              if (token.isNotEmpty) 'X-Local-Token': token,
            },
            body: jsonEncode({
              'request': request.normalized().toJson(),
              'catalog_version': result.catalogVersion,
              'algorithm_version': result.algorithmVersion,
              'ids': result.recommendations
                  .map((r) => r.contractor.id)
                  .toList(),
            }),
          )
          .timeout(const Duration(milliseconds: 8000));
      if (response.statusCode != 200 || response.body.length > 20000) {
        return fallback('AI-сервис недоступен: показаны локальные объяснения.');
      }
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final cards = body['cards'] as List;
      if (body['catalog_version'] != result.catalogVersion ||
          body['algorithm_version'] != result.algorithmVersion ||
          cards.length != result.recommendations.length) {
        throw const FormatException('Mismatched result');
      }
      final recommendations = <Recommendation>[];
      for (var i = 0; i < cards.length; i++) {
        final original = result.recommendations[i];
        final card = cards[i] as Map<String, dynamic>;
        if (card['id'] != original.contractor.id) {
          throw const FormatException('Changed order');
        }
        final text = card['explanation'];
        if (text is String &&
            original.explanationOptions.contains(text) &&
            card['source'] == 'llm' &&
            !original.equivalent) {
          recommendations.add(original.withText(text, 'llm'));
        } else {
          recommendations.add(original);
        }
      }
      final generated = recommendations.where((c) => c.source == 'llm').length;
      final reason = switch (body['reason']) {
        'missing-key' => 'На сервере не задан ключ GPT',
        'daily-limit' => 'Достигнут дневной лимит AI-запросов',
        'verified-facts' => 'Показаны проверенные факты профиля',
        _ => 'AI-текст не получен или не прошёл проверку',
      };
      return result.withExplanations(
        recommendations,
        [
          result.notice,
          if (generated == 0)
            '$reason: показаны локальные объяснения.'
          else
            '${body['cached'] == true ? 'Из кэша: ' : ''}GPT: $generated из ${cards.length} объяснений; остальные — локальные.',
        ].where((s) => s.isNotEmpty).join(' '),
      );
    } catch (_) {
      return fallback('Нет ответа AI-сервиса: подбор выполнен локально.');
    }
  }
}
