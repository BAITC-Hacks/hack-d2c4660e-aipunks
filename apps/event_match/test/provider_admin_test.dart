import 'package:event_match/app/app_theme.dart';
import 'package:event_match/features/workspace/domain/workspace_models.dart';
import 'package:event_match/features/workspace/domain/workspace_repository.dart';
import 'package:event_match/features/workspace/presentation/admin_page.dart';
import 'package:event_match/features/workspace/presentation/contractor_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const content = ProfileContent(
  name: 'Студия праздничной фотографии',
  city: 'Алматы',
  categories: ['Фотограф'],
  price: 100000,
  formats: ['свадьба'],
  languages: ['русский'],
  description: 'Фотосъёмка свадеб и камерных мероприятий.',
  contact: '+7 700 123 45 67',
  portfolioUrls: ['https://example.com/portfolio'],
);

class PortalRepository implements WorkspaceRepository {
  ContractorProfile? profile = const ContractorProfile(
    ownerId: 'supplier',
    content: content,
    revision: 4,
    status: 'pending',
  );
  PublishedProfile? published;
  CalendarMonth? calendar;
  ProfileContent? savedContent;
  int? moderatedRevision;
  String? moderatedReason;
  bool throwModeration = false;
  @override
  Future<ContractorProfile?> getProfile(String uid) async => profile;
  @override
  Future<PublishedProfile?> getPublished(String uid) async => published;
  @override
  Future<List<ContractorProfile>> listProfiles() async => [?profile];
  @override
  Future<List<PublishedProfile>> listPublished() async => [?published];
  @override
  Future<CalendarMonth?> getCalendar(String uid, DateTime month) async =>
      calendar;
  @override
  Future<void> saveCalendar(String uid, CalendarMonth value) async {
    calendar = CalendarMonth(
      ownerId: uid,
      year: value.year,
      month: value.month,
      busyDays: value.busyDays,
      confirmedAt: DateTime.now(),
    );
  }

  @override
  Future<void> saveProfile(String uid, ProfileContent value) async =>
      savedContent = value;
  @override
  Future<void> moderateProfile(
    String actorId,
    String ownerId, {
    required bool approve,
    required String reason,
    required int expectedRevision,
  }) async {
    moderatedRevision = expectedRevision;
    moderatedReason = reason;
    if (throwModeration) {
      throw StateError('Версия изменилась. Обновите очередь проверки.');
    }
    profile = ContractorProfile(
      ownerId: ownerId,
      content: content,
      revision: expectedRevision + 1,
      status: approve ? 'approved' : 'changes_requested',
    );
  }

  @override
  Future<List<Account>> listAccounts() async => const [
    Account(
      uid: 'customer',
      name: 'Пользователь с длинным именем',
      email: 'event.organizer@example.com',
    ),
  ];
  @override
  Future<Map<String, StaffAccess>> listStaff() async => {};
  @override
  Future<List<AuditEntry>> listAudit() async => const [
    AuditEntry(
      id: '1',
      actorId: 'admin',
      action: 'publish',
      resourceType: 'profile',
      resourceId: 'supplier',
      revision: 4,
      reason: 'Данные проверены',
    ),
  ];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> pumpPage(
  WidgetTester tester,
  Widget child, {
  Size size = const Size(375, 900),
  double scale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: TextScaler.linear(scale),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: child,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('pending version cannot be edited until withdrawn', (
    tester,
  ) async {
    await pumpPage(
      tester,
      ContractorPage(
        repository: PortalRepository(),
        uid: 'supplier',
        section: 'profile',
      ),
    );
    expect(find.byType(TextFormField), findsNothing);
    expect(find.text('Отозвать и редактировать'), findsOneWidget);
    expect(
      find.textContaining('версия отправлена на проверку'),
      findsOneWidget,
    );
  });

  testWidgets('draft rejects insecure portfolio links before repository call', (
    tester,
  ) async {
    final repository = PortalRepository()..profile = null;
    await pumpPage(
      tester,
      ContractorPage(
        repository: repository,
        uid: 'supplier',
        section: 'profile',
      ),
    );
    final portfolio = find.widgetWithText(TextFormField, 'Ссылки на портфолио');
    await tester.ensureVisible(portfolio);
    await tester.enterText(portfolio, 'http://example.com/photos');
    final save = find.text('Сохранить черновик');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.textContaining('Используйте полные ссылки'), findsOneWidget);
    expect(repository.savedContent, isNull);
    await tester.enterText(portfolio, 'https://example.com/photos');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(repository.savedContent!.portfolioUrls, [
      'https://example.com/photos',
    ]);
  });

  testWidgets(
    'calendar persists selected busy days only after explicit confirmation',
    (tester) async {
      final repository = PortalRepository();
      await pumpPage(
        tester,
        ContractorPage(
          repository: repository,
          uid: 'supplier',
          section: 'calendar',
        ),
      );
      final saveFinder = find.widgetWithText(
        FilledButton,
        'Сохранить и подтвердить месяц',
      );
      expect(tester.widget<FilledButton>(saveFinder).onPressed, isNull);
      final day = find.widgetWithText(FilterChip, '12');
      await tester.ensureVisible(day);
      await tester.tap(day);
      await tester.pump();
      final confirm = find.byType(CheckboxListTile);
      await tester.ensureVisible(confirm);
      await tester.tap(confirm);
      await tester.pump();
      await tester.ensureVisible(saveFinder);
      await tester.tap(saveFinder);
      await tester.pumpAndSettle();
      expect(repository.calendar!.busyDays, [12]);
      expect(repository.calendar!.isFresh(DateTime.now()), isTrue);
      expect(tester.widget<CheckboxListTile>(confirm).value, isFalse);
    },
  );

  testWidgets(
    'moderation uses displayed revision and reports a concurrent decision',
    (tester) async {
      final repository = PortalRepository()..throwModeration = true;
      await pumpPage(
        tester,
        AdminPage(
          repository: repository,
          uid: 'admin',
          isAdmin: true,
          section: 'moderation',
        ),
      );
      final approve = find.text('Опубликовать версию 4');
      await tester.ensureVisible(approve);
      await tester.tap(approve);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Причина'),
        'Проверены услуги и контакты',
      );
      await tester.tap(find.text('Подтвердить'));
      await tester.pumpAndSettle();
      expect(repository.moderatedRevision, 4);
      expect(repository.moderatedReason, 'Проверены услуги и контакты');
      expect(
        find.text('Версия изменилась. Обновите очередь проверки.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('moderator does not request account or role records', (
    tester,
  ) async {
    await pumpPage(
      tester,
      AdminPage(
        repository: PortalRepository(),
        uid: 'mod',
        isAdmin: false,
        section: 'users',
      ),
    );
    expect(find.text('Только для администратора'), findsOneWidget);
    expect(find.text('event.organizer@example.com'), findsNothing);
  });

  for (final width in [375.0, 768.0, 1024.0, 1440.0]) {
    testWidgets('supplier and admin sections fit width $width', (tester) async {
      final repository = PortalRepository();
      for (final section in ['overview', 'profile', 'calendar', 'moderation']) {
        await pumpPage(
          tester,
          ContractorPage(
            repository: repository,
            uid: 'supplier',
            section: section,
          ),
          size: Size(width, 1100),
        );
        expect(tester.takeException(), isNull, reason: 'contractor $section');
      }
      for (final section in [
        'overview',
        'moderation',
        'contractors',
        'users',
        'quality',
        'audit',
      ]) {
        await pumpPage(
          tester,
          AdminPage(
            repository: repository,
            uid: 'admin',
            isAdmin: true,
            section: section,
          ),
          size: Size(width, 1100),
        );
        expect(tester.takeException(), isNull, reason: 'admin $section');
      }
    });
  }

  testWidgets('compact users view supports large text', (tester) async {
    await pumpPage(
      tester,
      AdminPage(
        repository: PortalRepository(),
        uid: 'admin',
        isAdmin: true,
        section: 'users',
      ),
      scale: 1.5,
    );
    expect(tester.takeException(), isNull);
  });
}
