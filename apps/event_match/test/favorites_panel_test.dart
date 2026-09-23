import 'package:event_match/app/app.dart';
import 'package:event_match/features/matching/presentation/favorites_controller.dart';
import 'package:event_match/features/matching/presentation/favorites_page.dart';
import 'package:event_match/features/matching/presentation/widgets/contractor_card.dart';
import 'package:event_match/features/matching/presentation/widgets/contractor_details.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'favorites_flow_test.dart' show FlowCatalog;
import 'favorites_test.dart' show FailingRepository;

void main() {
  testWidgets(
    'favorites and folders stay in the right panel and preserve catalog scroll',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = FailingRepository();
      final catalog = FlowCatalog();
      final seed = FavoritesController(repository);
      await seed.load();
      await seed.createAndSave('Наша команда', catalog.profiles.first, null);
      final folderId = seed.folders.single.id;
      seed.dispose();
      await tester.pumpWidget(
        EventMatchApp(repository: catalog, favoritesRepository: repository),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(ContractorCard).first);
      await tester.pumpAndSettle();
      final catalogScroll = tester
          .state<ScrollableState>(
            find
                .descendant(
                  of: find.byType(CustomScrollView),
                  matching: find.byType(Scrollable),
                )
                .first,
          )
          .position;
      final scrollBefore = catalogScroll.pixels;

      Future<void> open() async {
        await tester.tap(find.byKey(const Key('open-favorites-desktop')));
        await tester.pumpAndSettle();
        expect(find.byType(Dialog), findsOneWidget);
        expect(find.byType(CustomScrollView), findsOneWidget);
        expect(catalogScroll.pixels, scrollBefore);
      }

      Future<void> folder() async {
        await tester.tap(find.byKey(ValueKey('favorite-folder-$folderId')));
        await tester.pumpAndSettle();
        expect(find.byType(FavoriteFolderPage), findsOneWidget);
        expect(find.byType(Dialog), findsOneWidget);
      }

      await open();
      final bounds = tester.getRect(find.byType(FavoritesPage));
      expect(bounds.width, 640);
      expect(bounds.right, 1440 - 24);
      expect(bounds.top, 24);
      await folder();
      expect(tester.getRect(find.byType(FavoriteFolderPage)), bounds);

      final profile = find.descendant(
        of: find.byType(FavoriteFolderPage),
        matching: find.byKey(const ValueKey('profile-host-0')),
      );
      await tester.ensureVisible(profile);
      await tester.pumpAndSettle();
      await tester.tap(profile);
      await tester.pumpAndSettle();
      expect(find.byType(ContractorDetails), findsOneWidget);
      expect(tester.getRect(find.byType(ContractorDetails)), bounds);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(ContractorDetails), findsNothing);
      expect(find.byType(FavoriteFolderPage), findsOneWidget);

      await tester.tap(find.byTooltip('К папкам избранного'));
      await tester.pumpAndSettle();
      expect(find.byType(FavoriteFolderPage), findsNothing);
      expect(find.text('Наша команда'), findsOneWidget);
      await folder();
      await tester.tap(find.byTooltip('Закрыть избранное'));
      await tester.pumpAndSettle();
      expect(find.byType(FavoritesPage), findsNothing);
      expect(catalogScroll.pixels, scrollBefore);

      await open();
      await folder();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(FavoritesPage), findsNothing);
      expect(catalogScroll.pixels, scrollBefore);

      await open();
      await tester.tapAt(const Offset(200, 300));
      await tester.pumpAndSettle();
      expect(find.byType(FavoritesPage), findsNothing);
      expect(catalogScroll.pixels, scrollBefore);
      expect(tester.takeException(), isNull);
    },
  );
}
