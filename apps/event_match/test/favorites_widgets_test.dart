import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:event_match/app/app_theme.dart';
import 'package:event_match/features/matching/data/favorites_repository.dart';
import 'package:event_match/features/matching/presentation/favorites_controller.dart';
import 'package:event_match/features/matching/presentation/favorites_page.dart';
import 'package:event_match/features/matching/presentation/widgets/favorite_folder_picker.dart';
import 'favorites_test.dart' show contractor, request;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'existing-folder picker removes and re-adds only that membership',
    (tester) async {
      final controller = FavoritesController(LocalFavoritesRepository());
      await controller.load();
      await controller.createAndSave('Свадьба', contractor, request);
      await controller.createAndSave('Вторая папка', contractor, null);
      final first = controller.folders.first.id;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => FavoriteFolderPicker(
                    controller: controller,
                    contractor: contractor,
                    request: request,
                  ),
                ),
                child: const Text('Сохранить'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('save-folder-$first')));
      await tester.pumpAndSettle();
      expect(controller.folders.first.entries, isEmpty);
      expect(controller.folders.last.entries, hasLength(1));
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('save-folder-$first')));
      await tester.pumpAndSettle();
      expect(controller.folders.first.entries, hasLength(1));
      expect(
        controller.folders.first.entries.single.request!.toJson(),
        request.toJson(),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  testWidgets('empty state, rename and delete folder work through navigation', (
    tester,
  ) async {
    final controller = FavoritesController(LocalFavoritesRepository());
    await controller.load();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: FavoritesPage(
          controller: controller,
          catalog: const [contractor],
        ),
      ),
    );
    expect(find.text('Пока нет сохранённых подрядчиков'), findsOneWidget);
    await controller.createAndSave('Свадьба', contractor, request);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(ValueKey('favorite-folder-${controller.folders.single.id}')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Действия с папкой'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Переименовать'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Наш праздник');
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    expect(find.text('Наш праздник'), findsOneWidget);
    await tester.tap(find.byTooltip('Действия с папкой'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Удалить папку'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Удалить'));
    await tester.pumpAndSettle();
    expect(find.text('Пока нет сохранённых подрядчиков'), findsOneWidget);
    expect(await LocalFavoritesRepository().load(), isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}
