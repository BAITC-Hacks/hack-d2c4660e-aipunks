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
import 'package:event_match/features/matching/domain/models.dart';
import 'package:event_match/features/matching/presentation/widgets/contractor_details.dart';
import 'package:event_match/features/assistant/presentation/widgets/assistant_recommendations.dart';

const _profile = Contractor(
  id: 'explanation-test',
  name: 'Фотограф семейных событий',
  city: 'Астана',
  categories: ['Фотограф'],
  price: 150000,
  formats: ['свадьба'],
  languages: ['русский'],
  busyDates: [],
  description: 'Снимает живые эмоции. Помогает парам освоиться перед камерой.',
  maxHours: null,
  isLive: true,
);

void main() {
  testWidgets(
    'missing hours retain demo meaning and stay unknown for live profiles',
    (tester) async {
      final demo = Contractor(
        id: 'demo-hours',
        name: _profile.name,
        city: _profile.city,
        categories: _profile.categories,
        price: _profile.price,
        formats: _profile.formats,
        languages: _profile.languages,
        busyDates: const [],
        description: _profile.description,
        maxHours: null,
        isLive: false,
      );
      for (final profile in [demo, _profile]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: SingleChildScrollView(
                child: ContractorCard(contractor: profile),
              ),
            ),
          ),
        );
        final label = profile.isLive
            ? 'Длительность не указана'
            : 'Без привязки к часам присутствия';
        final other = profile.isLive
            ? 'Без привязки к часам присутствия'
            : 'Длительность не указана';
        expect(find.text(label), findsOneWidget);
        expect(find.text(other), findsNothing);
        final button = find.byKey(ValueKey('profile-${profile.id}'));
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pumpAndSettle();
        final panel = find.byType(ContractorDetails);
        expect(
          find.descendant(of: panel, matching: find.text(label)),
          findsOneWidget,
        );
        expect(
          find.descendant(of: panel, matching: find.text(other)),
          findsNothing,
        );
        await tester.tap(find.byTooltip('Закрыть профиль'));
        await tester.pumpAndSettle();
      }
    },
  );

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
      expect(find.text('Об услугах'), findsNWidgets(3));
      expect(find.text('Сводка ИИ · GPT'), findsNWidgets(3));
      expect(find.text('Почему в подборке'), findsNothing);
      expect(
        tester.getSize(find.byType(ContractorCard).first).width,
        greaterThan(450),
      );
      final toggle = find.byType(SwitchListTile);
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(find.text('Сводка ИИ · GPT'), findsNothing);
      expect(find.text('Об услугах'), findsNWidgets(3));
      expect(find.text('Почему в подборке'), findsNothing);
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
                source: 'llm',
                text:
                    'Проводит камерные свадьбы на русском языке. Программа рассчитана на небольшие группы.',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Почему в подборке'), findsOneWidget);
      expect(find.text('Формулировка выбрана ИИ · GPT'), findsOneWidget);
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
    expect(find.text('Почему в подборке'), findsOneWidget);
    expect(find.textContaining('GPT'), findsNothing);
    expect(find.byIcon(Icons.auto_awesome_outlined), findsNothing);
  });

  testWidgets('legacy generated flag alone does not claim model authorship', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AiExplanation(
            text: 'Подходит по формату события.',
            generated: true,
          ),
        ),
      ),
    );
    expect(find.text('Почему в подборке'), findsOneWidget);
    expect(find.textContaining('GPT'), findsNothing);
    expect(find.byIcon(Icons.auto_awesome_outlined), findsNothing);
  });

  testWidgets(
    'unknown catalog summary source stays neutral in card and profile',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(
            body: SingleChildScrollView(
              child: ContractorCard(
                contractor: _profile,
                aiSummary: 'Снимает свадьбы и помогает перед камерой.',
              ),
            ),
          ),
        ),
      );
      expect(find.text('Об услугах'), findsOneWidget);
      expect(find.text('Почему в подборке'), findsNothing);
      expect(find.textContaining('GPT'), findsNothing);
      expect(find.text('Длительность не указана'), findsOneWidget);
      final details = find.byKey(const ValueKey('profile-explanation-test'));
      await tester.ensureVisible(details);
      await tester.tap(details);
      await tester.pumpAndSettle();
      final panel = find.byType(ContractorDetails);
      expect(
        find.descendant(of: panel, matching: find.text('Об услугах')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: panel, matching: find.text('Почему в подборке')),
        findsNothing,
      );
      expect(
        find.descendant(of: panel, matching: find.textContaining('GPT')),
        findsNothing,
      );
    },
  );

  for (final source in ['template', 'llm']) {
    testWidgets(
      'matching card and profile explain fit with separate limitations for $source',
      (tester) async {
        const explanation =
            'Помогает парам освоиться перед камерой — это отвечает вашему пожеланию снимать без позирования.';
        final recommendation = Recommendation(
          _profile,
          explanation,
          source: source,
          unchecked: const ['Итоговая стоимость', 'Длительность не указана'],
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: SingleChildScrollView(
                child: ContractorCard(
                  contractor: _profile,
                  recommendation: recommendation,
                ),
              ),
            ),
          ),
        );
        expect(find.text('Почему в подборке'), findsOneWidget);
        expect(find.text('Об услугах'), findsNothing);
        expect(find.text(explanation), findsOneWidget);
        expect(find.text('Что уточнить'), findsOneWidget);
        expect(find.text('• Итоговая стоимость'), findsOneWidget);
        expect(
          find.textContaining('GPT'),
          source == 'llm' ? findsOneWidget : findsNothing,
        );
        expect(
          find.ancestor(
            of: find.text('Почему в подборке'),
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Semantics && widget.properties.header == true,
            ),
          ),
          findsOneWidget,
        );
        final details = find.byKey(const ValueKey('profile-explanation-test'));
        await tester.ensureVisible(details);
        await tester.tap(details);
        await tester.pumpAndSettle();
        final panel = find.byType(ContractorDetails);
        expect(
          find.descendant(of: panel, matching: find.text('Почему в подборке')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: panel, matching: find.text('Что уточнить')),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: panel,
            matching: find.text('• Итоговая стоимость'),
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final width in [375.0, 768.0, 1440.0]) {
    testWidgets('matching explanation and profile fit $width with expanded text', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      const explanation =
          'Помогает парам освоиться перед камерой, поэтому подходит для съёмки без позирования. В профиле указан документальный подход к свадебным фотографиям.';
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(
            body: SingleChildScrollView(
              padding: EdgeInsets.all(16),
              child: ContractorCard(
                contractor: _profile,
                recommendation: Recommendation(
                  _profile,
                  explanation,
                  source: 'llm',
                  unchecked: [
                    'Итоговая стоимость зависит от согласованного состава услуг',
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Почему в подборке'), findsOneWidget);
      expect(find.text('Что уточнить'), findsOneWidget);
      expect(
        tester.widget<AiExplanation>(find.byType(AiExplanation)).maxLines,
        isNull,
      );
      expect(tester.takeException(), isNull);
      final details = find.byKey(const ValueKey('profile-explanation-test'));
      await tester.ensureVisible(details);
      await tester.tap(details);
      await tester.pumpAndSettle();
      final panel = find.byType(ContractorDetails);
      expect(
        find.descendant(of: panel, matching: find.text('Почему в подборке')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: panel, matching: find.text('Что уточнить')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'assistant fit and limitations remain readable at $width with large text',
      (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        const explanation =
            'Помогает парам освоиться перед камерой. Снимает живые эмоции, как вы и просили.';
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: Scaffold(
                body: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: AssistantRecommendations(
                    recommendations: const [
                      Recommendation(_profile, explanation),
                    ],
                    unverified: const {
                      'explanation-test': [
                        'Дата не проверена',
                        'Длительность не подтверждена',
                        'Дата не проверена',
                      ],
                    },
                    preliminary: true,
                    onReject: (_, _) async {},
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Почему в подборке'), findsOneWidget);
        expect(find.text('Что уточнить'), findsOneWidget);
        expect(find.text('• Дата не проверена'), findsOneWidget);
        expect(find.text(explanation), findsOneWidget);
        expect(find.textContaining('GPT'), findsNothing);
        expect(find.textContaining('%'), findsNothing);
        expect(tester.takeException(), isNull);
        final details = find.byKey(
          const ValueKey('profile-explanation-test'),
        );
        await tester.ensureVisible(details);
        await tester.tap(details);
        await tester.pumpAndSettle();
        final panel = find.byType(ContractorDetails);
        expect(
          find.descendant(of: panel, matching: find.text('Что уточнить')),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: panel,
            matching: find.text('• Дата не проверена'),
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
