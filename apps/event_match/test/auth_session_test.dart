import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:event_match/features/auth/domain/auth_gateway.dart';
import 'package:event_match/features/auth/presentation/session_controller.dart';
import 'package:event_match/features/workspace/domain/workspace_models.dart';
import 'package:event_match/features/workspace/domain/workspace_repository.dart';

class FakeAuthGateway implements AuthGateway {
  final changes = StreamController<AuthIdentity?>.broadcast();
  AuthIdentity? identity;
  String? registeredType;
  bool resetRequested = false;
  bool verificationSent = false;
  @override
  AuthIdentity? get currentIdentity => identity;
  @override
  Stream<AuthIdentity?> get identities async* {
    yield identity;
    yield* changes.stream;
  }

  void emit(AuthIdentity? next) {
    identity = next;
    changes.add(next);
  }

  @override
  Future<void> signOut() async => emit(null);
  @override
  Future<void> reload() async {}
  @override
  Future<void> sendVerification() async {
    verificationSent = true;
  }

  @override
  Future<void> resetPassword(String email) async {
    resetRequested = true;
  }

  @override
  Future<void> updateName(String name) async {}
  @override
  Future<void> signIn(String email, String password) async {}
  @override
  Future<void> register(
    String email,
    String password,
    String name, {
    String accountType = 'client',
  }) async {
    registeredType = accountType;
  }

  @override
  Future<void> signInWithGoogle() async {}
}

class SessionRepository extends WorkspaceRepository {
  final accounts = <String, Account>{};
  final roles = <String, StaffAccess>{};
  final accountChanges = StreamController<Account>.broadcast();
  final roleChanges =
      StreamController<MapEntry<String, StaffAccess>>.broadcast();
  final ensures = <String>[];
  Completer<void>? pendingEnsure;
  int staffReads = 0;
  @override
  Future<void> ensureAccount(
    String uid,
    String name,
    String email, {
    String accountType = 'client',
  }) async {
    ensures.add(uid);
    await pendingEnsure?.future;
    accounts.putIfAbsent(
      uid,
      () =>
          Account(uid: uid, name: name, email: email, accountType: accountType),
    );
  }

  @override
  Stream<Account?> watchAccount(String uid) async* {
    yield accounts[uid];
    yield* accountChanges.stream.where((a) => a.uid == uid);
  }

  @override
  Stream<StaffAccess?> watchStaff(String uid) async* {
    staffReads++;
    yield roles[uid];
    yield* roleChanges.stream.where((r) => r.key == uid).map((r) => r.value);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const alice = AuthIdentity(
  uid: 'alice',
  email: 'alice@example.com',
  name: 'Alice',
  emailVerified: true,
);
const bob = AuthIdentity(
  uid: 'bob',
  email: 'bob@example.com',
  name: 'Bob',
  emailVerified: true,
);
Future<void> flush() async {
  for (var i = 0; i < 6; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late FakeAuthGateway auth;
  late SessionRepository repo;
  late SessionController session;
  setUp(() async {
    auth = FakeAuthGateway();
    repo = SessionRepository();
    session = SessionController(auth: auth, repository: repo);
    await flush();
  });
  tearDown(() async {
    session.dispose();
    await auth.changes.close();
    await repo.accountChanges.close();
    await repo.roleChanges.close();
  });

  test(
    'contractor registration persists preferred cabinet without staff access',
    () async {
      auth.emit(
        const AuthIdentity(
          uid: 'maker',
          email: 'maker@example.com',
          name: 'Maker',
          emailVerified: true,
          accountType: 'contractor',
        ),
      );
      await flush();
      expect(repo.accounts['maker']!.accountType, 'contractor');
      expect(
        sessionRedirect(session, Uri.parse('/auth')),
        '/contractor/overview',
      );
      expect(
        sessionRedirect(session, Uri.parse('/auth?returnTo=%2Fsettings')),
        '/settings',
      );
      expect(session.isStaff, isFalse);
      await auth.signOut();
      await flush();
      auth.emit(
        const AuthIdentity(
          uid: 'maker',
          email: 'maker@example.com',
          name: 'Maker',
          emailVerified: true,
        ),
      );
      await flush();
      expect(
        sessionRedirect(session, Uri.parse('/auth')),
        '/contractor/overview',
      );
    },
  );
  test(
    'guest never creates account; protected destination is retained',
    () async {
      await flush();
      expect(repo.ensures, isEmpty);
      expect(
        sessionRedirect(session, Uri.parse('/client/favorites')),
        '/auth?returnTo=%2Fclient%2Ffavorites',
      );
      expect(sessionRedirect(session, Uri.parse('/')), isNull);
      expect(sessionRedirect(session, Uri.parse('/assistant')), isNull);
    },
  );
  test(
    'unverified identity cannot read staff or enter either cabinet',
    () async {
      auth.emit(
        const AuthIdentity(
          uid: 'alice',
          email: 'a@example.com',
          name: 'A',
          emailVerified: false,
        ),
      );
      await flush();
      expect(session.isActive, isTrue);
      expect(session.canUseWorkspace, isFalse);
      expect(repo.staffReads, 0);
      expect(
        sessionRedirect(session, Uri.parse('/contractor/profile')),
        '/verify?returnTo=%2Fcontractor%2Fprofile',
      );
      auth.emit(alice);
      await flush();
      expect(session.canUseWorkspace, isTrue);
      expect(
        sessionRedirect(
          session,
          Uri.parse('/verify?returnTo=%2Fcontractor%2Fprofile'),
        ),
        '/contractor/profile',
      );
    },
  );
  test(
    'roles are server sourced and revocation disposes private views',
    () async {
      repo.roles['alice'] = const StaffAccess(role: 'moderator', revision: 1);
      auth.emit(alice);
      await flush();
      expect(session.isStaff, isTrue);
      expect(session.isAdmin, isFalse);
      final epoch = session.epoch;
      repo.roleChanges.add(
        const MapEntry('alice', StaffAccess(role: 'none', revision: 2)),
      );
      await flush();
      expect(session.isStaff, isFalse);
      expect(session.epoch, greaterThan(epoch));
      expect(
        sessionRedirect(session, Uri.parse('/admin/moderation')),
        '/client/events',
      );
    },
  );
  test(
    'suspension clears staff and prevents protected navigation immediately',
    () async {
      repo.roles['alice'] = const StaffAccess(role: 'admin');
      auth.emit(alice);
      await flush();
      final epoch = session.epoch;
      repo.accountChanges.add(
        const Account(
          uid: 'alice',
          name: 'A',
          email: 'a@example.com',
          status: 'suspended',
        ),
      );
      await flush();
      expect(session.staff, isNull);
      expect(session.canUseWorkspace, isFalse);
      expect(session.epoch, greaterThan(epoch));
      expect(
        sessionRedirect(session, Uri.parse('/client/events')),
        '/restricted',
      );
    },
  );
  test(
    'late previous-user load cannot leak account into a new session',
    () async {
      final pending = Completer<void>();
      repo.pendingEnsure = pending;
      auth.emit(alice);
      await flush();
      auth.emit(bob);
      await flush();
      pending.complete();
      await flush();
      expect(session.uid, 'bob');
      expect(session.account?.uid, 'bob');
      await session.signOut();
      expect(session.account, isNull);
      expect(session.staff, isNull);
      expect(session.identity, isNull);
    },
  );
  test('safe redirects reject external destinations and auth loops', () {
    for (final path in [
      'https://evil.test',
      '//evil.test',
      '/auth',
      '/verify',
      '/session',
      'javascript:alert(1)',
    ]) {
      expect(safeReturnTarget(path), '/client/events');
    }
    expect(safeReturnTarget('/contractor/profile'), '/contractor/profile');
    expect(safeReturnTarget('/?save=selection'), '/?save=selection');
  });
}
