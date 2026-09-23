import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:event_match/app/app.dart';
import 'package:event_match/features/matching/data/catalog_repository.dart';
import 'widget_test.dart' show MemoryCatalog;

void main() {
  testWidgets(
    'desktop dropdown filters validate, cancel drafts and preserve applied values',
    (tester) async {
      final catalog = await tester.runAsync(
        () => AssetCatalogRepository().load(),
      );
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        EventMatchApp(repository: MemoryCatalog(catalog!)),
      );
      await tester.pumpAndSettle();
      Future<void> tapKey(String key) async {
        final finder = find.byKey(Key(key));
        await tester.ensureVisible(finder);
        await tester.pumpAndSettle();
        await tester.tap(finder);
        await tester.pumpAndSettle();
      }

      String value(String key) =>
          tester.widget<TextFormField>(find.byKey(Key(key))).controller!.text;
      expect(find.byKey(const Key('budget-input')), findsNothing);
      await tapKey('advanced-filters-toggle');
      expect(find.byType(Dialog), findsNothing);
      await tester.enterText(find.byKey(const Key('budget-input')), '500000');
      await tapKey('cancel-filters');
      expect(find.text('Ваша подборка'), findsNothing);
      await tapKey('advanced-filters-toggle');
      expect(value('budget-input'), '1000000');
      await tester.enterText(find.byKey(const Key('budget-input')), '0');
      await tapKey('apply-filters');
      expect(find.text('Введите целое число больше нуля'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('budget-input')), '1000000');
      await tester.enterText(find.byKey(const Key('hours-input')), '4');
      expect(find.byKey(const Key('preferences-input')), findsNothing);
      await tapKey('language-select');
      await tester.tap(find.text('русский').last);
      await tester.pumpAndSettle();
      await tapKey('apply-filters');
      expect(find.byKey(const Key('budget-input')), findsNothing);
      expect(find.text('Ваша подборка'), findsOneWidget);
      expect(find.text('русский'), findsOneWidget);
      await tapKey('advanced-filters-toggle');
      expect(value('hours-input'), '4.0');
      await tester.enterText(find.byKey(const Key('hours-input')), '-1');
      await tapKey('apply-filters');
      expect(find.text('Введите число больше нуля'), findsOneWidget);
      await tapKey('cancel-filters');
      expect(find.text('4.0 ч'), findsOneWidget);
      await tapKey('reset-filters');
      expect(find.text('Каталог · 500 профилей'), findsOneWidget);
      await tapKey('advanced-filters-toggle');
      expect(value('hours-input'), isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}
