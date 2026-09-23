import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:event_match/app/app.dart';
import 'package:event_match/features/matching/data/catalog_repository.dart';
import 'package:event_match/features/matching/presentation/widgets/contractor_card.dart';
import 'package:event_match/features/matching/presentation/widgets/contractor_details.dart';
import 'widget_test.dart' show MemoryCatalog;

void main() {
  for (final width in [1440.0, 1694.0]) {
    testWidgets(
      'equal row heights and profile closes without moving catalog at $width',
      (tester) async {
        final profiles = await tester.runAsync(
          () => AssetCatalogRepository().load(),
        );
        final repo = MemoryCatalog(profiles!.take(3).toList());
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(EventMatchApp(repository: repo));
        await tester.pumpAndSettle();
        expect(find.byType(ExpansionTile), findsNothing);
        final cards = find.byType(ContractorCard);
        expect(
          tester.getSize(cards.at(0)).height,
          tester.getSize(cards.at(1)).height,
        );
        final first = find.byKey(ValueKey('profile-${repo.profiles[0].id}'));
        final second = find.byKey(ValueKey('profile-${repo.profiles[1].id}'));
        expect(tester.getBottomLeft(first).dy, tester.getBottomLeft(second).dy);
        await tester.ensureVisible(first);
        await tester.pumpAndSettle();
        final position = tester.getTopLeft(cards.first);
        await tester.tap(first);
        await tester.pumpAndSettle();
        expect(find.byType(ContractorDetails), findsOneWidget);
        expect(tester.getSize(find.byType(ContractorDetails)).width, 640);
        expect(
          tester.getTopLeft(find.byType(ContractorDetails)).dx,
          greaterThan(width / 2),
        );
        expect(
          find.byWidgetPredicate(
            (w) =>
                w is SelectableText &&
                w.data == repo.profiles.first.description,
          ),
          findsOneWidget,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.byType(ContractorDetails), findsNothing);
        expect(tester.getTopLeft(cards.first), position);
        // The action remains usable after closing the route.
        await tester.tap(first);
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Закрыть профиль'));
        await tester.pumpAndSettle();
        expect(find.byType(ContractorDetails), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'short desktop with large text retains visible close and scrollable description',
    (tester) async {
      final profiles = await tester.runAsync(
        () => AssetCatalogRepository().load(),
      );
      tester.view.physicalSize = const Size(1024, 500);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(
        EventMatchApp(repository: MemoryCatalog(profiles!.take(1).toList())),
      );
      await tester.pumpAndSettle();
      final button = find.byKey(ValueKey('profile-${profiles.first.id}'));
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
      final close = find.byTooltip('Закрыть профиль');
      final before = tester.getTopLeft(close);
      await tester.drag(
        find.descendant(
          of: find.byType(ContractorDetails),
          matching: find.byType(SingleChildScrollView),
        ),
        const Offset(0, -500),
      );
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(close), before);
      await tester.tap(close);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
