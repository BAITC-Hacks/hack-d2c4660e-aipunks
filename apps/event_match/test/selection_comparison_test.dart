import 'package:event_match/app/app_theme.dart';
import 'package:event_match/features/matching/domain/models.dart';
import 'package:event_match/features/matching/presentation/selection_presentation.dart';
import 'package:event_match/features/matching/presentation/widgets/recommendation_comparison.dart';
import 'package:event_match/features/matching/presentation/widgets/selection_overview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final comparisonFixtures = [
  for (var i = 0; i < 3; i++)
    Recommendation(
      Contractor(
        id: 'choice-$i',
        name: ['Анна — фотограф', 'Екатерина с длинным именем', 'Алексей'][i],
        city: 'Алматы',
        categories: const ['Фотограф'],
        price: [150000, 210000, 270000][i],
        formats: i == 1
            ? const ['свадьба', 'корпоратив', 'юбилей', 'день рождения']
            : const ['свадьба'],
        languages: i == 2
            ? const ['русский', 'казахский', 'английский']
            : const ['русский'],
        busyDates: const [],
        description: 'Исходное описание $i.',
        maxHours: i == 2 ? null : (6 + i * 2).toDouble(),
      ),
      'Текст объяснения коллеги $i. Сохраняется без изменений.',
    ),
];

const _summary =
    'Проходят по указанным условиям 16 из 56; показано 3. Исключены: 40 — заняты на дату.';

void main() {
  test('headline is count-aware and leaves original summary intact', () {
    const p = SelectionPresentation(
      outcome: MatchOutcome.matched,
      count: 3,
      summary: _summary,
    );
    expect(p.title, '3 лучших кандидата под ваши условия');
    expect(p.visibleNote, isNot(contains('16')));
    expect(p.summary, _summary);
    expect(
      p.presentMessage('$_summary\n\nНа какую дату?'),
      contains('На какую дату?'),
    );
    expect(
      p.presentMessage('$_summary\n\nНа какую дату?'),
      isNot(contains('16 из 56')),
    );
    for (final n in [1, 2]) {
      final fewer = SelectionPresentation(
        outcome: MatchOutcome.matched,
        count: n,
        summary:
            'Проходят по указанным условиям $n из 10; показано $n. Исключены: 8 — заняты на дату.',
      );
      expect(
        fewer.title,
        n == 1 ? 'Подобрали 1 вариант' : 'Подобрали 2 варианта',
      );
      expect(fewer.visibleNote, contains('заняты на дату'));
      expect(fewer.visibleNote, isNot(contains('из 10')));
    }
    const rare = SelectionPresentation(
      outcome: MatchOutcome.matched,
      count: 2,
      summary: 'Проходят по указанным условиям 2 из 2; показано 2.',
    );
    expect(rare.visibleNote, contains('только 2 предложения'));
    const unknown = SelectionPresentation(
      outcome: MatchOutcome.matched,
      count: 3,
      summary: '',
      preliminary: true,
    );
    expect(unknown.title, contains('Предварительная'));
    expect(unknown.title, isNot(contains('лучших')));
    const absent = SelectionPresentation(
      outcome: MatchOutcome.categoryAbsent,
      count: 0,
      summary: 'В этом городе такой категории пока нет в каталоге.',
    );
    const empty = SelectionPresentation(
      outcome: MatchOutcome.noEligible,
      count: 0,
      summary: 'Никто не проходит. 3 — заняты на дату.',
    );
    expect(absent.title, isNot(empty.title));
    expect(empty.visibleNote, contains('заняты на дату'));
  });

  testWidgets(
    'statistics are disclosed; three-way comparison is visible immediately',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: Column(
                children: [
                  const SelectionOverview(
                    presentation: SelectionPresentation(
                      outcome: MatchOutcome.matched,
                      count: 3,
                      summary: _summary,
                    ),
                  ),
                  RecommendationComparison(recommendations: comparisonFixtures),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(_summary), findsNothing);
      expect(find.text('Сравнить'), findsNothing);
      for (final r in comparisonFixtures) {
        expect(find.text(r.explanation), findsOneWidget);
        expect(find.text(r.contractor.name), findsOneWidget);
      }
      expect(find.text('Без привязки к часам присутствия'), findsOneWidget);
      final first = tester.getTopLeft(
        find.byKey(const ValueKey('comparison-profile-choice-0')),
      );
      final second = tester.getTopLeft(
        find.byKey(const ValueKey('comparison-profile-choice-1')),
      );
      final third = tester.getTopLeft(
        find.byKey(const ValueKey('comparison-profile-choice-2')),
      );
      expect(first.dy, second.dy);
      expect(first.dy, third.dy);
      expect(first.dx, lessThan(second.dx));
      expect(second.dx, lessThan(third.dx));
      for (var row = 1; row <= 4; row++) {
        final top = tester
            .getTopLeft(find.byKey(ValueKey('comparison-choice-0-$row')))
            .dy;
        for (var i = 1; i < 3; i++) {
          expect(
            tester
                .getTopLeft(find.byKey(ValueKey('comparison-choice-$i-$row')))
                .dy,
            top,
          );
        }
      }
      await tester.tap(find.text('Как мы подобрали'));
      await tester.pumpAndSettle();
      expect(find.text(_summary), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final scenario in [
    (width: 375.0, height: 812.0, scale: 1.0),
    (width: 844.0, height: 390.0, scale: 1.0),
    (width: 1024.0, height: 768.0, scale: 1.0),
    (width: 1440.0, height: 1100.0, scale: 2.0),
  ]) {
    testWidgets('comparison wraps without clipping at $scenario', (
      tester,
    ) async {
      tester.view.physicalSize = Size(scenario.width, scenario.height);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = scenario.scale;
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: RecommendationComparison(
                recommendations: comparisonFixtures,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final r in comparisonFixtures) {
        final button = find.byKey(ValueKey('profile-${r.contractor.id}'));
        await tester.ensureVisible(button);
        await tester.pumpAndSettle();
        expect(
          tester.getRect(button).right,
          lessThanOrEqualTo(scenario.width - 16),
        );
        expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
        expect(find.text(r.explanation), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }
}
