import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:event_match/features/matching/data/api_recommendation_service.dart';
import 'package:event_match/features/matching/data/local_recommendation_service.dart';
import 'package:event_match/features/matching/data/catalog_repository.dart';
import 'package:event_match/features/matching/domain/models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'catalog summaries preserve IDs, cache successes and honor AI toggle',
    () async {
      final repo = AssetCatalogRepository();
      final catalog = await repo.load();
      final profiles = catalog.take(3).toList();
      var calls = 0;
      final service = ApiRecommendationService(
        repo,
        baseUrl: 'http://test',
        client: MockClient((request) async {
          calls++;
          expect(request.url.path, '/v1/summaries');
          final input = jsonDecode(request.body) as Map<String, dynamic>;
          expect(input.containsKey('description'), isFalse);
          return http.Response(
            jsonEncode({
              'catalog_version': input['catalog_version'],
              'cards': [
                for (final id in input['ids'])
                  {
                    'id': id,
                    'explanation':
                        'Краткая сводка услуг по данным профиля. Условия можно уточнить в описании.',
                    'source': 'llm',
                  },
              ],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      expect((await service.summarize(profiles, catalog)).length, 3);
      expect((await service.summarize(profiles, catalog)).length, 3);
      expect(calls, 1);
      service.aiEnabled = false;
      expect(await service.summarize(profiles, catalog), isEmpty);
      expect(calls, 1);
    },
  );
  final request = MatchRequest(
    city: 'Алматы',
    category: 'Ведущий',
    date: DateTime(2026, 10, 6),
    format: 'свадьба',
    budget: 1000000,
  );
  test(
    'network failure returns same offline ranking and visible notice',
    () async {
      final repo = AssetCatalogRepository();
      final local = await LocalRecommendationService(repo).recommend(request);
      final service = ApiRecommendationService(
        repo,
        baseUrl: 'http://test',
        client: MockClient((_) async => throw const FormatException('offline')),
      );
      final actual = await service.recommend(request);
      expect(
        actual.recommendations.map((c) => c.contractor.id),
        local.recommendations.map((c) => c.contractor.id),
      );
      expect(actual.notice, contains('локально'));
    },
  );
  test(
    'obvious unsupported promise is rejected; toggle makes zero HTTP calls',
    () async {
      final repo = AssetCatalogRepository();
      var calls = 0;
      final local = await LocalRecommendationService(repo).recommend(request);
      final service = ApiRecommendationService(
        repo,
        baseUrl: 'http://test',
        client: MockClient((_) async {
          calls++;
          return http.Response(
            jsonEncode({
              'catalog_version': local.catalogVersion,
              'algorithm_version': local.algorithmVersion,
              'reason': 'ok',
              'cards': local.recommendations
                  .map(
                    (c) => {
                      'id': c.contractor.id,
                      'explanation': 'Гарантируем успех за 1 ₸',
                      'source': 'llm',
                    },
                  )
                  .toList(),
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      final actual = await service.recommend(request);
      expect(
        actual.recommendations.map((c) => c.explanation),
        local.recommendations.map((c) => c.explanation),
      );
      expect(
        actual.recommendations.every((c) => c.source == 'template'),
        isTrue,
      );
      service.aiEnabled = false;
      await service.recommend(request);
      expect(calls, 1);
    },
  );
  test('validated GPT is accepted but reordered cards are rejected', () async {
    final repo = AssetCatalogRepository();
    final local = await LocalRecommendationService(repo).recommend(request);
    var reverse = false;
    final service = ApiRecommendationService(
      repo,
      baseUrl: 'http://test',
      client: MockClient((_) async {
        final cards = local.recommendations
            .map(
              (c) => {
                'id': c.contractor.id,
                'explanation': c.explanation.replaceFirst(
                  'Цена от',
                  'Стоимость от',
                ),
                'source': 'llm',
              },
            )
            .toList();
        return http.Response(
          jsonEncode({
            'catalog_version': local.catalogVersion,
            'algorithm_version': local.algorithmVersion,
            'reason': 'ok',
            'cached': true,
            'cards': reverse ? cards.reversed.toList() : cards,
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    final accepted = await service.recommend(request);
    expect(accepted.recommendations.every((c) => c.source == 'llm'), isTrue);
    expect(accepted.notice, contains('Из кэша'));
    reverse = true;
    final rejected = await service.recommend(request);
    expect(
      rejected.recommendations.every((c) => c.source == 'template'),
      isTrue,
    );
    expect(
      rejected.recommendations.map((c) => c.contractor.id),
      local.recommendations.map((c) => c.contractor.id),
    );
  });
}
