import 'package:event_match/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../features/auth/presentation/session_controller.dart';
import 'design_tokens.dart';
import 'communication_scope.dart';

class AccountShell extends StatelessWidget {
  const AccountShell({
    super.key,
    required this.session,
    required this.location,
    required this.child,
  });
  final SessionController session;
  final String location;
  final Widget child;

  String get _mode => location.startsWith('/contractor')
      ? 'contractor'
      : location.startsWith('/admin')
      ? 'admin'
      : 'client';
  List<({String path, String title, IconData icon})> get _items =>
      switch (_mode) {
        'contractor' => [
          (
            path: '/contractor/overview',
            title: 'Обзор',
            icon: Icons.dashboard_outlined,
          ),
          (
            path: '/contractor/profile',
            title: 'Мой профиль',
            icon: Icons.badge_outlined,
          ),
          (
            path: '/contractor/calendar',
            title: 'Календарь',
            icon: Icons.calendar_month_outlined,
          ),
          (
            path: '/contractor/moderation',
            title: 'Проверка профиля',
            icon: Icons.fact_check_outlined,
          ),
          (
            path: '/contractor/settings',
            title: 'Настройки',
            icon: Icons.settings_outlined,
          ),
        ],
        'admin' => [
          (
            path: '/admin/overview',
            title: 'Обзор',
            icon: Icons.dashboard_outlined,
          ),
          (
            path: '/admin/moderation',
            title: 'Модерация',
            icon: Icons.fact_check_outlined,
          ),
          (
            path: '/admin/contractors',
            title: 'Подрядчики',
            icon: Icons.storefront_outlined,
          ),
          if (session.isAdmin)
            (
              path: '/admin/users',
              title: 'Пользователи',
              icon: Icons.people_outline,
            ),
          (
            path: '/admin/quality',
            title: 'Качество каталога',
            icon: Icons.insights_outlined,
          ),
          (path: '/admin/audit', title: 'Журнал', icon: Icons.history_outlined),
        ],
        _ => [
          (
            path: '/client/events',
            title: 'Мои мероприятия',
            icon: Icons.celebration_outlined,
          ),
          (
            path: '/client/selections',
            title: 'Подборки',
            icon: Icons.auto_awesome_outlined,
          ),
          (
            path: '/client/planner',
            title: 'План события',
            icon: Icons.assignment_outlined,
          ),
          (
            path: '/client/favorites',
            title: 'Избранное',
            icon: Icons.favorite_outline,
          ),
          (
            path: '/client/settings',
            title: 'Настройки',
            icon: Icons.settings_outlined,
          ),
        ],
      };

  Widget _navigation(BuildContext context, {bool drawer = false}) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 16, 12, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Event Match', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              session.account?.name ?? '',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
      DropdownButtonFormField<String>(
        key: ValueKey(_mode),
        initialValue: _mode,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: trNullable(context, 'Кабинет'),
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        ),
        items: [
          const DropdownMenuItem(value: 'client', child: Text('Заказчик')),
          const DropdownMenuItem(value: 'contractor', child: Text('Подрядчик')),
          if (session.isStaff)
            const DropdownMenuItem(value: 'admin', child: Text('Админка')),
        ],
        onChanged: (value) {
          if (drawer) Navigator.pop(context);
          context.go(
            value == 'contractor'
                ? '/contractor/overview'
                : value == 'admin'
                ? '/admin/overview'
                : '/client/events',
          );
        },
      ),
      const SizedBox(height: 24),
      for (final item in _items)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            selected:
                location == item.path ||
                (location == '/settings' && item.path.endsWith('/settings')),
            selectedTileColor: AppColors.lavender,
            leading: Icon(item.icon),
            title: Text(item.title),
            onTap: () {
              if (drawer) Navigator.pop(context);
              context.go(item.path);
            },
          ),
        ),
      const Divider(height: 32),
      ListTile(
        leading: const Icon(Icons.auto_awesome_outlined),
        title: Text(tr(context, 'ИИ-помощник')),
        onTap: () =>
            CommunicationScope.maybeOf(context)?.openAssistant(context),
      ),
      ListTile(
        leading: const Icon(Icons.chat_bubble_outline),
        title: Text(tr(context, 'Сообщения')),
        onTap: () =>
            CommunicationScope.maybeOf(context)?.openMessages(context, null),
      ),
      ListTile(
        leading: const Icon(Icons.search_outlined),
        title: Text(tr(context, 'Каталог')),
        onTap: () {
          if (drawer) Navigator.pop(context);
          context.go('/');
        },
      ),
      ListTile(
        leading: const Icon(Icons.logout_outlined),
        title: Text(tr(context, 'Выйти')),
        onTap: () async {
          if (drawer) Navigator.pop(context);
          try {
            await session.signOut();
          } catch (_) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Не удалось выйти. Повторите попытку.'),
                ),
              );
            }
          }
        },
      ),
    ],
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final desktop = constraints.maxWidth >= 1024;
      final body = KeyedSubtree(
        key: ValueKey('${session.uid}:${session.epoch}'),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(desktop ? 32 : 20),
            child: Align(
              alignment: Alignment.topLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1200),
                child: child,
              ),
            ),
          ),
        ),
      );
      return Scaffold(
        appBar: desktop ? null : AppBar(title: const Text('Event Match')),
        drawer: desktop
            ? null
            : Drawer(
                child: SafeArea(child: _navigation(context, drawer: true)),
              ),
        body: desktop
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 270,
                    child: Material(
                      color: AppColors.white,
                      child: SafeArea(child: _navigation(context)),
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(child: body),
                ],
              )
            : body,
      );
    },
  );
}
