import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import '../features/auth/presentation/auth_pages.dart';
import '../features/auth/presentation/session_controller.dart';
import '../features/auth/presentation/settings_page.dart';
import '../features/matching/data/catalog_repository.dart';
import '../features/matching/presentation/matching_screen.dart';
import '../features/matching/domain/recommendation_service.dart';
import '../features/workspace/domain/workspace_repository.dart';
import '../features/workspace/presentation/admin_page.dart';
import '../features/workspace/presentation/catalog_page.dart';
import '../features/workspace/presentation/client_page.dart';
import '../features/workspace/presentation/contractor_page.dart';
import 'account_shell.dart';
import 'app_theme.dart';

/// Supplying [repository] preserves the isolated demo application for previews
/// and existing matching tests. Production always supplies session + workspace.
class EventMatchApp extends StatefulWidget {
  const EventMatchApp({
    super.key,
    this.repository,
    this.recommendationService,
    this.session,
    this.workspace,
    this.initialLocation,
  });
  final CatalogRepository? repository;
  final RecommendationService? recommendationService;
  final SessionController? session;
  final WorkspaceRepository? workspace;
  final String? initialLocation;
  @override
  State<EventMatchApp> createState() => _EventMatchAppState();
}

class _EventMatchAppState extends State<EventMatchApp> {
  GoRouter? _router;
  final CatalogRepository _demoRepository = AssetCatalogRepository();
  @override
  void initState() {
    super.initState();
    if (widget.session != null && widget.workspace != null) {
      _router = _createRouter();
    }
  }

  GoRouter _createRouter() {
    final session = widget.session!;
    final workspace = widget.workspace!;
    Widget settings() => SettingsPage(session: session, repository: workspace);
    return GoRouter(
      initialLocation: widget.initialLocation,
      overridePlatformDefaultLocation: widget.initialLocation != null,
      refreshListenable: session,
      redirect: (context, state) => sessionRedirect(session, state.uri),
      errorBuilder: (context, state) => Scaffold(
        appBar: AppBar(title: const Text('Event Match')),
        body: Center(
          child: FilledButton(
            onPressed: () => context.go('/'),
            child: const Text('Страница не найдена. Открыть каталог'),
          ),
        ),
      ),
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => AnimatedBuilder(
            animation: session,
            builder: (context, _) => _PublicFrame(
              session: session,
              selected: '/',
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1200),
                    child: CatalogPage(
                      repository: workspace,
                      uid: session.canUseWorkspace ? session.uid : null,
                      onRequireSignIn: () => context.go(
                        Uri(
                          path: '/auth',
                          queryParameters: {'returnTo': state.uri.toString()},
                        ).toString(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/demo',
          builder: (context, state) => _PublicFrame(
            session: session,
            selected: '/demo',
            child: MatchingScreen(
              repository: _demoRepository,
              service: widget.recommendationService,
            ),
          ),
        ),
        GoRoute(
          path: '/auth',
          builder: (context, state) => AuthPage(
            auth: session.auth,
            returnTo: safeReturnTarget(state.uri.queryParameters['returnTo']),
          ),
        ),
        GoRoute(
          path: '/verify',
          builder: (context, state) =>
              VerifyEmailPage(auth: session.auth, onRefresh: session.refresh),
        ),
        GoRoute(
          path: '/session',
          builder: (context, state) => _SessionStatePage(session: session),
        ),
        GoRoute(
          path: '/restricted',
          builder: (context, state) =>
              _SessionStatePage(session: session, restricted: true),
        ),
        GoRoute(
          path: '/client',
          redirect: (context, state) => '/client/events',
        ),
        GoRoute(
          path: '/contractor',
          redirect: (context, state) => '/contractor/overview',
        ),
        GoRoute(
          path: '/admin',
          redirect: (context, state) => '/admin/overview',
        ),
        ShellRoute(
          builder: (context, state, child) => AccountShell(
            session: session,
            location: state.uri.path,
            child: child,
          ),
          routes: [
            GoRoute(path: '/settings', builder: (context, state) => settings()),
            GoRoute(
              path: '/client/:section',
              builder: (context, state) {
                final section = state.pathParameters['section']!;
                return section == 'settings'
                    ? settings()
                    : ClientPage(
                        key: ValueKey('client:$section'),
                        repository: workspace,
                        uid: session.uid!,
                        section: section,
                      );
              },
            ),
            GoRoute(
              path: '/contractor/:section',
              builder: (context, state) {
                final section = state.pathParameters['section']!;
                return section == 'settings'
                    ? settings()
                    : ContractorPage(
                        key: ValueKey('contractor:$section'),
                        repository: workspace,
                        uid: session.uid!,
                        section: section,
                      );
              },
            ),
            GoRoute(
              path: '/admin/:section',
              builder: (context, state) => AdminPage(
                key: ValueKey('admin:${state.pathParameters['section']}'),
                repository: workspace,
                uid: session.uid!,
                isAdmin: session.isAdmin,
                section: state.pathParameters['section']!,
              ),
            ),
          ],
        ),
      ],
    );
  }

  @override
  void dispose() {
    _router?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_router != null) {
      return MaterialApp.router(
        title: 'Event Match',
        debugShowCheckedModeBanner: false,
        locale: const Locale('ru'),
        supportedLocales: const [Locale('ru')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: AppTheme.light,
        routerConfig: _router,
      );
    }
    return MaterialApp(
      title: 'Event Match',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ru'),
      supportedLocales: const [Locale('ru')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: AppTheme.light,
      home: MatchingScreen(
        repository: widget.repository ?? AssetCatalogRepository(),
        service: widget.recommendationService,
      ),
    );
  }
}

class _PublicFrame extends StatelessWidget {
  const _PublicFrame({
    required this.session,
    required this.selected,
    required this.child,
  });
  final SessionController session;
  final String selected;
  final Widget child;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Column(
        children: [
          Material(
            color: Theme.of(context).colorScheme.surface,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    'Event Match',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  TextButton(
                    onPressed: () => context.go('/'),
                    child: Text(selected == '/' ? 'Каталог · live' : 'Каталог'),
                  ),
                  TextButton(
                    onPressed: () => context.go('/demo'),
                    child: const Text('Демо-каталог'),
                  ),
                  FilledButton.tonal(
                    onPressed: () => context.go(
                      session.identity == null ? '/auth' : '/client/events',
                    ),
                    child: Text(
                      session.identity == null ? 'Войти' : 'Мой кабинет',
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (selected != '/')
            Container(
              width: double.infinity,
              color: Theme.of(context).colorScheme.secondaryContainer,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: const Text(
                'Демонстрационные анкеты и даты 23.09–31.12.2026. Они не принадлежат зарегистрированным подрядчикам.',
                textAlign: TextAlign.center,
              ),
            ),
          Expanded(child: child),
        ],
      ),
    ),
  );
}

class _SessionStatePage extends StatelessWidget {
  const _SessionStatePage({required this.session, this.restricted = false});
  final SessionController session;
  final bool restricted;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: session,
    builder: (context, _) => AuthFrame(
      title: restricted
          ? session.account?.status == 'deactivated'
                ? 'Аккаунт деактивирован'
                : 'Доступ приостановлен'
          : session.loading
          ? 'Подключаем аккаунт'
          : 'Не удалось подключиться',
      subtitle: restricted
          ? session.account?.deletionRequested == true
                ? 'Запрос на удаление данных сохранён. Команда Event Match обработает его служебным инструментом.'
                : 'Кабинеты сейчас недоступны. Обратитесь к команде Event Match для уточнения статуса.'
          : session.error ?? 'Загружаем ваши права доступа.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (session.loading) const Center(child: CircularProgressIndicator()),
          if (!session.loading && !restricted)
            FilledButton(
              onPressed: session.retry,
              child: const Text('Повторить подключение'),
            ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () => context.go('/'),
            child: const Text('Открыть каталог'),
          ),
          TextButton(
            onPressed: session.signOut,
            child: const Text('Выйти из аккаунта'),
          ),
        ],
      ),
    ),
  );
}
