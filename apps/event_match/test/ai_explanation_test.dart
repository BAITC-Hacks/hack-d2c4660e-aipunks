import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:event_match/app/app_theme.dart';
import 'package:event_match/features/matching/presentation/widgets/ai_explanation.dart';

void main() {
  for (final reduced in [false, true]) {
    testWidgets('AI badge wraps at 320px, finite motion, reduced=$reduced', (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduced, textScaler: const TextScaler.linear(2)),
          child: const Scaffold(body: AiExplanation(text: 'Проводит камерные свадьбы на русском языке. Программа рассчитана на небольшие группы.')),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Объяснение от ИИ'), findsOneWidget);
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('fallback never claims AI authorship', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: AiExplanation(text: 'Факты из каталога.', generated: false))));
    expect(find.text('Объяснение от ИИ'), findsNothing);
    expect(find.byIcon(Icons.auto_awesome_outlined), findsNothing);
  });
}
