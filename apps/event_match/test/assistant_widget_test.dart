import 'dart:io';
import 'dart:ui' as ui;

import 'package:event_match/app/app_theme.dart';
import 'package:event_match/features/assistant/data/basic_assistant_service.dart';
import 'package:event_match/features/assistant/domain/assistant_models.dart';
import 'package:event_match/features/assistant/domain/assistant_service.dart';
import 'package:event_match/features/assistant/presentation/assistant_controller.dart';
import 'package:event_match/features/assistant/presentation/assistant_screen.dart';
import 'package:event_match/features/matching/data/catalog_repository.dart';
import 'package:event_match/features/matching/domain/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

const _profiles = [
  Contractor(
    id: 'first',
    name: 'Первый фотограф',
    city: 'Астана',
    categories: ['Фотограф'],
    price: 100000,
    formats: ['свадьба'],
    languages: ['русский'],
    busyDates: ['2026-10-01'],
    description: 'Снимает живые эмоции и помогает парам перед камерой.',
    maxHours: 8,
  ),
  Contractor(
    id: 'second',
    name: 'Второй фотограф',
    city: 'Астана',
    categories: ['Фотограф'],
    price: 200000,
    formats: ['свадьба'],
    languages: ['русский', 'казахский'],
    busyDates: [],
    description: 'Документальные кадры и семейные портреты.',
    maxHours: 10,
  ),
];

class _Catalog implements CatalogRepository {
  @override
  Future<List<Contractor>> load() async => _profiles;
}

class _AiService implements AssistantService {
  final List<AssistantAction> actions = [];
  final List<String> texts = [];
  int failures = 0;
  @override
  bool get supportsFreeText => true;
  @override
  Future<AssistantTurn> send({
    required AssistantBrief brief,
    String? message,
    AssistantAction? action,
    List<AssistantMessage> history = const [],
  }) async {
    if (message != null) texts.add(message);
    if (action != null) actions.add(action);
    if (failures > 0) {
      failures--;
      throw const AssistantServiceException(
        'Проверьте соединение и повторите.',
      );
    }
    return AssistantTurn(
      brief: const AssistantBrief(
        city: 'Астана',
        category: 'Фотограф',
        eventFormat: 'свадьба',
        budgetKzt: 300000,
      ),
      message:
          'Нашла варианты под ваш запрос. На какую дату проверить доступность?',
      questionField: 'date',
      actions: [
        AssistantAction(
          id: 'date-${texts.length}',
          label: 'Выбрать дату',
          type: 'pick_date',
          field: 'date',
        ),
        const AssistantAction(
          id: 'skip-date',
          label: 'Пока не знаю',
          type: 'skip_field',
          field: 'date',
        ),
      ],
      result: AssistantResult(
        outcome: MatchOutcome.matched,
        recommendations: [
          for (final profile in _profiles)
            AssistantRecommendation(
              contractor: profile,
              explanation: 'В профиле: «${profile.description}».',
              unchecked: const ['Дата не проверена'],
            ),
        ],
        summary: 'Подходят два фотографа.',
        preliminary: true,
        unchecked: const ['Дата не проверена'],
      ),
    );
  }
}

Widget _app(AssistantController controller) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: AppTheme.light,
  locale: const Locale('ru'),
  supportedLocales: const [Locale('ru')],
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  home: Scaffold(body: AssistantScreen(controller: controller)),
);

Future<AssistantController> _controller(AssistantService service) async {
  final repository = _Catalog();
  final controller = AssistantController(
    service: service,
    basicService: BasicAssistantService(repository),
    repository: repository,
  );
  await controller.loadCatalog();
  return controller;
}

void main() {
  // Opt-in local renders for visual review; no platform fonts are distributed.
  for (final size in [const Size(375, 812), const Size(1440, 900)]) {
    testWidgets(
      'assistant visual preview $size',
      (tester) async {
        final font = FontLoader('Roboto');
        await tester.runAsync(() async {
          final flutterRoot =
              Platform.environment['FLUTTER_ROOT'] ??
              '/opt/homebrew/share/flutter';
          final bytes = await File(
            '$flutterRoot/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
          ).readAsBytes();
          font.addFont(Future.value(ByteData.sublistView(bytes)));
          await font.load();
          await (FontLoader('MaterialIcons')
                ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
              .load();
        });
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final controller = await _controller(_AiService());
        addTearDown(controller.dispose);
        final key = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(key: key, child: _app(controller)),
        );
        await tester.pumpAndSettle();
        for (final stage in ['welcome', 'results']) {
          if (stage == 'results') {
            await controller.sendMessage(
              'Фотограф на свадьбу в Астане до 300 тысяч. Хотим живые кадры.',
            );
            await tester.pumpAndSettle();
          }
          await tester.runAsync(() async {
            final boundary =
                key.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final snapshot = await boundary.toImage(pixelRatio: 1);
            final png = await snapshot.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final file = File(
              'build/previews/assistant-$stage-${size.width.toInt()}.png',
            );
            await file.parent.create(recursive: true);
            await file.writeAsBytes(png!.buffer.asUint8List());
            snapshot.dispose();
          });
        }
      },
      skip:
          !const bool.fromEnvironment('ASSISTANT_VISUAL_PREVIEW') ||
          !Platform.isMacOS,
    );
  }
  for (final size in [
    const Size(375, 812),
    const Size(768, 1024),
    const Size(1440, 900),
  ]) {
    testWidgets('chat and results adapt to $size without overflow', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final service = _AiService();
      final controller = await _controller(service);
      addTearDown(controller.dispose);
      await tester.pumpWidget(_app(controller));
      await tester.pumpAndSettle();
      expect(find.text('Кого подберём для вашего события?'), findsOneWidget);
      expect(
        find.byKey(
          Key(
            size.width >= 1000
                ? 'assistant-brief-sidebar'
                : 'assistant-brief-compact',
          ),
        ),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const Key('assistant-input')),
        'Фотограф на свадьбу в Астане до 300 тысяч',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('assistant-send')));
      await tester.pumpAndSettle();
      expect(service.texts, ['Фотограф на свадьбу в Астане до 300 тысяч']);
      expect(find.text('Предварительная подборка · 2'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('assistant-action-date-1')),
        findsOneWidget,
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('comparison-profile-first')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Первый фотограф'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('large text and keyboard leave the composer usable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final controller = await _controller(_AiService());
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(controller));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Уже учтено'));
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    final field = find.byKey(const Key('assistant-input'));
    expect(tester.getBottomLeft(field).dy, lessThanOrEqualTo(512));
    await tester.enterText(field, 'Нужен фотограф');
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pumpAndSettle();
    expect(controller.messages.length, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'basic flow shows early results and does not repeat skipped questions',
    (tester) async {
      final controller = await _controller(BasicAssistantService(_Catalog()));
      addTearDown(controller.dispose);
      await tester.pumpWidget(_app(controller));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ActionChip, 'Фотограф'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ActionChip, 'Астана'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ActionChip, 'свадьба'));
      await tester.pumpAndSettle();
      expect(controller.brief.canRecommend, isTrue);
      expect(controller.turn!.result!.preliminary, isTrue);
      expect(controller.turn!.questionField, 'date');
      await tester.tap(find.widgetWithText(ActionChip, 'Пока не знаю'));
      await tester.pumpAndSettle();
      expect(controller.turn!.questionField, 'budget_kzt');
      await tester.tap(find.widgetWithText(ActionChip, 'Пока не знаю'));
      await tester.pumpAndSettle();
      expect(
        controller.brief.skippedFields,
        containsAll(['date', 'budget_kzt']),
      );
      expect(controller.turn!.questionField, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'details and comparison display facts; rejection sends a typed reason',
    (tester) async {
      final service = _AiService();
      final controller = await _controller(service);
      await controller.sendMessage('Фотограф');
      addTearDown(controller.dispose);
      await tester.pumpWidget(_app(controller));
      await tester.pumpAndSettle();
      final details = find.byKey(const ValueKey('profile-first'));
      await tester.ensureVisible(details);
      await tester.pumpAndSettle();
      await tester.tap(details);
      await tester.pumpAndSettle();
      expect(find.text('Профиль подрядчика'), findsOneWidget);
      expect(find.text('Полное описание'), findsOneWidget);
      await tester.tap(find.byTooltip('Закрыть профиль'));
      await tester.pumpAndSettle();
      expect(find.text('Сравнить'), findsNothing);
      expect(
        find.byKey(const Key('recommendation-comparison')),
        findsOneWidget,
      );
      expect(find.text('русский, казахский'), findsOneWidget);
      final reject = find.widgetWithText(TextButton, 'Не подходит').first;
      await tester.ensureVisible(reject);
      await tester.pumpAndSettle();
      await tester.tap(reject);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ActionChip, 'Дорого'));
      await tester.pumpAndSettle();
      expect(service.actions.single.type, 'reject');
      expect(service.actions.single.value, {
        'contractor_id': 'first',
        'reason': 'price',
        'detail': 'Дорого',
      });
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('old response actions disappear after the next answer', (
    tester,
  ) async {
    final controller = await _controller(_AiService());
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(controller));
    await controller.sendMessage('Фотограф');
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('assistant-action-date-1')),
      findsOneWidget,
    );
    await controller.sendMessage('Всё-таки другой формат');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('assistant-action-date-1')), findsNothing);
    expect(
      find.byKey(const ValueKey('assistant-action-date-2')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    '375px large text preserves full action labels and card semantics',
    (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final semantics = tester.ensureSemantics();
      try {
        final controller = await _controller(_AiService());
        addTearDown(controller.dispose);
        await controller.sendMessage('Фотограф');
        final turn = AssistantTurn(
          brief: controller.brief,
          message: controller.turn!.message,
          result: controller.turn!.result,
          actions: const [
            AssistantAction(
              id: 'long-feature',
              label: 'Предпочитаю документальный стиль съёмки без постановки',
              type: 'add_preference',
              value: {
                'text': 'Документальный стиль',
                'importance': 'preferred',
                'polarity': 'positive',
              },
            ),
          ],
        );
        controller.turn = turn;
        controller.messages[controller.messages.length - 1] = AssistantMessage(
          role: 'assistant',
          text: turn.message,
          turn: turn,
        );
        await tester.pumpWidget(_app(controller));
        await tester.pumpAndSettle();
        final action = find.byKey(
          const ValueKey('assistant-action-long-feature'),
        );
        await tester.ensureVisible(action);
        await tester.pumpAndSettle();
        final paragraph = tester.renderObject<RenderParagraph>(
          find.text(turn.actions.single.label),
        );
        expect(paragraph.didExceedMaxLines, isFalse);
        expect(tester.getRect(action).right, lessThanOrEqualTo(359));
        final live = find.byKey(const Key('assistant-latest-response'));
        await tester.ensureVisible(live);
        await tester.pumpAndSettle();
        expect(
          tester.getSemantics(live).getSemanticsData().label,
          contains(turn.message),
        );
        expect(tester.widget<Semantics>(live).properties.liveRegion, isTrue);
        final details = find.byKey(const ValueKey('profile-first'));
        await tester.ensureVisible(details);
        await tester.pumpAndSettle();
        expect(
          tester.getSemantics(details).getSemanticsData().label,
          contains('Первый фотограф'),
        );
        expect(tester.getRect(details).height, greaterThanOrEqualTo(48));
        final input = find.byKey(const Key('assistant-input'));
        await tester.enterText(input, 'Хочу сохранить этот черновик пожелания');
        await tester.tap(find.text('Уже учтено'));
        await tester.pumpAndSettle();
        final addPreference = find.widgetWithText(
          TextButton,
          'Добавить пожелание',
        );
        await tester.ensureVisible(addPreference);
        await tester.pumpAndSettle();
        await tester.tap(addPreference);
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextField>(input).controller!.text,
          'Хочу сохранить этот черновик пожелания',
        );
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets('brief budget editor validates and submits a number directly', (
    tester,
  ) async {
    final service = _AiService();
    final controller = await _controller(service);
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(controller));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Уже учтено'));
    await tester.pumpAndSettle();
    final edit = find.byKey(const Key('brief-budget_kzt'));
    await tester.ensureVisible(edit);
    await tester.pumpAndSettle();
    await tester.tap(edit);
    await tester.pumpAndSettle();
    final amount = find.widgetWithText(TextFormField, 'Сумма, ₸');
    await tester.enterText(amount, '0');
    await tester.tap(find.widgetWithText(FilledButton, 'Применить'));
    await tester.pumpAndSettle();
    expect(find.text('Введите число больше нуля'), findsOneWidget);
    await tester.enterText(amount, '250000');
    await tester.tap(find.widgetWithText(FilledButton, 'Применить'));
    await tester.pumpAndSettle();
    expect(service.texts, isEmpty);
    expect(service.actions.single.type, 'set_field');
    expect(service.actions.single.field, 'budget_kzt');
    expect(service.actions.single.value, 250000);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'long preferences and rejection details keep action labels within the API limit',
    (tester) async {
      final service = _AiService();
      final controller = await _controller(service);
      final preference = List.filled(
        20,
        'Нужны живые кадры без постановки.',
      ).join(' ');
      controller.brief = AssistantBrief(
        preferences: [AssistantPreference(text: preference)],
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(_app(controller));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Уже учтено'));
      await tester.pumpAndSettle();
      final remove = find.byTooltip('Убрать пожелание: $preference');
      await tester.ensureVisible(remove);
      await tester.pumpAndSettle();
      await tester.tap(remove);
      await tester.pumpAndSettle();
      expect(service.actions.single.type, 'remove_preference');
      expect(service.actions.single.label.length, lessThanOrEqualTo(180));
      // Collapse the summary to leave the recommendation actions in view.
      await tester.ensureVisible(find.text('Уже учтено'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Уже учтено'));
      await tester.pumpAndSettle();
      final reject = find.widgetWithText(TextButton, 'Не подходит').first;
      await tester.ensureVisible(reject);
      await tester.pumpAndSettle();
      await tester.tap(reject);
      await tester.pumpAndSettle();
      final detail = List.filled(
        9,
        'Хочу больше примеров репортажа.',
      ).join(' ');
      await tester.enterText(
        find.widgetWithText(TextField, 'Своя причина'),
        detail,
      );
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Обновить подборку'));
      await tester.pumpAndSettle();
      expect(service.actions.last.type, 'reject');
      expect(service.actions.last.label.length, lessThanOrEqualTo(180));
      expect((service.actions.last.value as Map)['detail'], detail);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('failure preserves conditions and offers explicit basic mode', (
    tester,
  ) async {
    final service = _AiService()..failures = 1;
    final controller = await _controller(service);
    controller.brief = const AssistantBrief(city: 'Астана');
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(controller));
    await tester.enterText(
      find.byKey(const Key('assistant-input')),
      'Фотограф',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('assistant-send')));
    await tester.pumpAndSettle();
    expect(find.text('Ваши условия сохранены.'), findsOneWidget);
    expect(controller.brief.city, 'Астана');
    await tester.tap(find.widgetWithText(TextButton, 'Продолжить кнопками'));
    await tester.pumpAndSettle();
    expect(controller.service.supportsFreeText, isFalse);
    expect(find.text('Подбор кнопками'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
