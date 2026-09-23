import 'package:event_match/app/app.dart';
import 'package:event_match/features/matching/data/catalog_repository.dart';
import 'package:event_match/features/matching/presentation/widgets/contractor_card.dart';
import 'package:event_match/features/matching/presentation/widgets/catalog_hero.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'widget_test.dart' show MemoryCatalog;

void main() {
  for (final bundledFonts in [false, true]) {
    testWidgets(
      'desktop cards fit with bundled fonts: $bundledFonts',
      (tester) async {
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final profiles = await tester.runAsync(
          () => AssetCatalogRepository().load(),
        );
        if (bundledFonts) {
          await tester.runAsync(() async {
            for (final font in {
              'Manrope': 'assets/fonts/Manrope.ttf',
              'NotoSans': 'assets/fonts/NotoSans.ttf',
              'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
              'CormorantGaramond': 'assets/fonts/CormorantGaramond-Italic.ttf',
            }.entries) {
              await (FontLoader(
                font.key,
              )..addFont(rootBundle.load(font.value))).load();
            }
          });
        }
        final app = EventMatchApp(
          repository: MemoryCatalog(
            profiles!.where((profile) => profile.synthetic).take(5).toList(),
          ),
        );
        for (final viewport in [
          (width: 1706.0, dpr: 1.0, scale: 1.0, columns: 3),
          (width: 1705.0, dpr: 1.25, scale: 1.0, columns: 3),
          (width: 1440.0, dpr: 1.5, scale: 1.0, columns: 3),
          (width: 1706.0, dpr: 1.5, scale: 1.25, columns: 3),
          (width: 1024.0, dpr: 1.0, scale: 1.0, columns: 2),
          (width: 1706.0, dpr: 1.0, scale: 2.0, columns: 1),
        ]) {
          tester.view.physicalSize = Size(viewport.width, 1000) * viewport.dpr;
          tester.view.devicePixelRatio = viewport.dpr;
          tester.platformDispatcher.textScaleFactorTestValue = viewport.scale;
          await tester.pumpWidget(app);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: '$viewport');
          final cards = find.byType(ContractorCard);
          expect(cards, findsNWidgets(5));
          final width = tester.getSize(cards.first).width;
          for (var row = 0; row < 5; row += viewport.columns) {
            final height = tester.getSize(cards.at(row)).height;
            double? buttonBottom;
            for (
              var offset = 0;
              offset < viewport.columns && row + offset < 5;
              offset++
            ) {
              final card = cards.at(row + offset);
              expect(tester.getSize(card).height, height);
              expect(tester.getSize(card).width, closeTo(width, .01));
              final button = find.descendant(
                of: card,
                matching: find.byType(OutlinedButton),
              );
              final bottom = tester.getBottomRight(button);
              buttonBottom ??= bottom.dy;
              expect(bottom.dy, closeTo(buttonBottom, .01));
              expect(
                tester.getRect(card).contains(bottom + const Offset(0, 19)),
                isTrue,
                reason: 'The footer keeps its bottom padding at $viewport',
              );
            }
          }
        }
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );
  }

  testWidgets('hero photograph is registered and decodes from the bundle', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      expect(manifest.listAssets(), contains('assets/images/event-table.jpg'));
      final data = await rootBundle.load('assets/images/event-table.jpg');
      final image = await decodeImageFromList(data.buffer.asUint8List());
      expect(image.width, greaterThan(500));
      expect(image.height, greaterThan(300));
      image.dispose();
    });
  });

  testWidgets('missing hero photo retains its frame without an error widget', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1706, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: DefaultAssetBundle(
          bundle: _MissingPhotoBundle(),
          child: Scaffold(
            body: CatalogHero(count: 500, onBrowse: () {}),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.celebration_outlined), findsOneWidget);
    expect(find.byType(ErrorWidget), findsNothing);
    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byKey(const Key('catalog-hero-photo'))).height,
      332,
    );
  });
}

class _MissingPhotoBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) {
    if (key == 'assets/images/event-table.jpg') {
      return Future.error(FlutterError('Missing photo fixture'));
    }
    return rootBundle.load(key);
  }
}
