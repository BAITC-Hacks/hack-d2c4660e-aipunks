import 'dart:io';
import 'dart:ui' as ui;

import 'package:event_match/app/app_theme.dart';
import 'package:event_match/features/matching/domain/models.dart';
import 'package:event_match/features/workspace/domain/workspace_models.dart';
import 'package:event_match/features/workspace/domain/workspace_repository.dart';
import 'package:event_match/features/workspace/presentation/catalog_page.dart';
import 'package:event_match/features/workspace/presentation/client_page.dart';
import 'package:event_match/features/workspace/presentation/admin_page.dart';
import 'package:event_match/features/workspace/presentation/contractor_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'provider_admin_test.dart' show PortalRepository;

const providerContent = ProfileContent(
  name: 'Айжан — ведущая событий',
  city: 'Алматы',
  categories: ['Ведущий'],
  price: 120000,
  formats: ['свадьба', 'корпоратив'],
  languages: ['русский', 'казахский'],
  description: 'Камерные свадьбы с авторским сценарием.',
  contact: '+7 700 123 45 67',
);

class ClientRepository implements WorkspaceRepository {
  final events = <ClientEvent>[];
  final selections = <SavedSelection>[];
  final favorites = <Contractor>[];
  ProfileContent? currentContent = providerContent;
  bool busy = false;
  bool failFavoriteWrite = false;
  bool failEventWrite = false;
  final List<bool> favoriteWrites = [];

  @override
  Future<List<PublishedProfile>> listPublished() async => [
    if (currentContent != null)
      PublishedProfile(
        ownerId: 'provider',
        content: currentContent!,
        revision: 2,
        profileRevision: 4,
        published: true,
      ),
  ];
  @override
  Future<List<ClientEvent>> listEvents(String uid) async => events.toList();
  @override
  Future<String> saveEvent(String uid, ClientEvent value) async {
    if (failEventWrite) throw StateError('Offline');
    final id = value.id.isEmpty ? 'event-${events.length + 1}' : value.id;
    events.removeWhere((e) => e.id == id);
    events.add(
      ClientEvent(
        id: id,
        name: value.name,
        city: value.city,
        date: value.date,
        format: value.format,
        preferences: value.preferences,
      ),
    );
    return id;
  }

  @override
  Future<List<SavedSelection>> listSelections(String uid) async =>
      selections.toList();
  @override
  Future<String> saveSelection(String uid, SavedSelection value) async {
    final id = value.id.isEmpty
        ? 'selection-${selections.length + 1}'
        : value.id;
    selections.removeWhere((s) => s.id == id);
    selections.add(
      SavedSelection(
        id: id,
        eventId: value.eventId,
        name: value.name,
        request: value.request,
        entries: value.entries,
        savedAt: DateTime.now(),
      ),
    );
    return id;
  }

  @override
  Future<List<Contractor>> listFavorites(String uid) async =>
      favorites.toList();
  @override
  Future<void> setFavorite(
    String uid,
    Contractor value, {
    required bool favorite,
  }) async {
    if (failFavoriteWrite) throw StateError('Offline');
    favoriteWrites.add(favorite);
    favorites.removeWhere((c) => c.id == value.id);
    if (favorite) favorites.add(value);
  }

  @override
  Future<CalendarMonth?> getCalendar(String uid, DateTime date) async =>
      CalendarMonth(
        ownerId: uid,
        year: date.year,
        month: date.month,
        busyDays: busy ? [date.day] : [],
        confirmedAt: DateTime.now().subtract(const Duration(minutes: 1)),
      );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget host(Widget child, {double scale = 1}) => MaterialApp(
  theme: AppTheme.light,
  home: Scaffold(
    body: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: child,
        ),
      ),
    ),
  ),
);

Future<void> pump(
  WidgetTester tester,
  Widget child, {
  double width = 375,
  double scale = 1,
}) async {
  tester.view.physicalSize = Size(width, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(host(child, scale: scale));
  await tester.pumpAndSettle();
}

Future<void> openAction(WidgetTester tester, Finder action) async {
  await tester.ensureVisible(action);
  await tester.tap(action);
  // WorkspaceAction remains busy behind an open dialog.
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> runCatalogMatch(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const Key('live-open-filters')));
  await tester.tap(find.byKey(const Key('live-open-filters')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('apply-filters')));
  await tester.pumpAndSettle();
}

void seedEventAndSelection(ClientRepository repository) {
  final date = eventToday();
  repository.events.add(
    ClientEvent(
      id: 'event-1',
      name: 'Наша свадьба',
      city: 'Алматы',
      date: date,
      format: 'свадьба',
    ),
  );
  repository.selections.add(
    SavedSelection(
      id: 'selection-1',
      eventId: 'event-1',
      name: 'Ведущий · Наша свадьба',
      request: MatchRequest(
        city: 'Алматы',
        date: date,
        format: 'свадьба',
        category: 'Ведущий',
        budget: 1000000,
      ),
      entries: [
        Recommendation(
          providerContent.toContractor('provider'),
          'Историческое объяснение подбора',
        ),
      ],
      savedAt: DateTime.now(),
    ),
  );
}

void main() {
  testWidgets(
    'event and selection actions pass their context to integrated matching',
    (tester) async {
      final repository = ClientRepository();
      seedEventAndSelection(repository);
      ClientEvent? passedEvent;
      SavedSelection? passedSelection;
      void findContractors(ClientEvent event, SavedSelection? selection) {
        passedEvent = event;
        passedSelection = selection;
      }

      await pump(
        tester,
        ClientPage(
          repository: repository,
          uid: 'client',
          onFindContractors: findContractors,
        ),
      );
      await openAction(tester, find.text('Подобрать подрядчиков'));
      expect(passedEvent, same(repository.events.single));
      expect(passedSelection, isNull);
      expect(find.byKey(const Key('apply-filters')), findsNothing);
      await pump(
        tester,
        ClientPage(
          repository: repository,
          uid: 'client',
          section: 'selections',
          onFindContractors: findContractors,
        ),
      );
      await openAction(tester, find.text('Обновить подбор'));
      expect(passedSelection, same(repository.selections.single));
      expect(find.byKey(const Key('apply-filters')), findsNothing);
    },
  );

  testWidgets(
    'category-specific wishes remain current and survive legacy refresh',
    (tester) async {
      final repository = ClientRepository();
      seedEventAndSelection(repository);
      final before = repository.selections.single;
      repository.selections[0] = SavedSelection(
        id: before.id,
        eventId: before.eventId,
        name: before.name,
        entries: before.entries,
        request: MatchRequest.fromJson({
          ...before.request.toJson(),
          'preferences': 'Ведущий без конкурсов',
        }),
      );
      await pump(
        tester,
        ClientPage(
          repository: repository,
          uid: 'client',
          section: 'selections',
        ),
      );
      expect(
        find.textContaining('Условия мероприятия изменились'),
        findsNothing,
      );
      await openAction(tester, find.text('Обновить подбор'));
      await tester.tap(find.byKey(const Key('apply-filters')));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.text('Обновить сохранённую'));
      await tester.pumpAndSettle();
      expect(
        repository.selections.single.request.preferences,
        'Ведущий без конкурсов',
      );
    },
  );

  testWidgets(
    'workspace visual previews',
    (tester) async {
      final font = File('/System/Library/Fonts/Supplemental/Arial.ttf');
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
      final client = ClientRepository();
      seedEventAndSelection(client);
      final portal = PortalRepository();
      for (final width in [375.0, 1440.0]) {
        final screens = <String, Widget>{
          'client': ClientPage(repository: client, uid: 'client'),
          'contractor': ContractorPage(repository: portal, uid: 'supplier'),
          'calendar': ContractorPage(
            repository: portal,
            uid: 'supplier',
            section: 'calendar',
          ),
          'admin': AdminPage(repository: portal, uid: 'admin', isAdmin: true),
          'moderation': AdminPage(
            repository: portal,
            uid: 'admin',
            isAdmin: true,
            section: 'moderation',
          ),
        };
        for (final screen in screens.entries) {
          final key = GlobalKey();
          tester.view.physicalSize = Size(width, 1200);
          tester.view.devicePixelRatio = 1;
          await tester.pumpWidget(
            RepaintBoundary(key: key, child: host(screen.value)),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.runAsync(() async {
            final boundary =
                key.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final picture = await boundary.toImage(pixelRatio: 1);
            final bytes = await picture.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final file = File(
              'build/previews/workspace-${screen.key}-${width.toInt()}.png',
            );
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes!.buffer.asUint8List());
            picture.dispose();
          });
        }
      }
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    },
    skip: !const bool.fromEnvironment('WORKSPACE_VISUAL_PREVIEW'),
  );

  testWidgets('event create and edit persist and survive page recreation', (
    tester,
  ) async {
    final repository = ClientRepository();
    await pump(tester, ClientPage(repository: repository, uid: 'client'));
    await openAction(tester, find.text('Создать мероприятие'));
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Название'),
      'Встреча команды',
    );
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    expect(repository.events.single.name, 'Встреча команды');
    await openAction(tester, find.text('Изменить'));
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Название'),
      'Праздник команды',
    );
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    expect(repository.events.single.id, 'event-1');
    expect(repository.events.single.name, 'Праздник команды');
    await tester.pumpWidget(const SizedBox());
    await pump(tester, ClientPage(repository: repository, uid: 'client'));
    expect(find.text('Праздник команды'), findsOneWidget);
  });

  testWidgets('failed event save keeps dialog and full draft for retry', (
    tester,
  ) async {
    final repository = ClientRepository()..failEventWrite = true;
    await pump(tester, ClientPage(repository: repository, uid: 'client'));
    await openAction(tester, find.text('Создать мероприятие'));
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Название'),
      'Наш день',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Что важно для события?'),
      'Живые кадры без позирования',
    );
    await tester.ensureVisible(find.text('Сохранить'));
    await tester.tap(find.text('Сохранить'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(EventEditor), findsOneWidget);
    expect(
      find.textContaining('Не удалось сохранить мероприятие'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<TextFormField>(find.widgetWithText(TextFormField, 'Название'))
          .controller!
          .text,
      'Наш день',
    );
    expect(
      tester
          .widget<TextFormField>(
            find.widgetWithText(TextFormField, 'Что важно для события?'),
          )
          .controller!
          .text,
      'Живые кадры без позирования',
    );
    expect(repository.events, isEmpty);
    repository.failEventWrite = false;
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    expect(find.byType(EventEditor), findsNothing);
    expect(repository.events.single.name, 'Наш день');
    expect(repository.events.single.preferences, 'Живые кадры без позирования');
  });

  testWidgets('guest can resume saving a selection after sign in', (
    tester,
  ) async {
    final repository = ClientRepository();
    var requestedSignIn = 0;
    await pump(
      tester,
      CatalogPage(
        repository: repository,
        onRequireSignIn: () => requestedSignIn++,
      ),
    );
    await runCatalogMatch(tester);
    await openAction(tester, find.text('Сохранить подборку'));
    await tester.pumpAndSettle();
    expect(requestedSignIn, 1);
    expect(repository.selections, isEmpty);
    await pump(
      tester,
      CatalogPage(
        repository: repository,
        uid: 'client',
        onRequireSignIn: () {},
      ),
    );
    expect(find.text('Сохранить в мероприятие'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Название мероприятия'),
      'Наш праздник',
    );
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    expect(repository.events.single.name, 'Наш праздник');
    expect(repository.selections.single.eventId, repository.events.single.id);
    expect(
      repository.selections.single.entries.single.contractor.id,
      'provider',
    );
  });

  testWidgets(
    'favorite can be added from catalog and removed in client account',
    (tester) async {
      final repository = ClientRepository();
      await pump(
        tester,
        CatalogPage(
          repository: repository,
          uid: 'client',
          onRequireSignIn: () {},
        ),
      );
      await openAction(tester, find.text('В избранное'));
      await tester.pumpAndSettle();
      expect(repository.favorites.single.id, 'provider');
      await pump(
        tester,
        ClientPage(repository: repository, uid: 'client', section: 'favorites'),
      );
      await openAction(tester, find.text('Убрать из избранного'));
      await tester.pumpAndSettle();
      expect(repository.favorites, isEmpty);
      expect(find.text('Здесь будут ваши избранные'), findsOneWidget);
    },
  );

  testWidgets(
    'guest add action never removes an already saved favorite after sign in',
    (tester) async {
      final repository = ClientRepository()
        ..favorites.add(providerContent.toContractor('provider'));
      await pump(
        tester,
        CatalogPage(repository: repository, onRequireSignIn: () {}),
      );
      await openAction(tester, find.text('В избранное'));
      await tester.pumpAndSettle();
      await pump(
        tester,
        CatalogPage(
          repository: repository,
          uid: 'client',
          onRequireSignIn: () {},
        ),
      );
      expect(repository.favorites.map((c) => c.id), ['provider']);
      expect(repository.favoriteWrites, everyElement(isTrue));
    },
  );

  testWidgets(
    'failed guest favorite restoration shows a retry and preserves the action',
    (tester) async {
      final repository = ClientRepository()..failFavoriteWrite = true;
      await pump(
        tester,
        CatalogPage(repository: repository, onRequireSignIn: () {}),
      );
      await openAction(tester, find.text('В избранное'));
      await tester.pumpAndSettle();
      await pump(
        tester,
        CatalogPage(
          repository: repository,
          uid: 'client',
          onRequireSignIn: () {},
        ),
      );
      expect(find.text('Действие не завершено'), findsOneWidget);
      expect(repository.favorites, isEmpty);
      repository.failFavoriteWrite = false;
      await tester.ensureVisible(find.text('Повторить действие'));
      await tester.tap(find.text('Повторить действие'));
      await tester.pumpAndSettle();
      expect(repository.favorites.single.id, 'provider');
      expect(find.text('Действие не завершено'), findsNothing);
    },
  );

  testWidgets(
    'saved snapshot reports price and availability changes then refreshes same selection',
    (tester) async {
      final repository = ClientRepository();
      seedEventAndSelection(repository);
      repository.currentContent = const ProfileContent(
        name: 'Айжан — ведущая событий',
        city: 'Алматы',
        categories: ['Ведущий'],
        price: 150000,
        formats: ['свадьба'],
        languages: ['русский'],
        description: 'Обновлённая программа',
        contact: '+7 700 123 45 67',
      );
      repository.busy = true;
      await pump(
        tester,
        ClientPage(
          repository: repository,
          uid: 'client',
          section: 'selections',
        ),
      );
      expect(find.textContaining('цена теперь от 150 000'), findsOneWidget);
      expect(find.textContaining('дата занята'), findsOneWidget);
      repository.busy = false;
      await openAction(tester, find.text('Обновить подбор'));
      await tester.tap(find.byKey(const Key('apply-filters')));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Результат подбора'), findsOneWidget);
      await tester.tap(find.text('Обновить сохранённую'));
      await tester.pumpAndSettle();
      expect(repository.selections.single.id, 'selection-1');
      expect(
        repository.selections.single.entries.single.contractor.price,
        150000,
      );
      expect(find.textContaining('цена теперь'), findsNothing);
    },
  );

  testWidgets(
    'unpublished saved profile is identified without showing live contacts',
    (tester) async {
      final repository = ClientRepository();
      seedEventAndSelection(repository);
      repository.currentContent = null;
      await pump(
        tester,
        ClientPage(
          repository: repository,
          uid: 'client',
          section: 'selections',
        ),
      );
      expect(
        find.textContaining('карточка снята с публикации'),
        findsOneWidget,
      );
      expect(find.textContaining('+7 700 123 45 67'), findsNothing);
    },
  );

  for (final width in [375.0, 768.0, 1024.0, 1440.0]) {
    testWidgets('client and catalog pages fit $width pixels', (tester) async {
      final repository = ClientRepository();
      seedEventAndSelection(repository);
      repository.favorites.add(providerContent.toContractor('provider'));
      for (final section in ['events', 'selections', 'favorites']) {
        await pump(
          tester,
          ClientPage(repository: repository, uid: 'client', section: section),
          width: width,
        );
        expect(tester.takeException(), isNull, reason: section);
      }
      await pump(
        tester,
        CatalogPage(
          repository: repository,
          uid: 'client',
          onRequireSignIn: () {},
        ),
        width: width,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('saved selection and catalog support large text', (tester) async {
    final repository = ClientRepository();
    seedEventAndSelection(repository);
    await pump(
      tester,
      ClientPage(repository: repository, uid: 'client', section: 'selections'),
      scale: 1.5,
    );
    expect(tester.takeException(), isNull);
    await pump(
      tester,
      CatalogPage(
        repository: repository,
        uid: 'client',
        onRequireSignIn: () {},
      ),
      scale: 1.5,
    );
    expect(tester.takeException(), isNull);
  });
}
