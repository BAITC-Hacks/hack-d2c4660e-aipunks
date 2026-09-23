import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../domain/auth_gateway.dart';

class FirebaseAuthGateway implements AuthGateway {
  FirebaseAuthGateway(this._auth);
  final FirebaseAuth _auth;
  Future<void>? _googleInitialization;
  bool _googleUsed = false;
  bool _registering = false;

  AuthIdentity? _identity(User? user) => user == null || user.isAnonymous
      ? null
      : AuthIdentity(
          uid: user.uid,
          email: user.email ?? '',
          name: user.displayName ?? '',
          emailVerified: user.emailVerified,
        );
  @override
  AuthIdentity? get currentIdentity => _identity(_auth.currentUser);
  @override
  Stream<AuthIdentity?> get identities =>
      _auth.userChanges().where((_) => !_registering).map(_identity);
  @override
  Future<void> signIn(String email, String password) async {
    await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  @override
  Future<void> register(String email, String password, String name) async {
    _registering = true;
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      await credential.user!.updateDisplayName(name.trim());
      await credential.user!.sendEmailVerification();
    } finally {
      _registering = false;
      await _auth.currentUser?.reload();
    }
  }

  @override
  Future<void> signInWithGoogle() async {
    if (kIsWeb) {
      await _auth.signInWithPopup(GoogleAuthProvider());
      return;
    }
    const serverClientId = String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');
    if (serverClientId.isEmpty) {
      throw const AuthFailure(
        'Google-вход для Android ещё не настроен. Используйте email и пароль.',
      );
    }
    _googleInitialization ??= GoogleSignIn.instance.initialize(
      serverClientId: serverClientId,
    );
    await _googleInitialization;
    final user = await GoogleSignIn.instance.authenticate();
    _googleUsed = true;
    await _auth.signInWithCredential(
      GoogleAuthProvider.credential(idToken: user.authentication.idToken),
    );
  }

  @override
  Future<void> sendVerification() async =>
      _auth.currentUser?.sendEmailVerification();
  @override
  Future<void> reload() async {
    await _auth.currentUser?.reload();
    // Firestore must see the refreshed verified-email claim too.
    await _auth.currentUser?.getIdToken(true);
  }

  @override
  Future<void> resetPassword(String email) =>
      _auth.sendPasswordResetEmail(email: email.trim());
  @override
  Future<void> updateName(String name) async =>
      _auth.currentUser?.updateDisplayName(name.trim());
  @override
  Future<void> signOut() async {
    await _auth.signOut();
    if (!kIsWeb && _googleUsed) {
      await GoogleSignIn.instance.signOut();
      _googleUsed = false;
    }
  }
}

String authErrorMessage(Object error) {
  if (error is AuthFailure) return error.message;
  if (error is FirebaseAuthException) {
    return switch (error.code) {
      'invalid-email' => 'Проверьте адрес электронной почты.',
      'invalid-credential' ||
      'user-not-found' ||
      'wrong-password' => 'Не удалось войти. Проверьте email и пароль.',
      'email-already-in-use' =>
        'Этот email уже зарегистрирован. Войдите или восстановите пароль.',
      'weak-password' => 'Используйте пароль длиной не менее 8 символов.',
      'user-disabled' => 'Доступ к аккаунту приостановлен.',
      'too-many-requests' =>
        'Слишком много попыток. Подождите немного и повторите.',
      'network-request-failed' =>
        'Нет связи с сервером. Проверьте интернет и повторите.',
      'popup-closed-by-user' ||
      'cancelled-popup-request' => 'Окно Google закрыто. Можно повторить вход.',
      'popup-blocked' => 'Разрешите всплывающее окно Google и повторите вход.',
      'operation-not-allowed' || 'configuration-not-found' =>
        'Этот способ входа ещё не настроен. Попробуйте другой.',
      'account-exists-with-different-credential' =>
        'Войдите ранее выбранным способом для этого email.',
      _ => 'Не удалось выполнить действие (${error.code}). Повторите попытку.',
    };
  }
  if (error is FirebaseException) {
    return switch (error.code) {
      'permission-denied' =>
        'Доступ не разрешён. Обновите сессию и попробуйте ещё раз.',
      'resource-exhausted' =>
        'Сервис временно достиг лимита запросов. Попробуйте позже.',
      'unavailable' || 'deadline-exceeded' =>
        'Сервер недоступен. Проверьте соединение и повторите.',
      _ => 'Не удалось сохранить изменения (${error.code}). Повторите попытку.',
    };
  }
  if (error is GoogleSignInException) {
    return 'Google-вход не завершён. Повторите попытку или используйте email.';
  }
  return 'Не удалось выполнить действие. Повторите попытку.';
}
