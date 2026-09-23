import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../workspace/domain/workspace_models.dart';
import '../../workspace/domain/workspace_repository.dart';
import '../data/firebase_auth_gateway.dart';
import '../domain/auth_gateway.dart';

/// Owns the three session subscriptions. Private page state is keyed by [epoch]
/// so identity changes and loss of access dispose all account-specific views.
class SessionController extends ChangeNotifier {
  SessionController({
    required this.auth,
    required this.repository,
    this.requireEmailVerification = true,
  }) {
    _identitySubscription = auth.identities.listen(
      _acceptIdentity,
      onError: _fail,
    );
  }
  final AuthGateway auth;
  final WorkspaceRepository repository;
  final bool requireEmailVerification;
  StreamSubscription<AuthIdentity?>? _identitySubscription;
  StreamSubscription<Account?>? _accountSubscription;
  StreamSubscription<StaffAccess?>? _staffSubscription;
  AuthIdentity? identity;
  Account? account;
  StaffAccess? staff;
  bool loading = true;
  String? error;
  int epoch = 0;
  int _generation = 0;
  bool _disposed = false;
  bool _staffLoaded = false;

  String? get uid => identity?.uid;
  bool get isVerified =>
      identity != null &&
      (!requireEmailVerification || identity!.emailVerified);
  bool get isActive => account?.isActive ?? false;
  bool get canUseWorkspace =>
      !loading && error == null && isVerified && isActive;
  bool get isAdmin => canUseWorkspace && (staff?.isAdmin ?? false);
  bool get isStaff => canUseWorkspace && (staff?.isStaff ?? false);

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  void _fail(Object exception) {
    if (_disposed) return;
    error = authErrorMessage(exception);
    account = null;
    staff = null;
    loading = false;
    epoch++;
    _changed();
  }

  Future<void> _acceptIdentity(AuthIdentity? next) async {
    if (_disposed) return;
    final generation = ++_generation;
    epoch++;
    identity = next;
    account = null;
    staff = null;
    _staffLoaded = false;
    error = null;
    loading = next != null;
    _changed();
    await _accountSubscription?.cancel();
    await _staffSubscription?.cancel();
    _accountSubscription = null;
    _staffSubscription = null;
    if (_disposed || generation != _generation || next == null) return;
    try {
      await repository.ensureAccount(
        next.uid,
        next.name,
        next.email,
        accountType: next.accountType,
      );
      if (_disposed || generation != _generation) return;
      _accountSubscription = repository
          .watchAccount(next.uid)
          .listen(
            (value) {
              if (_disposed || generation != _generation) return;
              final previouslyActive = account?.isActive ?? false;
              account = value;
              if (value == null) {
                _fail(
                  const AuthFailure(
                    'Не удалось загрузить аккаунт. Повторите подключение.',
                  ),
                );
                return;
              }
              if (!value.isActive ||
                  (requireEmailVerification && !next.emailVerified)) {
                if (previouslyActive && !value.isActive) epoch++;
                _staffSubscription?.cancel();
                _staffSubscription = null;
                staff = null;
                loading = false;
              } else if (_staffSubscription == null) {
                loading = true;
                _staffLoaded = false;
                _staffSubscription = repository
                    .watchStaff(next.uid)
                    .listen(
                      (access) {
                        if (_disposed ||
                            generation != _generation ||
                            account?.isActive != true) {
                          return;
                        }
                        final previousRole = staff?.role;
                        staff = access;
                        if (previousRole != null &&
                            previousRole != access?.role) {
                          epoch++;
                        }
                        _staffLoaded = true;
                        loading = false;
                        _changed();
                      },
                      onError: (Object exception) {
                        if (generation == _generation) _fail(exception);
                      },
                    );
              } else {
                loading = !_staffLoaded;
              }
              _changed();
            },
            onError: (Object exception) {
              if (generation == _generation) _fail(exception);
            },
          );
    } catch (exception) {
      if (generation == _generation) _fail(exception);
    }
  }

  Future<void> refresh() async {
    await auth.reload();
    await _acceptIdentity(auth.currentIdentity);
  }

  Future<void> retry() => _acceptIdentity(auth.currentIdentity);
  Future<void> signOut() async {
    // Clear protected UI immediately, rather than waiting for the auth stream.
    await _acceptIdentity(null);
    try {
      await auth.signOut();
    } catch (exception) {
      await _acceptIdentity(auth.currentIdentity);
      rethrow;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _identitySubscription?.cancel();
    _accountSubscription?.cancel();
    _staffSubscription?.cancel();
    super.dispose();
  }
}

/// Return targets are deliberately local, with no authority/scheme. This also
/// prevents login loops through /auth, /verify or the session-error route.
String safeReturnTarget(String? raw) {
  if (raw == null) return '/client/events';
  final uri = Uri.tryParse(raw);
  if (uri == null ||
      uri.hasScheme ||
      uri.hasAuthority ||
      !raw.startsWith('/') ||
      raw.startsWith('//')) {
    return '/client/events';
  }
  if (uri.path == '/' ||
      uri.path == '/catalog' ||
      uri.path == '/demo' ||
      uri.path == '/assistant' ||
      uri.path == '/settings' ||
      uri.path.startsWith('/client/') ||
      uri.path.startsWith('/contractor/') ||
      uri.path.startsWith('/admin/')) {
    return uri.toString();
  }
  return switch (uri.path) {
    '/client' => '/client/events',
    '/contractor' => '/contractor/overview',
    '/admin' => '/admin/overview',
    _ => '/client/events',
  };
}

String? sessionRedirect(SessionController session, Uri uri) {
  final path = uri.path;
  final public =
      path == '/' ||
      path == '/demo' ||
      path == '/assistant' ||
      path == '/catalog';
  if (public) return null;
  final target = safeReturnTarget(uri.queryParameters['returnTo']);
  String carry(String route, String destination) =>
      Uri(path: route, queryParameters: {'returnTo': destination}).toString();
  final currentTarget =
      {'/auth', '/verify', '/session', '/restricted'}.contains(path)
      ? target
      : safeReturnTarget(uri.toString());
  if (session.loading) {
    return path == '/session' ? null : carry('/session', currentTarget);
  }
  if (session.identity == null) {
    return path == '/auth' ? null : carry('/auth', currentTarget);
  }
  if (session.error != null) {
    return path == '/session' ? null : carry('/session', currentTarget);
  }
  if (!session.isActive) return path == '/restricted' ? null : '/restricted';
  if (!session.isVerified) {
    return path == '/verify' ? null : carry('/verify', currentTarget);
  }
  if (path.startsWith('/admin') && !session.isStaff) return '/client/events';
  if (path == '/admin/users' && !session.isAdmin) return '/admin/overview';
  if ({'/auth', '/verify', '/session', '/restricted'}.contains(path)) {
    if (target.startsWith('/admin') && !session.isStaff) {
      return '/client/events';
    }
    return target == '/client/events' &&
            session.account?.accountType == 'contractor'
        ? '/contractor/overview'
        : target;
  }
  return null;
}
