import 'dart:io';
import 'dart:ui' as ui;
import 'package:event_match/app/app.dart';
import 'package:event_match/app/communication_scope.dart';
import 'package:event_match/features/assistant/domain/assistant_models.dart';
import 'package:event_match/features/assistant/domain/assistant_service.dart';
import 'package:event_match/features/assistant/presentation/assistant_screen.dart';
import 'package:event_match/features/matching/domain/models.dart';
import 'package:event_match/features/matching/domain/recommendation_service.dart';
import 'package:event_match/features/matching/presentation/widgets/contractor_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'favorites_test.dart' show FailingRepository;
import 'selection_comparison_test.dart' show comparisonFixtures;
import 'widget_test.dart' show MemoryCatalog;

class _SelectedService implements AssistantService {
  int calls = 0;
  final selected = [
    comparisonFixtures[2],
    comparisonFixtures[0],
    comparisonFixtures[1],
  ];
  @override
  bool get supportsFreeText => true;
  @override
  Future<AssistantTurn> send({
    required AssistantBrief brief,
    String? message,
    AssistantAction? action,
    List<AssistantMessage> history = const [],
  }) async {
    calls++;
    const summary =
        'Проходят по указанным условиям 16 из 56; показано 3. Исключены: 40 — заняты на дату.';
    return AssistantTurn(
      brief: const AssistantBrief(
        city: 'Алматы',
        category: 'Фотограф',
        eventFormat: 'свадьба',
        date: '2026-10-10',
        budgetKzt: 400000,
      ),
      message: summary,
      result: AssistantResult(
        outcome: MatchOutcome.matched,
        summary: summary,
        recommendations: [
          for (final r in selected)
            AssistantRecommendation(
              contractor: r.contractor,
              explanation: r.explanation,
            ),
        ],
      ),
      actions: const [
        AssistantAction(
          id: 'budget',
          label: 'Изменить бюджет',
          type: 'pick_budget',
          field: 'budget_kzt',
        ),
      ],
    );
  }
}

class _NoRerank implements RecommendationService {
  int calls = 0;
  @override
  bool get supportsPreferences => false;
  @override
  Future<MatchResult> recommend(MatchRequest request) async {
    calls++;
    return MatchResult(
      MatchOutcome.matched,
      comparisonFixtures,
      'Подходят 3 из 3; показано 3.',
    );
  }
}

void main() {
  for (final size in [const Size(1440, 1100), const Size(375, 812)]) {
    testWidgets(
      'assistant result is shown on main page without re-ranking at $size',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        const capture = bool.fromEnvironment('VISUAL_PREVIEW');
        if (capture) {
          await tester.runAsync(() async {
            for (final font in {
              'Manrope': 'assets/fonts/Manrope.ttf',
              'NotoSans': 'assets/fonts/NotoSans.ttf',
              'CormorantGaramond': 'assets/fonts/CormorantGaramond-Italic.ttf',
              'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
            }.entries) {
              await (FontLoader(
                font.key,
              )..addFont(rootBundle.load(font.value))).load();
            }
          });
        }
        final boundaryKey = GlobalKey();
        final service = _SelectedService();
        final local = _NoRerank();
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundaryKey,
            child: EventMatchApp(
              repository: MemoryCatalog(
                comparisonFixtures.map((r) => r.contractor).toList(),
              ),
              favoritesRepository: FailingRepository(),
              recommendationService: local,
              assistantService: service,
            ),
          ),
        );
        await tester.pumpAndSettle();
        final context = tester.element(find.byType(ContractorCard).first);
        CommunicationScope.maybeOf(context)!.openAssistant(context);
        await tester.pumpAndSettle();
        final controller = tester
            .widget<AssistantScreen>(find.byType(AssistantScreen))
            .controller;
        await tester.enterText(
          find.byKey(const Key('assistant-input')),
          'Нужен фотограф на свадьбу в Алматы 10 октября до 400 тысяч',
        );
        await tester.pump();
        await tester.tap(find.byKey(const Key('assistant-send')));
        await tester.pumpAndSettle();
        expect(service.calls, 1);
        expect(local.calls, 0);
        expect(
          controller.turn!.result!.recommendations.map((r) => r.contractor.id),
          service.selected.map((r) => r.contractor.id),
        );
        if (size.width >= 1400) {
          expect(
            find.byKey(const Key('recommendation-comparison')),
            findsOneWidget,
          );
          for (var i = 0; i < service.selected.length; i++) {
            final header = find.byKey(
              ValueKey(
                'comparison-profile-${service.selected[i].contractor.id}',
              ),
            );
            expect(
              find.descendant(
                of: header,
                matching: find.text('Вариант ${i + 1}'),
              ),
              findsOneWidget,
            );
          }
          final first = tester.getRect(
            find.byKey(
              ValueKey(
                'comparison-profile-${service.selected.first.contractor.id}',
              ),
            ),
          );
          final third = tester.getRect(
            find.byKey(
              ValueKey(
                'comparison-profile-${service.selected.last.contractor.id}',
              ),
            ),
          );
          expect(first.top, third.top);
          expect(
            third.right,
            lessThan(
              tester.getRect(find.byKey(const Key('assistant-panel'))).left,
            ),
          );
        }
        expect(find.textContaining('16 из 56'), findsNothing);
        if (capture) {
          await tester.runAsync(() async {
            final boundary =
                boundaryKey.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final image = await boundary.toImage(pixelRatio: 1);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final file = File(
              'build/previews/selection-chat-${size.width.toInt()}.png',
            );
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.tap(find.byTooltip('Закрыть помощника'));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('recommendation-comparison')),
          findsOneWidget,
        );
        expect(
          find.text('3 лучших кандидата под ваши условия'),
          findsOneWidget,
        );
        for (final r in service.selected) {
          expect(find.text(r.explanation), findsOneWidget);
        }
        final filter = find.byKey(const Key('open-filters'));
        await tester.ensureVisible(filter);
        await tester.pumpAndSettle();
        await tester.tap(filter);
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<TextFormField>(find.byKey(const Key('budget-input')))
              .controller!
              .text,
          '400000',
        );
        final apply = find.byKey(const Key('apply-filters'));
        await tester.ensureVisible(apply);
        await tester.pumpAndSettle();
        await tester.tap(apply);
        await tester.pumpAndSettle();
        expect(local.calls, 1);
        expect(service.calls, 1);
        expect(controller.messages.length, 2);
        controller.reset();
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('selection-title')),
          findsOneWidget,
        ); // Manual result is retained.
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
