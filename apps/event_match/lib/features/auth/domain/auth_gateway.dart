/// Authentication identity only. Permissions come from the account repository.
class AuthIdentity {
  const AuthIdentity({
    required this.uid,
    required this.email,
    required this.name,
    required this.emailVerified,
  });
  final String uid;
  final String email;
  final String name;
  final bool emailVerified;
}

abstract interface class AuthGateway {
  Stream<AuthIdentity?> get identities;
  AuthIdentity? get currentIdentity;
  Future<void> signIn(String email, String password);
  Future<void> register(String email, String password, String name);
  Future<void> signInWithGoogle();
  Future<void> sendVerification();
  Future<void> reload();
  Future<void> resetPassword(String email);
  Future<void> updateName(String name);
  Future<void> signOut();
}

class AuthFailure implements Exception {
  const AuthFailure(this.message);
  final String message;
  @override
  String toString() => message;
}
