// Opt-in visual snapshots for local design review, not platform-specific CI tests.
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
  for (final size in [const Size(1440, 1100), const Size(390, 1000)]) {
    testWidgets('design preview ${size.width}', (tester) async {
      final repository = MemoryCatalog(
        await tester.runAsync(() => AssetCatalogRepository().load()) ?? [],
      );
      // Use installed fonts only for review; no system fonts are distributed.
      final fontPath =
          '${Platform.environment['SystemRoot']}/Fonts/segoeui.ttf';
      await tester.runAsync(() async {
        final bytes = await File(fontPath).readAsBytes();
        final loader = FontLoader('Roboto')
          ..addFont(Future.value(ByteData.sublistView(bytes)));
        await loader.load();
        final icons = FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
        await icons.load();
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
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final snapshot = await boundary.toImage(pixelRatio: 1);
        final png = await snapshot.toByteData(format: ui.ImageByteFormat.png);
        final destination = File(
          'build/previews/catalog-${size.width.toInt()}.png',
        );
        await destination.parent.create(recursive: true);
        await destination.writeAsBytes(png!.buffer.asUint8List());
        snapshot.dispose();
      });
    }, skip: !enabled || !Platform.isWindows);
  }
}
