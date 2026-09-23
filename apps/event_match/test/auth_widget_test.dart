import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:event_match/features/auth/presentation/auth_pages.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:event_match/app/app.dart';
import 'package:event_match/main.dart'
    show FirebaseBootstrap, firebaseOptionsForEnvironment;
import 'package:event_match/firebase_options.dart';
import 'package:event_match/features/workspace/domain/workspace_models.dart';
import 'package:event_match/features/auth/domain/auth_gateway.dart';
import 'package:event_match/features/auth/presentation/session_controller.dart';
import 'auth_session_test.dart' show FakeAuthGateway, SessionRepository, alice;

void main() {
  test(
    'emulator options use a separate demo project and dummy credentials',
    () {
      final live = DefaultFirebaseOptions.web;
      expect(
        firebaseOptionsForEnvironment(production: live, useEmulators: false),
        same(live),
      );
      final local = firebaseOptionsForEnvironment(
        production: live,
        useEmulators: true,
      );
      expect(local.projectId, 'demo-event-match');
      expect(local.apiKey, isNot(live.apiKey));
      expect(local.appId, '1:1:web:1');
      expect(
        () => firebaseOptionsForEnvironment(
          production: live,
          useEmulators: true,
          emulatorProjectId: 'hackalem-84547',
        ),
        throwsArgumentError,
      );
    },
  );
  for (final size in [
    const Size(375, 812),
    const Size(768, 1024),
    const Size(1024, 768),
    const Size(1440, 900),
  ]) {
    testWidgets('auth and account settings fit $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final auth = FakeAuthGateway();
      final repo = SessionRepository();
      final session = SessionController(auth: auth, repository: repo);
      addTearDown(session.dispose);
      await tester.pumpWidget(
        EventMatchApp(
          session: session,
          workspace: repo,
          initialLocation: '/auth?returnTo=%2Fsettings',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('С возвращением'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('auth-submit')));
      await tester.tap(find.byKey(const Key('auth-submit')));
      await tester.pumpAndSettle();
      expect(find.text('Введите корректный email'), findsOneWidget);
      expect(find.text('Введите пароль'), findsOneWidget);
      auth.emit(alice);
      await tester.pumpAndSettle();
      expect(find.text('Настройки аккаунта'), findsOneWidget);
      expect(find.text('Email подтверждён'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await auth.changes.close();
      await repo.accountChanges.close();
      await repo.roleChanges.close();
    });
  }
  testWidgets('unverified sign in returns to verification and can resend', (
    tester,
  ) async {
    final auth = FakeAuthGateway();
    final repo = SessionRepository();
    final session = SessionController(auth: auth, repository: repo);
    addTearDown(session.dispose);
    await tester.pumpWidget(
      EventMatchApp(
        session: session,
        workspace: repo,
        initialLocation: '/contractor/calendar',
      ),
    );
    await tester.pumpAndSettle();
    auth.emit(
      const AuthIdentity(
        uid: 'unverified',
        email: 'u@example.com',
        name: 'U',
        emailVerified: false,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Подтвердите почту'), findsOneWidget);
    await tester.tap(find.text('Отправить письмо ещё раз'));
    await tester.pumpAndSettle();
    expect(auth.verificationSent, isTrue);
    expect(
      find.text('Письмо отправлено повторно. Проверьте также папку «Спам».'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
    await auth.changes.close();
    await repo.accountChanges.close();
    await repo.roleChanges.close();
  });
  testWidgets('recovery validates email and requests reset', (tester) async {
    final auth = FakeAuthGateway();
    final repo = SessionRepository();
    final session = SessionController(auth: auth, repository: repo);
    addTearDown(session.dispose);
    await tester.pumpWidget(
      EventMatchApp(
        session: session,
        workspace: repo,
        initialLocation: '/auth',
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Забыли пароль?'));
    await tester.tap(find.text('Забыли пароль?'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('auth-email')),
      'user@example.com',
    );
    await tester.tap(find.byKey(const Key('auth-submit')));
    await tester.pumpAndSettle();
    expect(auth.resetRequested, isTrue);
    expect(find.textContaining('Если аккаунт с таким email'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await auth.changes.close();
    await repo.accountChanges.close();
    await repo.roleChanges.close();
  });
  testWidgets('startup failure offers explicit demo and a working retry', (
    tester,
  ) async {
    var attempts = 0;
    Future<SessionController> failStartup() async {
      attempts++;
      throw StateError('offline');
    }

    await tester.pumpWidget(FirebaseBootstrap(createSession: failStartup));
    await tester.pumpAndSettle();
    expect(find.text('Не удалось подключить сервис'), findsOneWidget);
    expect(find.text('Каталог · 66 профилей'), findsNothing);
    await tester.tap(find.text('Повторить'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    await tester.tap(find.text('Открыть демо-каталог'));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Event Match · демо'), findsOneWidget);
    expect(find.text('Каталог · 66 профилей'), findsOneWidget);
  });
  testWidgets('auth supports large text and reduced motion on a small phone', (
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
    final auth = FakeAuthGateway();
    final repo = SessionRepository();
    final session = SessionController(auth: auth, repository: repo);
    addTearDown(session.dispose);
    await tester.pumpWidget(
      EventMatchApp(
        session: session,
        workspace: repo,
        initialLocation: '/auth?returnTo=%2Fsettings',
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    auth.emit(alice);
    await tester.pumpAndSettle();
    expect(find.text('Настройки аккаунта'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await auth.changes.close();
    await repo.accountChanges.close();
    await repo.roleChanges.close();
  });
  testWidgets('administrator settings explain protected account controls', (
    tester,
  ) async {
    final auth = FakeAuthGateway()..identity = alice;
    final repo = SessionRepository();
    repo.roles[alice.uid] = const StaffAccess(role: 'admin', revision: 1);
    final session = SessionController(auth: auth, repository: repo);
    addTearDown(session.dispose);
    await tester.pumpWidget(
      EventMatchApp(
        session: session,
        workspace: repo,
        initialLocation: '/settings',
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Аккаунт администратора защищён'),
      findsOneWidget,
    );
    expect(find.text('Деактивировать аккаунт'), findsNothing);
    expect(find.text('Запросить удаление всех данных'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await auth.changes.close();
    await repo.accountChanges.close();
    await repo.roleChanges.close();
  });
  for (final destination in [
    '/client/selections',
    '/client/selections?event=event-42',
  ]) {
    testWidgets('cold bootstrap preserves $destination through auth redirect', (
      tester,
    ) async {
      tester.platformDispatcher.defaultRouteNameTestValue = destination;
      addTearDown(tester.platformDispatcher.clearDefaultRouteNameTestValue);
      final ready = Completer<SessionController>();
      final auth = FakeAuthGateway();
      final repo = SessionRepository();
      await tester.pumpWidget(
        FirebaseBootstrap(createSession: () => ready.future),
      );
      await tester.pump();
      expect(find.text('Подключаем Event Match…'), findsOneWidget);
      expect(find.byType(Navigator), findsNothing);
      expect(tester.takeException(), isNull);
      // Model a browser platform route changing while initialization is pending.
      // The app must use its captured cold-start target, including the query.
      tester.platformDispatcher.defaultRouteNameTestValue = '/';
      ready.complete(SessionController(auth: auth, repository: repo));
      await tester.pumpAndSettle();
      final router = GoRouter.of(tester.element(find.byType(AuthPage)));
      expect(router.routeInformationProvider.value.uri.path, '/auth');
      expect(
        router.routeInformationProvider.value.uri.queryParameters['returnTo'],
        destination,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await auth.changes.close();
      await repo.accountChanges.close();
      await repo.roleChanges.close();
    });
  }
}
