import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import '../features/assistant/presentation/assistant_host.dart';
import '../features/auth/presentation/auth_pages.dart';
import '../features/auth/presentation/session_controller.dart';
import '../features/auth/presentation/settings_page.dart';
import '../features/matching/data/catalog_repository.dart';
import '../features/matching/presentation/matching_screen.dart';
import '../features/matching/domain/recommendation_service.dart';
import '../features/matching/domain/models.dart';
import '../features/planning/data/firestore_event_plan_repository.dart';
import '../features/planning/domain/event_plan_repository.dart';
import '../features/planning/presentation/event_plan_page.dart';
import '../features/workspace/domain/workspace_repository.dart';
import '../features/workspace/presentation/admin_page.dart';
import '../features/workspace/presentation/catalog_page.dart';
import '../features/workspace/presentation/client_page.dart';
import '../features/workspace/presentation/contractor_page.dart';
import 'account_shell.dart';
import 'app_theme.dart';
import 'communication_scope.dart';
import '../features/assistant/domain/assistant_service.dart';
import '../features/messages/messages_panel.dart';
import '../features/matching/data/favorites_repository.dart';
import '../features/matching/presentation/widgets/side_panel.dart';

/// Supplying [repository] preserves the isolated demo application for previews
/// and existing matching tests. Production always supplies session + workspace.
class EventMatchApp extends StatefulWidget {
  const EventMatchApp({
    super.key,
    this.repository,
    this.recommendationService,
    this.session,
    this.workspace,
    this.plans,
    this.initialLocation,
    this.favoritesRepository,
    this.assistantService,
    this.messagesRepository,
  });
  final CatalogRepository? repository;
  final RecommendationService? recommendationService;
  final SessionController? session;
  final WorkspaceRepository? workspace;
  final EventPlanRepository? plans;
  final String? initialLocation;
  final FavoritesRepository? favoritesRepository;
  final AssistantService? assistantService;
  final MessagesRepository? messagesRepository;
  @override
  State<EventMatchApp> createState() => _EventMatchAppState();
}

class _EventMatchAppState extends State<EventMatchApp> {
  GoRouter? _router;
  EventPlanRepository? _plans;
  late final CatalogRepository _demoRepository =
      widget.repository ?? AssetCatalogRepository();
  AssistantSession? _assistantSession;
  String? _assistantUid;
  @override
  void initState() {
    super.initState();
    _assistantUid = widget.session?.uid;
    widget.session?.addListener(_identityChanged);
    if (widget.session != null && widget.workspace != null) {
      _router = _createRouter();
    }
  }

  void _identityChanged() {
    if (_assistantUid != widget.session?.uid) {
      _assistantUid = widget.session?.uid;
      _assistantSession?.controller.reset();
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
          path: '/catalog',
          builder: (context, state) => AnimatedBuilder(
            animation: session,
            builder: (context, _) => _PublicFrame(
              session: session,
              selected: '/catalog',
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1760),
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
        GoRoute(path: '/', builder: (context, state) => _home(context)),
        GoRoute(path: '/demo', builder: (context, state) => _home(context)),
        GoRoute(path: '/assistant', redirect: (context, state) => '/'),
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
                if (section == 'planner') {
                  return EventPlanPage(
                    key: ValueKey(
                      'planner:${state.uri.queryParameters['event']}',
                    ),
                    workspace: workspace,
                    plans: _plans ??=
                        widget.plans ?? FirestoreEventPlanRepository(),
                    uid: session.uid!,
                    initialEventId: state.uri.queryParameters['event'],
                    onOpenEvents: () => context.go('/client/events'),
                  );
                }
                return section == 'settings'
                    ? settings()
                    : ClientPage(
                        key: ValueKey('client:$section'),
                        repository: workspace,
                        uid: session.uid!,
                        section: section,
                        onOpenPlan: (eventId) => context.go(
                          Uri(
                            path: '/client/planner',
                            queryParameters: {'event': eventId},
                          ).toString(),
                        ),
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

  Widget _home(BuildContext context) => MatchingScreen(
    repository: _demoRepository,
    service: widget.recommendationService,
    favoritesRepository: widget.favoritesRepository,
    onOpenAssistant: (request) => _openAssistant(context, request),
    onOpenAccount: widget.session == null
        ? null
        : () => context.go('/client/events'),
    onOpenLiveCatalog: widget.workspace == null
        ? null
        : () => context.go('/catalog'),
  );
  void _openAssistant(BuildContext context, [MatchRequest? request]) {
    final session = _assistantSession ??= AssistantSession(
      repository: _demoRepository,
      service: widget.assistantService,
    );
    showSidePanel<void>(
      context,
      barrierLabel: 'Закрыть помощника',
      builder: (panelContext) => Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: const Text('ИИ-помощник'),
          actions: [
            IconButton(
              autofocus: true,
              tooltip: 'Закрыть помощника',
              onPressed: () => Navigator.of(panelContext).pop(),
              icon: const Icon(Icons.close),
            ),
          ],
        ),
        body: AssistantHost(
          showHeading: false,
          repository: _demoRepository,
          session: session,
          initialRequest: request,
          onOpenCatalog: () => Navigator.of(panelContext).pop(),
        ),
      ),
    );
  }

  void _openMessages(BuildContext context, Contractor? contractor) {
    if (widget.session == null || widget.messagesRepository == null) return;
    showMessagesPanel(
      context,
      session: widget.session!,
      repository: widget.messagesRepository!,
      contractor: contractor,
      onSignIn: () {
        Navigator.of(context, rootNavigator: true).pop();
        _router?.go('/auth');
      },
    );
  }

  Widget _communications(BuildContext context, Widget? child) =>
      CommunicationScope(
        openMessages: _openMessages,
        openAssistant: _openAssistant,
        child: child ?? const SizedBox.shrink(),
      );

  @override
  void dispose() {
    widget.session?.removeListener(_identityChanged);
    _router?.dispose();
    _assistantSession?.dispose();
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
        builder: _communications,
      );
    }
    return MaterialApp(
      title: 'Event Match',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ru'),
      supportedLocales: const [Locale('ru')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: AppTheme.light,
      builder: _communications,
      home: Builder(builder: _home),
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
                    onPressed: () => context.go('/catalog'),
                    child: const Text('Опубликованные подрядчики'),
                  ),
                  TextButton(
                    onPressed: () => context.go('/demo'),
                    child: const Text('Демо-каталог'),
                  ),
                  TextButton(
                    onPressed: () => CommunicationScope.maybeOf(
                      context,
                    )?.openAssistant(context),
                    child: const Text('ИИ-помощник'),
                  ),
                  FilledButton.tonal(
                    onPressed: () => context.go(
                      session.identity == null ? '/auth' : '/client/events',
                    ),
                    child: Text(
                      session.identity == null ? 'Войти' : 'Мой кабинет',
                    ),
                  ),
                  IconButton(
                    tooltip: 'Сообщения',
                    icon: const Icon(Icons.chat_bubble_outline),
                    onPressed: () => CommunicationScope.maybeOf(
                      context,
                    )?.openMessages(context, null),
                  ),
                ],
              ),
            ),
          ),
          if (selected == '/demo')
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
