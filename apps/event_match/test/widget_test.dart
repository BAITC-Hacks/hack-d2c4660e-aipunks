import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:event_match/app/app.dart';
import 'package:event_match/features/matching/data/catalog_repository.dart';
import 'package:event_match/features/matching/domain/models.dart';

class MemoryCatalog implements CatalogRepository {
  MemoryCatalog(this.profiles);
  final List<Contractor> profiles;
  @override
  Future<List<Contractor>> load() async => profiles;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MemoryCatalog repository;
  setUpAll(() async {
    repository = MemoryCatalog(await AssetCatalogRepository().load());
  });
  for (final size in [
    const Size(375, 812),
    const Size(812, 375),
    const Size(768, 1024),
    const Size(1024, 768),
    const Size(1440, 900),
  ]) {
    testWidgets('search works without overflow at $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(EventMatchApp(repository: repository));
      await tester.pumpAndSettle();
      expect(find.text('Тони Тони Чоппер'), findsOneWidget);
      expect(find.byKey(const Key('budget-input')), findsNothing);
      await tester.ensureVisible(find.byKey(const Key('open-filters')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('open-filters')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('apply-filters')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('apply-filters')));
      await tester.pumpAndSettle();
      expect(find.text('Ваша подборка'), findsOneWidget);
      for (var rank = 1; rank <= 3; rank++) {
        expect(find.text('Рекомендация №$rank · Алматы'), findsOneWidget);
      }
      expect(find.byKey(const Key('budget-input')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('large text and result cards do not overflow', (tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(EventMatchApp(repository: repository));
    await tester.pumpAndSettle();
    final button = find.byKey(const Key('open-filters'));
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('apply-filters')));
    await tester.pumpAndSettle();
    expect(find.text('Ваша подборка'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'cancel retains applied conditions; invalid budget keeps dialog open; reset restores catalog',
    (tester) async {
      await tester.pumpWidget(EventMatchApp(repository: repository));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('open-filters')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('open-filters')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('apply-filters')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('open-filters')));
      await tester.pumpAndSettle();
      final budget = find.byKey(const Key('budget-input'));
      await tester.ensureVisible(budget);
      await tester.enterText(budget, '0');
      await tester.tap(find.byKey(const Key('apply-filters')));
      await tester.pumpAndSettle();
      expect(find.text('Введите целое число больше нуля'), findsOneWidget);
      await tester.tap(find.byTooltip('Закрыть без изменений'));
      await tester.pumpAndSettle();
      expect(find.text('Ваша подборка'), findsOneWidget);
      expect(find.text('до 1 000 000 ₸'), findsOneWidget);
      await tester.tap(find.byKey(const Key('reset-filters')));
      await tester.pumpAndSettle();
      expect(find.text('Каталог · 500 профилей'), findsOneWidget);
      expect(find.text('Тони Тони Чоппер'), findsOneWidget);
    },
  );
  testWidgets('catalog search and category shortcuts filter real profiles', (
    tester,
  ) async {
    await tester.pumpWidget(EventMatchApp(repository: repository));
    await tester.pumpAndSettle();
    final field = find.byKey(const Key('catalog-search'));
    await tester.ensureVisible(field);
    await tester.pumpAndSettle();
    await tester.enterText(field, 'чоппер');
    await tester.pumpAndSettle();
    expect(find.text('Тони Тони Чоппер'), findsOneWidget);
    expect(find.text('Буллма'), findsNothing);
    await tester.enterText(field, 'несуществующий профиль');
    await tester.pumpAndSettle();
    expect(find.text('Ничего не нашлось'), findsOneWidget);
    await tester.enterText(field, '');
    await tester.pumpAndSettle();
    final category = find.widgetWithText(ChoiceChip, 'Флорист');
    await tester.ensureVisible(category);
    await tester.pumpAndSettle();
    await tester.tap(category);
    await tester.pumpAndSettle();
    expect(find.text('Буллма'), findsNothing);
    expect(find.text('Тони Тони Чоппер'), findsOneWidget);
  });
  testWidgets(
    'relaxation applies one new request and updates visible conditions',
    (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(EventMatchApp(repository: repository));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('open-filters')));
      await tester.tap(find.byKey(const Key('open-filters')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('budget-input')));
      await tester.enterText(find.byKey(const Key('budget-input')), '1');
      await tester.tap(find.byKey(const Key('apply-filters')));
      await tester.pumpAndSettle();
      expect(find.text('Нет подходящих кандидатов'), findsOneWidget);
      final suggestion = find.byKey(const ValueKey('relaxation-0'));
      await tester.ensureVisible(suggestion);
      await tester.pumpAndSettle();
      await tester.tap(suggestion);
      await tester.pumpAndSettle();
      expect(find.text('Ваша подборка'), findsOneWidget);
      expect(find.text('до 1 ₸'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
