import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:event_match/app/app.dart';
import 'package:event_match/features/matching/data/catalog_repository.dart';
import 'package:event_match/features/matching/data/api_recommendation_service.dart';
import 'package:event_match/features/matching/presentation/widgets/contractor_card.dart';
import 'widget_test.dart' show MemoryCatalog;
import 'package:flutter_test/flutter_test.dart';
import 'package:event_match/app/app_theme.dart';
import 'package:event_match/features/matching/presentation/widgets/ai_explanation.dart';

void main() {
  testWidgets(
    'catalog renders generated summaries and wide cards; toggle hides AI',
    (tester) async {
      final catalog = await tester.runAsync(
        () => AssetCatalogRepository().load(),
      );
      final repo = MemoryCatalog(catalog!.take(3).toList());
      var calls = 0;
      final service = ApiRecommendationService(
        repo,
        baseUrl: 'http://test',
        client: MockClient((request) async {
          calls++;
          final input = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'catalog_version': input['catalog_version'],
              'cards': [
                for (final id in input['ids'])
                  {
                    'id': id,
                    'explanation':
                        'Краткая тестовая сводка услуг из каталога. Подробности остаются в исходном описании.',
                    'source': 'llm',
                  },
              ],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      tester.view.physicalSize = const Size(1694, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        EventMatchApp(repository: repo, recommendationService: service),
      );
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(find.text('Объяснение от ИИ'), findsNWidgets(3));
      expect(
        tester.getSize(find.byType(ContractorCard).first).width,
        greaterThan(450),
      );
      final toggle = find.byType(SwitchListTile);
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(find.text('Объяснение от ИИ'), findsNothing);
      expect(calls, 1);
      expect(tester.takeException(), isNull);
    },
  );
  for (final reduced in [false, true]) {
    testWidgets('AI badge wraps at 320px, finite motion, reduced=$reduced', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: MediaQuery(
            data: MediaQueryData(
              disableAnimations: reduced,
              textScaler: const TextScaler.linear(2),
            ),
            child: const Scaffold(
              body: AiExplanation(
                text:
                    'Проводит камерные свадьбы на русском языке. Программа рассчитана на небольшие группы.',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Объяснение от ИИ'), findsOneWidget);
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('fallback never claims AI authorship', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AiExplanation(text: 'Факты из каталога.', generated: false),
        ),
      ),
    );
    expect(find.text('Объяснение от ИИ'), findsNothing);
    expect(find.byIcon(Icons.auto_awesome_outlined), findsNothing);
  });
}
