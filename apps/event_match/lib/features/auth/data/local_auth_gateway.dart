import 'dart:async';
import '../../../core/local_api.dart';
import '../domain/auth_gateway.dart';

class LocalAuthGateway implements AuthGateway {
  LocalAuthGateway(this.api);
  final LocalApi api;
  final _events = StreamController<AuthIdentity?>.broadcast();
  AuthIdentity? _identity;
  @override
  AuthIdentity? get currentIdentity => _identity;
  @override
  Stream<AuthIdentity?> get identities async* {
    yield _identity;
    yield* _events.stream;
  }

  void _set(dynamic data) {
    _identity = data == null
        ? null
        : AuthIdentity(
            uid: data['uid'] as String,
            email: data['email'] as String,
            name: data['name'] as String,
            emailVerified: data['emailVerified'] == true,
          );
    _events.add(_identity);
  }

  Future<void> _login(Map<String, dynamic> input) async {
    try {
      final data = await api.post('/v1/auth', input);
      api.sessionToken = data['token'] as String;
      _set(data['identity']);
    } on LocalApiException catch (e) {
      throw AuthFailure(e.message);
    }
  }

  @override
  Future<void> signIn(String email, String password) =>
      _login({'op': 'login', 'email': email, 'password': password});
  @override
  Future<void> register(String email, String password, String name) => _login({
    'op': 'register',
    'email': email,
    'password': password,
    'name': name,
  });
  @override
  Future<void> reload() async {
    if (api.sessionToken == null) return;
    final data = await api.post('/v1/auth', {'op': 'session'});
    _set(data['identity']);
  }

  @override
  Future<void> updateName(String name) async {
    await api.workspace('updateName', {'name': name});
    await reload();
  }

  @override
  Future<void> signOut() async {
    await api.post('/v1/auth', {'op': 'logout'});
    api.sessionToken = null;
    _set(null);
  }

  @override
  Future<void> signInWithGoogle() async =>
      throw const AuthFailure('Google-вход не подключён к локальному серверу.');
  @override
  Future<void> sendVerification() async =>
      throw const AuthFailure('Почтовый сервис не подключён.');
  @override
  Future<void> resetPassword(String email) async =>
      throw const AuthFailure('Восстановление через email пока не подключено.');
  void dispose() => _events.close();
}
