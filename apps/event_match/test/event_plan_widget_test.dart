import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:event_match/app/app_theme.dart';
import 'package:event_match/features/matching/domain/models.dart';
import 'package:event_match/features/planning/domain/event_plan.dart';
import 'package:event_match/features/planning/domain/event_plan_repository.dart';
import 'package:event_match/features/planning/presentation/event_plan_page.dart';
import 'package:event_match/features/workspace/domain/workspace_models.dart';
import 'package:event_match/features/workspace/domain/workspace_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Workspace implements WorkspaceRepository {
  _Workspace() {
    event = ClientEvent(
      id: 'event-1',
      name: 'Праздник команды',
      city: 'Алматы',
      date: eventToday().add(const Duration(days: 60)),
      format: 'корпоратив',
      preferences: 'Камерный вечер без конкурсов',
    );
    for (var index = 1; index <= 3; index++) {
      profiles['p$index'] = PublishedProfile(
        ownerId: 'p$index',
        content: ProfileContent(
          name: 'Ведущий $index — камерные события',
          city: 'Алматы',
          categories: const ['Ведущий'],
          price: index * 100000,
          formats: const ['корпоратив', 'свадьба'],
          languages: const ['русский', 'казахский'],
          maxHours: 6,
          description: 'Авторская программа и спокойная атмосфера вечера.',
          contact: '+7 700 000 00 0$index',
        ),
        revision: 2,
        profileRevision: 3,
        published: true,
      );
    }
    selection = SavedSelection(
      id: 'selection-1',
      eventId: event.id,
      name: 'Ведущие для праздника',
      request: MatchRequest(
        city: event.city,
        date: event.date,
        format: event.format,
        preferences: event.preferences,
        category: 'Ведущий',
        budget: 400000,
        language: 'русский',
        hours: 4,
      ),
      entries: [
        for (final profile in profiles.values)
          Recommendation(
            profile.content.toContractor(profile.ownerId),
            'Подходит по языку, городу и формату.',
          ),
      ],
    );
  }

  late ClientEvent event;
  late SavedSelection selection;
  final profiles = <String, PublishedProfile>{};
  bool failLoad = false;
  bool staleCalendar = false;
  bool addSecondEvent = false;
  final calendarReads = <String>[];

  @override
  Future<List<ClientEvent>> listEvents(String uid) async {
    if (failLoad) throw StateError('Offline');
    return [
      event,
      if (addSecondEvent)
        ClientEvent(
          id: 'event-2',
          name: 'Вторая встреча',
          city: event.city,
          date: event.date,
          format: event.format,
        ),
    ];
  }

  @override
  Future<List<SavedSelection>> listSelections(String uid) async => [selection];

  @override
  Future<List<PublishedProfile>> listPublished() async =>
      profiles.values.toList();

  @override
  Future<CalendarMonth?> getCalendar(String uid, DateTime month) async {
    calendarReads.add(uid);
    if (!profiles.containsKey(uid)) {
      throw StateError('Permission denied for hidden profile');
    }
    return CalendarMonth(
      ownerId: uid,
      year: month.year,
      month: month.month,
      confirmedAt: DateTime.now().subtract(
        Duration(days: staleCalendar ? 31 : 1),
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Plans implements EventPlanRepository {
  final stored = <String, EventPlan>{};
  bool failSave = false;
  bool conflict = false;
  int writes = 0;

  @override
  Future<EventPlan> getPlan(String uid, String eventId) async =>
      stored[eventId] ?? EventPlan(eventId: eventId);

  @override
  Future<EventPlan> savePlan(String uid, EventPlan plan) async {
    if (failSave) throw StateError('Offline');
    if (conflict) {
      throw EventPlanConflict(
        expectedRevision: plan.revision,
        actualRevision: plan.revision + 1,
      );
    }
    plan.validate();
    final next = plan.copyWith(revision: plan.revision + 1);
    stored[plan.eventId] = next;
    writes++;
    return next;
  }
}

class _DelayedPlans extends _Plans {
  final response = Completer<EventPlan>();

  @override
  Future<EventPlan> savePlan(String uid, EventPlan plan) => response.future;
}

Future<void> _pump(
  WidgetTester tester,
  _Workspace workspace,
  _Plans plans, {
  double width = 375,
  double scale = 1,
  double height = 1100,
  GlobalKey? previewKey,
  String uid = 'client',
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: RepaintBoundary(
        key: previewKey,
        child: Scaffold(
          body: MediaQuery(
            data: MediaQueryData(
              size: Size(width, height),
              textScaler: TextScaler.linear(scale),
              disableAnimations: true,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: EventPlanPage(
                workspace: workspace,
                plans: plans,
                uid: uid,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _enter(WidgetTester tester, String key, String text) async {
  final finder = find.byKey(Key(key));
  await tester.ensureVisible(finder);
  await tester.enterText(finder, text);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('late save response cannot replace a different account plan', (
    tester,
  ) async {
    final workspace = _Workspace();
    final plans = _DelayedPlans();
    await _pump(tester, workspace, plans);
    await _enter(tester, 'plan-notes', 'Заметки первого клиента');
    final save = find.byKey(const Key('save-event-plan-bottom'));
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pump();
    await _pump(tester, workspace, plans, uid: 'another-client');
    plans.response.complete(
      const EventPlan(
        eventId: 'event-1',
        notes: 'Заметки первого клиента',
        revision: 1,
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('plan-notes')))
          .controller!
          .text,
      isEmpty,
    );
    expect(find.text('План сохранён'), findsNothing);
  });

  testWidgets(
    'switching events confirms unsaved loss and restores the picker after cancel',
    (tester) async {
      final workspace = _Workspace()..addSecondEvent = true;
      await _pump(tester, workspace, _Plans());
      await _enter(tester, 'plan-notes', 'Черновик первого события');
      final picker = find.byType(DropdownButtonFormField<String>);
      await _tap(tester, picker);
      await _tap(tester, find.text('Вторая встреча').last);
      await _tap(tester, find.text('Продолжить редактирование'));
      expect(
        tester.widget<DropdownButtonFormField<String>>(picker).initialValue,
        'event-1',
      );
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('plan-notes')))
            .controller!
            .text,
        'Черновик первого события',
      );
      await _tap(tester, picker);
      await _tap(tester, find.text('Вторая встреча').last);
      await _tap(tester, find.text('Загрузить без сохранения'));
      expect(
        tester.widget<DropdownButtonFormField<String>>(picker).initialValue,
        'event-2',
      );
      expect(find.text('Добавьте кандидатов в план'), findsOneWidget);
    },
  );

  testWidgets(
    'choice, budget, tasks and notes persist then restore; choice can be cleared',
    (tester) async {
      final workspace = _Workspace();
      final plans = _Plans();
      await _pump(tester, workspace, plans);
      await _tap(tester, find.byKey(const Key('choose-selection-1-p1')));
      await _enter(tester, 'plan-budget', '500000');
      await _enter(tester, 'plan-notes', 'Согласовать время монтажа');
      await _tap(tester, find.byKey(const Key('task-confirm_scope')));
      await _tap(tester, find.byKey(const Key('save-event-plan-bottom')));
      final saved = plans.stored['event-1']!;
      expect(saved.choices['Ведущий']!.contractorId, 'p1');
      expect(saved.totalBudgetKzt, 500000);
      expect(saved.completedTaskIds, contains('confirm_scope'));
      expect(saved.notes, 'Согласовать время монтажа');
      expect(saved.revision, 1);
      await tester.pumpWidget(const SizedBox());
      await _pump(tester, workspace, plans);
      expect(find.text('Все изменения сохранены'), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('plan-notes')))
            .controller!
            .text,
        saved.notes,
      );
      expect(
        tester
            .widget<CheckboxListTile>(
              find.byKey(const Key('task-confirm_scope')),
            )
            .value,
        isTrue,
      );
      expect(
        find.textContaining('Сумма актуальных стартовых цен: от 100 000'),
        findsOneWidget,
      );
      await _tap(tester, find.byKey(const Key('clear-Ведущий')));
      await _tap(tester, find.byKey(const Key('save-event-plan-bottom')));
      expect(plans.stored['event-1']!.choices, isEmpty);
      expect(plans.stored['event-1']!.revision, 2);
    },
  );

  testWidgets('failed saving retains edits and supports retry', (tester) async {
    final workspace = _Workspace();
    final plans = _Plans()..failSave = true;
    await _pump(tester, workspace, plans);
    await _tap(tester, find.byKey(const Key('choose-selection-1-p2')));
    await _enter(tester, 'plan-notes', 'Не терять эти заметки');
    await _tap(tester, find.byKey(const Key('save-event-plan-bottom')));
    expect(find.textContaining('Не удалось сохранить план.'), findsOneWidget);
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('plan-notes')))
          .controller!
          .text,
      'Не терять эти заметки',
    );
    expect(plans.stored, isEmpty);
    plans.failSave = false;
    await _tap(tester, find.byKey(const Key('save-event-plan-bottom')));
    expect(plans.stored['event-1']!.notes, 'Не терять эти заметки');
    expect(plans.stored['event-1']!.choices['Ведущий']!.contractorId, 'p2');
  });

  testWidgets(
    'revision conflict preserves edits and reload needs explicit discard',
    (tester) async {
      final workspace = _Workspace();
      final plans = _Plans()..conflict = true;
      await _pump(tester, workspace, plans);
      await _enter(tester, 'plan-notes', 'Моя версия');
      await _tap(tester, find.byKey(const Key('save-event-plan-bottom')));
      expect(
        find.textContaining('План уже изменён в другом окне.'),
        findsOneWidget,
      );
      await _tap(tester, find.text('Обновить данные'));
      expect(find.text('Есть несохранённые изменения'), findsWidgets);
      await _tap(tester, find.text('Продолжить редактирование'));
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('plan-notes')))
            .controller!
            .text,
        'Моя версия',
      );
      plans.stored['event-1'] = const EventPlan(
        eventId: 'event-1',
        notes: 'Новая версия с сервера',
        revision: 2,
      );
      await _tap(tester, find.text('Обновить данные'));
      await _tap(tester, find.text('Загрузить без сохранения'));
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('plan-notes')))
            .controller!
            .text,
        'Новая версия с сервера',
      );
      expect(find.text('Все изменения сохранены'), findsOneWidget);
    },
  );

  testWidgets('hidden profile never causes a forbidden calendar read', (
    tester,
  ) async {
    final workspace = _Workspace()..profiles.remove('p1');
    await _pump(tester, workspace, _Plans());
    expect(workspace.calendarReads, isNot(contains('p1')));
    expect(find.text('Карточка больше не опубликована.'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('choose-selection-1-p1')))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('choose-selection-1-p2')))
          .onPressed,
      isNotNull,
    );
    expect(find.textContaining('Не удалось загрузить план'), findsNothing);
  });

  testWidgets('unconfirmed calendars and changed briefs cannot be selected', (
    tester,
  ) async {
    final workspace = _Workspace()..staleCalendar = true;
    await _pump(tester, workspace, _Plans());
    expect(
      find.text('Доступность на дату мероприятия не подтверждена.'),
      findsNWidgets(3),
    );
    for (var id = 1; id <= 3; id++) {
      expect(
        tester
            .widget<FilledButton>(find.byKey(Key('choose-selection-1-p$id')))
            .onPressed,
        isNull,
      );
    }
    await tester.pumpWidget(const SizedBox());
    workspace.staleCalendar = false;
    workspace.event = ClientEvent(
      id: workspace.event.id,
      name: workspace.event.name,
      city: 'Астана',
      date: workspace.event.date,
      format: workspace.event.format,
    );
    await _pump(tester, workspace, _Plans());
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('choose-selection-1-p1')))
          .onPressed,
      isNull,
    );
    expect(find.textContaining('Обновите подборку в разделе'), findsOneWidget);
  });

  testWidgets('invalid budget is an inline error rather than an engine crash', (
    tester,
  ) async {
    final plans = _Plans();
    await _pump(tester, _Workspace(), plans);
    for (final invalid in ['0', '1000000001']) {
      await _enter(tester, 'plan-budget', invalid);
      expect(tester.takeException(), isNull);
      await _tap(tester, find.byKey(const Key('save-event-plan')));
      expect(find.textContaining('Укажите целое число'), findsOneWidget);
      expect(plans.writes, 0);
    }
    await _enter(tester, 'plan-budget', '');
    await _tap(tester, find.byKey(const Key('save-event-plan')));
    expect(plans.stored['event-1']!.totalBudgetKzt, isNull);
  });

  testWidgets(
    'long unicode notes remain editable without reaching domain validation',
    (tester) async {
      final plans = _Plans();
      await _pump(tester, _Workspace(), plans);
      final longText = List.filled(1001, '😀').join();
      await _enter(tester, 'plan-notes', longText);
      expect(tester.takeException(), isNull);
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('plan-notes')))
            .controller!
            .text,
        longText,
      );
      await _tap(tester, find.byKey(const Key('save-event-plan-bottom')));
      expect(plans.writes, 0);
      expect(find.textContaining('Заметка слишком длинная.'), findsOneWidget);
      await _enter(tester, 'plan-notes', 'Короткая заметка 😀');
      await _tap(tester, find.byKey(const Key('save-event-plan-bottom')));
      expect(plans.stored['event-1']!.notes, 'Короткая заметка 😀');
    },
  );

  testWidgets('failed initial load offers a working retry', (tester) async {
    final workspace = _Workspace()..failLoad = true;
    await _pump(tester, workspace, _Plans());
    expect(find.textContaining('Не удалось загрузить план'), findsOneWidget);
    workspace.failLoad = false;
    await _tap(tester, find.text('Повторить загрузку'));
    expect(find.text('Команда и бюджет'), findsOneWidget);
  });

  testWidgets('draft copies event context without saving or sending', (
    tester,
  ) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final plans = _Plans();
    final workspace = _Workspace();
    await _pump(tester, workspace, plans);
    await _tap(tester, find.byKey(const Key('brief-selection-1-p1')));
    expect(find.text('Черновик запроса подрядчику'), findsOneWidget);
    final editor = find.byKey(const Key('draft-request-text'));
    final original = tester.widget<TextField>(editor).controller!.text;
    await tester.enterText(editor, '$original\nВстреча начинается в 18:00.');
    await tester.pumpAndSettle();
    await _tap(tester, find.text('Скопировать текст'));
    expect(copied, contains('Камерный вечер без конкурсов'));
    expect(copied, contains('Бюджет категории: до 400000 ₸'));
    expect(copied, contains(dateKey(workspace.event.date)));
    expect(copied, contains('Встреча начинается в 18:00.'));
    expect(plans.writes, 0);
    expect(
      find.text('Черновик скопирован. Отправка не выполнялась.'),
      findsOneWidget,
    );
  });

  for (final width in [375.0, 1440.0]) {
    for (final scale in [1.0, 1.8]) {
      testWidgets(
        'planner and draft fit $width pixels with text scale $scale',
        (tester) async {
          await _pump(
            tester,
            _Workspace(),
            _Plans(),
            width: width,
            scale: scale,
          );
          expect(tester.takeException(), isNull);
          await _tap(tester, find.byKey(const Key('choose-selection-1-p1')));
          expect(tester.takeException(), isNull);
          await _tap(tester, find.byKey(const Key('brief-selection-1-p1')));
          expect(tester.takeException(), isNull);
          await _tap(tester, find.text('Закрыть'));
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('planner landscape supports large text and reduced motion', (
    tester,
  ) async {
    await _pump(
      tester,
      _Workspace(),
      _Plans(),
      width: 844,
      height: 390,
      scale: 1.8,
    );
    await _tap(tester, find.byKey(const Key('choose-selection-1-p1')));
    expect(tester.takeException(), isNull);
    await _tap(tester, find.byKey(const Key('brief-selection-1-p1')));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'render planner previews',
    (tester) async {
      final font = File('/System/Library/Fonts/SFNS.ttf');
      if (!font.existsSync()) return;
      await tester.runAsync(() async {
        final loader = FontLoader('Roboto')
          ..addFont(
            Future.value(ByteData.sublistView(await font.readAsBytes())),
          );
        await loader.load();
        await (FontLoader(
          'MaterialIcons',
        )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      });
      for (final width in [375.0, 1440.0]) {
        final key = GlobalKey();
        await _pump(
          tester,
          _Workspace(),
          _Plans(),
          width: width,
          previewKey: key,
        );
        for (final view in ['overview', 'comparison']) {
          if (view == 'comparison') {
            await tester.ensureVisible(find.text('Ведущие для праздника'));
          }
          await tester.pumpAndSettle();
          await tester.runAsync(() async {
            final boundary =
                key.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final picture = await boundary.toImage(pixelRatio: 1);
            final bytes = await picture.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final file = File(
              'build/previews/planner-$view-${width.toInt()}.png',
            );
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes!.buffer.asUint8List());
            picture.dispose();
          });
        }
      }
    },
    skip: !const bool.fromEnvironment('PLAN_VISUAL_PREVIEW'),
  );
}
