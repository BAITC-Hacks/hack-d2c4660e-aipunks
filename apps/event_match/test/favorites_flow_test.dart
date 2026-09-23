import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:event_match/app/app.dart';
import 'package:event_match/features/matching/data/catalog_repository.dart';
import 'package:event_match/features/matching/data/favorites_repository.dart';
import 'package:event_match/features/matching/domain/matching_engine.dart';
import 'package:event_match/features/matching/domain/models.dart';
import 'package:event_match/features/matching/domain/recommendation_service.dart';

class FlowCatalog implements CatalogRepository {
  final profiles = [
    for (var i = 0; i < 4; i++)
      Contractor(
        id: 'host-$i',
        name: ['Алина', 'Данияр', 'Мадина', 'Арман'][i],
        city: 'Алматы',
        categories: ['Ведущий'],
        price: 200000 + i * 70000,
        formats: ['свадьба', 'той'],
        languages: ['русский', 'казахский'],
        maxHours: 4.0 + i,
        busyDates: i == 0 ? ['2026-10-10'] : [],
        description:
            'Камерные свадьбы и семейные истории. Программа с музыкальными играми.',
      ),
  ];
  @override
  Future<List<Contractor>> load() async => profiles;
}

class RecordingService implements RecommendationService {
  RecordingService(this.catalog);
  final FlowCatalog catalog;
  final requests = <MatchRequest>[];
  @override
  bool get supportsPreferences => true;
  @override
  Future<MatchResult> recommend(MatchRequest request) async {
    requests.add(request);
    return const MatchingEngine().match(catalog.profiles, request);
  }
}

Future<void> capture(WidgetTester tester, GlobalKey key, String name) async {
  if (!const bool.fromEnvironment('VISUAL_PREVIEW')) return;
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final snapshot = await boundary.toImage(pixelRatio: 1);
    final png = await snapshot.toByteData(format: ui.ImageByteFormat.png);
    final destination = File('build/previews/$name.png');
    await destination.parent.create(recursive: true);
    await destination.writeAsBytes(png!.buffer.asUint8List());
    snapshot.dispose();
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final config in [
    (const Size(390, 1000), 1.0),
    (const Size(1440, 1100), 1.0),
    (const Size(390, 1000), 2.0),
  ]) {
    testWidgets(
      'favorite folders and alternative dates at ${config.$1}, scale ${config.$2}',
      (tester) async {
        tester.view.physicalSize = config.$1;
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = config.$2;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        if (const bool.fromEnvironment('VISUAL_PREVIEW')) {
          await tester.runAsync(() async {
            for (final font in {
              'Manrope': 'assets/fonts/Manrope.ttf',
              'NotoSans': 'assets/fonts/NotoSans.ttf',
              'CormorantGaramond': 'assets/fonts/CormorantGaramond-Italic.ttf',
            }.entries) {
              await (FontLoader(
                font.key,
              )..addFont(rootBundle.load(font.value))).load();
            }
            await (FontLoader('MaterialIcons')
                  ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
                .load();
          });
        }
        final catalog = FlowCatalog();
        final service = RecordingService(catalog);
        final repository = LocalFavoritesRepository();
        final key = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: key,
            child: EventMatchApp(
              repository: catalog,
              recommendationService: service,
              favoritesRepository: repository,
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byKey(const Key('open-filters')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('open-filters')));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byKey(const Key('apply-filters')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('apply-filters')));
        await tester.pumpAndSettle();
        final first = service.requests.single;
        final otherDay = find.byKey(const ValueKey('alternative-2026-10-09'));
        await tester.ensureVisible(otherDay);
        await tester.pumpAndSettle();
        final suffix = '${config.$1.width.toInt()}-${config.$2.toInt()}';
        await capture(tester, key, 'dates-$suffix');
        await tester.tap(otherDay);
        await tester.pumpAndSettle();
        final next = service.requests.last;
        expect(next.date, DateTime(2026, 10, 9));
        expect(
          next.toJson().keys.where(
            (k) => next.toJson()[k] != first.toJson()[k],
          ),
          ['date'],
        );
        expect(find.text('4 варианта'), findsWidgets);

        final heart = find
            .byWidgetPredicate(
              (widget) =>
                  widget is IconButton &&
                  widget.key is ValueKey<String> &&
                  (widget.key as ValueKey<String>).value.startsWith(
                    'favorite-',
                  ),
            )
            .first;
        final contractorId =
            (tester.widget<IconButton>(heart).key as ValueKey<String>).value
                .substring('favorite-'.length);
        await tester.ensureVisible(heart);
        await tester.pumpAndSettle();
        await tester.tap(heart);
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<TextField>(find.byKey(const Key('favorite-folder-name')))
              .controller!
              .text,
          'Свадьба · Алматы · Октябрь 2026',
        );
        await capture(tester, key, 'favorite-picker-$suffix');
        final create = find.byKey(const Key('create-favorite-folder'));
        await tester.ensureVisible(create);
        await tester.pumpAndSettle();
        await tester.tap(create);
        await tester.pumpAndSettle();
        final folder = (await repository.load()).single;
        expect(folder.entries.single.request!.toJson(), next.toJson());
        expect(
          tester.widget<IconButton>(heart).tooltip,
          'Сохранено в избранном',
        );

        final nav = find.byKey(
          Key(
            config.$1.width >= 1200 && config.$2 == 1
                ? 'open-favorites-desktop'
                : 'open-favorites-mobile',
          ),
        );
        await tester.tap(nav);
        await tester.pumpAndSettle();
        await capture(tester, key, 'favorite-folders-$suffix');
        final folderTile = find.byKey(ValueKey('favorite-folder-${folder.id}'));
        await tester.ensureVisible(folderTile);
        await tester.pumpAndSettle();
        await tester.tap(folderTile);
        await tester.pumpAndSettle();
        await capture(tester, key, 'favorite-folder-content-$suffix');
        final restore = find.byKey(ValueKey('restore-search-${contractorId}'));
        await tester.scrollUntilVisible(
          restore,
          300,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.pumpAndSettle();
        expect(
          find.text('Подходит по сохранённым условиям каталога.'),
          findsOneWidget,
        );
        await tester.tap(restore);
        await tester.pumpAndSettle();
        expect(service.requests.last.toJson(), next.toJson());
        expect(service.requests, hasLength(3));
        expect(tester.takeException(), isNull);
      },
    );
  }
}
