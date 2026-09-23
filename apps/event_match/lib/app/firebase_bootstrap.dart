import 'package:event_match/l10n/app_localizations.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'app.dart';
import 'app_theme.dart';
import '../features/auth/data/firebase_auth_gateway.dart';
import '../features/auth/presentation/session_controller.dart';
import '../features/matching/data/catalog_repository.dart';
import '../features/matching/presentation/matching_screen.dart';
import '../features/workspace/data/firestore_workspace_repository.dart';
import '../firebase_options.dart';

bool _configured = false;

FirebaseOptions firebaseOptionsForEnvironment({
  required FirebaseOptions production,
  required bool useEmulators,
  String emulatorProjectId = 'demo-event-match',
}) {
  if (!useEmulators) return production;
  if (!RegExp(r'^demo-[a-z0-9-]+$').hasMatch(emulatorProjectId)) {
    throw ArgumentError('Локальный проект должен иметь идентификатор demo-…');
  }
  // Isolate emulator auth persistence and project data from the production app.
  // These dummy identifiers follow Firebase.initializeApp(demoProjectId: ...).
  return FirebaseOptions(
    apiKey: '12345',
    appId: production.appId.contains(':android:')
        ? '1:1:android:1'
        : '1:1:web:1',
    messagingSenderId: '',
    projectId: emulatorProjectId,
    authDomain: '$emulatorProjectId.firebaseapp.com',
  );
}

Future<SessionController> createFirebaseSession() async {
  if (!DefaultFirebaseOptions.isSupported) {
    throw UnsupportedError(
      'Кабинеты поддерживаются на Web и Android. На этой платформе доступно демо.',
    );
  }
  const useEmulators = bool.fromEnvironment('USE_FIREBASE_EMULATORS');
  // firebase_auth_web 6.3 reconnects a persisted debug emulator only on this
  // hostname. Other hosts otherwise lose auth on reload before configuration.
  if (kIsWeb && useEmulators && Uri.base.host != 'localhost') {
    throw UnsupportedError(
      'Для проверки Web с эмуляторами откройте ${Uri.base.replace(host: 'localhost')}. Адрес localhost нужен для сохранения входа после перезагрузки.',
    );
  }
  const emulatorProjectId = String.fromEnvironment(
    'FIREBASE_EMULATOR_PROJECT_ID',
    defaultValue: 'demo-event-match',
  );
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: firebaseOptionsForEnvironment(
        production: DefaultFirebaseOptions.currentPlatform,
        useEmulators: useEmulators,
        emulatorProjectId: emulatorProjectId,
      ),
    );
  }
  final auth = FirebaseAuth.instance;
  final db = FirebaseFirestore.instance;
  if (!_configured) {
    const configuredHost = String.fromEnvironment('FIREBASE_EMULATOR_HOST');
    final host = configuredHost.isNotEmpty
        ? configuredHost
        : !kIsWeb && defaultTargetPlatform == TargetPlatform.android
        ? '10.0.2.2'
        : '127.0.0.1';
    if (useEmulators) {
      await auth.useAuthEmulator(host, 9099);
      db.settings = Settings(
        persistenceEnabled: false,
        host: '$host:8080',
        sslEnabled: false,
      );
    } else {
      // Private event/profile data must not persist to a device disk cache.
      db.settings = const Settings(persistenceEnabled: false);
    }
    _configured = true;
  }
  return SessionController(
    auth: FirebaseAuthGateway(auth),
    repository: FirestoreWorkspaceRepository(db),
  );
}

/// Startup is injectable and retryable. A backend failure never silently swaps
/// a live catalogue for the demonstration dataset.
class FirebaseBootstrap extends StatefulWidget {
  const FirebaseBootstrap({
    super.key,
    this.createSession = createFirebaseSession,
  });
  final Future<SessionController> Function() createSession;
  @override
  State<FirebaseBootstrap> createState() => _FirebaseBootstrapState();
}

class _FirebaseBootstrapState extends State<FirebaseBootstrap> {
  late Future<SessionController> _future;
  late final String _initialLocation;
  SessionController? _session;
  bool _demo = false;
  @override
  void initState() {
    super.initState();
    _initialLocation =
        WidgetsBinding.instance.platformDispatcher.defaultRouteName;
    _future = _start();
  }

  Future<SessionController> _start() {
    final future = _load();
    // A retry can fail before the next frame attaches FutureBuilder. Install an
    // immediate observer while preserving the failed future for the error UI.
    unawaited(future.then<void>((_) {}, onError: (Object _, StackTrace _) {}));
    return future;
  }

  Future<SessionController> _load() async {
    final session = await widget.createSession();
    if (!mounted) {
      session.dispose();
      return session;
    }
    _session = session;
    return session;
  }

  @override
  void dispose() {
    _session?.dispose();
    super.dispose();
  }

  void _retry() {
    setState(() {
      _demo = false;
      _session?.dispose();
      _session = null;
      _future = _start();
    });
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<SessionController>(
    future: _future,
    builder: (context, snapshot) {
      if (!_demo && snapshot.hasData) {
        return EventMatchApp(
          session: snapshot.data!,
          workspace: snapshot.data!.repository,
          initialLocation: _initialLocation,
        );
      }
      return MaterialApp(
        title: 'Event Match',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        locale: const Locale('ru'),
        supportedLocales: const [Locale('ru')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        // The bootstrap UI must not install a Navigator: its initial `/` route
        // would overwrite a browser deep link before GoRouter is ready.
        builder: _demo
            ? null
            : (context, _) => _startupScreen(context, snapshot),
        initialRoute: _demo ? '/' : null,
        home: _demo ? _startupScreen(context, snapshot) : null,
      );
    },
  );
  Widget _startupScreen(
    BuildContext context,
    AsyncSnapshot<SessionController> snapshot,
  ) => Scaffold(
    appBar: AppBar(
      title: Text(_demo ? 'Event Match · демо' : 'Event Match'),
      actions: [
        if (_demo)
          TextButton(
            onPressed: _retry,
            child:  Text(tr(context, 'Вернуться ко входу')),
          ),
      ],
    ),
    body: _demo
        ? MatchingScreen(repository: AssetCatalogRepository())
        : Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!snapshot.hasError) ...[
                      const Center(child: CircularProgressIndicator()),
                      const SizedBox(height: 24),
                       Text(
                        tr(context, 'Подключаем Event Match…'),
                        textAlign: TextAlign.center,
                      ),
                    ] else ...[
                      Text(
                        'Не удалось подключить сервис',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        snapshot.error is UnsupportedError
                            ? (snapshot.error! as UnsupportedError).message ??
                                  'Платформа не поддерживается.'
                            : 'Проверьте соединение и повторите. Данные аккаунтов и живой каталог загружаются через Firebase.',
                      ),
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: _retry,
                        child:  Text(tr(context, 'Повторить')),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: () => setState(() => _demo = true),
                        child:  Text(tr(context, 'Открыть демо-каталог')),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
  );
}
