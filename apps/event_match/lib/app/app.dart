import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import '../features/assistant/presentation/assistant_host.dart';
import '../features/assistant/data/basic_assistant_service.dart';
import '../features/assistant/domain/assistant_service.dart';
import '../features/planning/domain/event_plan_draft_store.dart';
import '../features/workspace/data/workspace_catalog_repository.dart';
import '../features/auth/presentation/auth_pages.dart';
import '../features/auth/presentation/session_controller.dart';
import '../features/auth/presentation/settings_page.dart';
import '../features/communication/data/firestore_communication_repository.dart';
import '../features/communication/domain/communication_models.dart';
import '../features/communication/domain/communication_repository.dart';
import '../features/communication/presentation/communication_page.dart';
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
    this.communications,
    this.initialLocation,
    this.assistantService,
  });
  final CatalogRepository? repository;
  final RecommendationService? recommendationService;
  final SessionController? session;
  final WorkspaceRepository? workspace;
  final EventPlanRepository? plans;
  final CommunicationRepository? communications;
  final String? initialLocation;
  final AssistantService? assistantService;
  @override
  State<EventMatchApp> createState() => _EventMatchAppState();
}

class _EventMatchAppState extends State<EventMatchApp> {
  GoRouter? _router;
  EventPlanRepository? _plans;
  CommunicationRepository? _communications;
  final CatalogRepository _demoRepository = AssetCatalogRepository();
  AssistantSession? _assistantSession;
  AssistantSession? _liveAssistant;
  final _planDrafts = EventPlanDraftStore();
  String? _workspaceUid;
  void _accountChanged() {
    final next = widget.session?.uid;
    if (_workspaceUid != next) {
      _planDrafts.clear();
      _liveAssistant?.controller.reset();
      _workspaceUid = next;
    }
  }

  AssistantSession _liveSession() {
    final catalog = WorkspaceCatalogRepository(widget.workspace!);
    return _liveAssistant ??= AssistantSession(
      repository: catalog,
      service: widget.assistantService,
      source: 'live',
      basicService: BasicAssistantService(
        catalog,
        datePolicy: MatchDatePolicy.live(),
        calendarResolver: widget.workspace!.getCalendar,
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    if (widget.session != null && widget.workspace != null) {
      _workspaceUid = widget.session!.uid;
      widget.session!.addListener(_accountChanged);
      _router = _createRouter();
    }
  }

  GoRouter _createRouter() {
    final session = widget.session!;
    final workspace = widget.workspace!;
    Widget settings() => SettingsPage(session: session, repository: workspace);
    Widget communication(GoRouterState state, CommunicationMode mode) {
      if (mode == CommunicationMode.admin && !session.isAdmin) {
        return const Text('Очередь поддержки доступна администратору.');
      }
      return CommunicationPage(
        key: ValueKey('${session.uid}:${session.epoch}:$mode:${state.uri}'),
        repository: _communications ??=
            widget.communications ?? FirestoreCommunicationRepository(),
        workspace: workspace,
        uid: session.uid!,
        mode: mode,
        isAdmin: session.isAdmin,
        initialConversationId: state.uri.queryParameters['conversation'],
        initialContractorId: state.uri.queryParameters['contractor'],
        initialEventId: state.uri.queryParameters['event'],
        onSelectConversation: (id) => _router!.go(
          Uri(
            path: state.uri.path,
            queryParameters: id.isEmpty ? null : {'conversation': id},
          ).toString(),
        ),
        onOpenEvents: () => _router!.go('/client/events'),
      );
    }

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
                      assistant: _liveSession().controller,
                      eventId: state.uri.queryParameters['event'],
                      selectionId: state.uri.queryParameters['selection'],
                      initialCategory: state.uri.queryParameters['category'],
                      uid: session.canUseWorkspace ? session.uid : null,
                      onCreateInquiry: (contractor) => context.go(
                        Uri(
                          path: '/client/messages',
                          queryParameters: {
                            'contractor': contractor.id,
                            'event': ?state.uri.queryParameters['event'],
                          },
                        ).toString(),
                      ),
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
              onOpenAssistant: (request) =>
                  context.go('/demo/assistant', extra: request),
            ),
          ),
        ),
        GoRoute(path: '/assistant', redirect: (_, _) => '/'),
        GoRoute(
          path: '/demo/assistant',
          builder: (context, state) => _PublicFrame(
            session: session,
            selected: '/assistant',
            child: AssistantHost(
              repository: _demoRepository,
              session: _assistantSession ??= AssistantSession(
                repository: _demoRepository,
              ),
              initialRequest: state.extra is MatchRequest
                  ? state.extra as MatchRequest
                  : null,
              onOpenCatalog: () => context.go('/demo'),
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
                if (section == 'messages' || section == 'support') {
                  return communication(
                    state,
                    section == 'support'
                        ? CommunicationMode.support
                        : CommunicationMode.client,
                  );
                }
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
                    draftStore: _planDrafts,
                    onFindContractors: (event, category) => context.go(
                      Uri(
                        path: '/',
                        queryParameters: {
                          'event': event.id,
                          'category': ?category,
                        },
                      ).toString(),
                    ),
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
                        onFindContractors: (event, selection) => context.go(
                          Uri(
                            path: '/',
                            queryParameters: {
                              'event': event.id,
                              if (selection != null) 'selection': selection.id,
                            },
                          ).toString(),
                        ),
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
                if (section == 'messages' || section == 'support') {
                  return communication(
                    state,
                    section == 'support'
                        ? CommunicationMode.support
                        : CommunicationMode.contractor,
                  );
                }
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
              builder: (context, state) =>
                  state.pathParameters['section'] == 'support'
                  ? communication(state, CommunicationMode.admin)
                  : AdminPage(
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
    widget.session?.removeListener(_accountChanged);
    _liveAssistant?.dispose();
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
