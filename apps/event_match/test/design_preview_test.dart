// Opt-in rendered previews for reviewing responsive layout with the bundled fonts.
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:event_match/app/app.dart';
import 'package:event_match/features/matching/data/catalog_repository.dart';
import 'widget_test.dart' show MemoryCatalog;

void main() {
  const enabled = bool.fromEnvironment('VISUAL_PREVIEW');
  for (final size in [
    const Size(1440, 1100),
    const Size(390, 1000),
    const Size(768, 1024),
  ]) {
    testWidgets('design preview ${size.width}', (tester) async {
      final repository = MemoryCatalog(
        await tester.runAsync(() => AssetCatalogRepository().load()) ?? [],
      );
      await tester.runAsync(() async {
        for (final font in {
          'Manrope': 'assets/fonts/Manrope.ttf',
          'NotoSans': 'assets/fonts/NotoSans.ttf',
          'CormorantGaramond': 'assets/fonts/CormorantGaramond-Italic.ttf',
          'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
        }.entries) {
          final loader = FontLoader(font.key)
            ..addFont(rootBundle.load(font.value));
          await loader.load();
        }
      });
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: EventMatchApp(repository: repository),
        ),
      );
      await tester.runAsync(
        () => precacheImage(
          const AssetImage('assets/images/event-table.jpg'),
          key.currentContext!,
        ),
      );
      await tester.pumpAndSettle();

      Future<void> capture(String name) async {
        await tester.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final snapshot = await boundary.toImage(pixelRatio: 1);
          final png = await snapshot.toByteData(format: ui.ImageByteFormat.png);
          final destination = File(
            'build/previews/$name-${size.width.toInt()}.png',
          );
          await destination.parent.create(recursive: true);
          await destination.writeAsBytes(png!.buffer.asUint8List());
          snapshot.dispose();
        });
      }

      await capture('catalog');
      await tester.tap(find.byKey(const Key('open-filters')));
      await tester.pumpAndSettle();
      await capture('filters');
      await tester.tap(find.byKey(const Key('apply-filters')));
      await tester.pumpAndSettle();
      await capture('results');
      expect(tester.takeException(), isNull);
    }, skip: !enabled);
  }
}
