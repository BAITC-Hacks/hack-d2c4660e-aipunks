import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/design_tokens.dart';
import '../domain/workspace_models.dart';
import '../domain/workspace_repository.dart';
import 'workspace_widgets.dart';

class AdminPage extends StatefulWidget {
  const AdminPage({
    super.key,
    required this.repository,
    required this.uid,
    required this.isAdmin,
    this.section = 'overview',
  });
  final WorkspaceRepository repository;
  final String uid, section;
  final bool isAdmin;

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminData {
  const _AdminData({
    this.profiles = const [],
    this.published = const [],
    this.accounts = const [],
    this.staff = const {},
    this.audit = const [],
  });
  final List<ContractorProfile> profiles;
  final List<PublishedProfile> published;
  final List<Account> accounts;
  final Map<String, StaffAccess> staff;
  final List<AuditEntry> audit;
}

class _AdminPageState extends State<AdminPage> {
  late Future<_AdminData> _data = _load();
  final _search = TextEditingController();
  String _query = '';

  Future<_AdminData> _load() async {
    if (widget.section == 'users') {
      if (!widget.isAdmin) return const _AdminData();
      final values = await Future.wait<Object>([
        widget.repository.listAccounts(),
        widget.repository.listStaff(),
      ]);
      return _AdminData(
        accounts: values[0] as List<Account>,
        staff: values[1] as Map<String, StaffAccess>,
      );
    }
    if (widget.section == 'audit') {
      return _AdminData(audit: await widget.repository.listAudit());
    }
    final values = await Future.wait<Object>([
      widget.repository.listProfiles(),
      widget.repository.listPublished(),
    ]);
    return _AdminData(
      profiles: values[0] as List<ContractorProfile>,
      published: values[1] as List<PublishedProfile>,
    );
  }

  void _refresh() => setState(() {
    _data = _load();
  });

  Future<void> _change(Future<void> Function() action) async {
    await action();
    if (mounted) _refresh();
  }

  @override
  void didUpdateWidget(covariant AdminPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.section != widget.section ||
        oldWidget.uid != widget.uid ||
        oldWidget.isAdmin != widget.isAdmin ||
        oldWidget.repository != widget.repository) {
      _data = _load();
      _query = '';
      _search.clear();
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<_AdminData>(
    future: _data,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return WorkspaceEmpty(
          title: 'Не удалось загрузить служебные данные',
          message: 'Проверьте подключение и права доступа.',
          action: OutlinedButton(
            onPressed: _refresh,
            child: const Text('Повторить'),
          ),
        );
      }
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      final data = snapshot.requireData;
      final content = switch (widget.section) {
        'moderation' => _moderation(data),
        'contractors' => _contractors(data),
        'users' => _users(data),
        'quality' => _QualityPanel(
          key: ValueKey(_data),
          repository: widget.repository,
          data: data,
        ),
        'audit' => _audit(data.audit),
        _ => _overview(data),
      };
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _refresh,
              icon: const Icon(Icons.refresh),
              label: const Text('Обновить данные'),
            ),
          ),
          content,
        ],
      );
    },
  );

  Widget _overview(_AdminData data) {
    final pending = data.profiles.where((p) => p.isPending).length;
    final incomplete = data.profiles
        .where((p) => p.content.issues.isNotEmpty)
        .length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const WorkspaceHeading(
          'Рабочий стол Event Match',
          'Проверяйте карточки и поддерживайте качество живого каталога.',
        ),
        Wrap(
          spacing: 16,
          runSpacing: 0,
          children: [
            _metric('На проверке', '$pending', AppColors.lavender),
            _metric('Опубликовано', '${data.published.length}', AppColors.sage),
            _metric('Неполные профили', '$incomplete', AppColors.peach),
          ],
        ),
        WorkspaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                pending == 0
                    ? 'Очередь проверки пуста'
                    : 'Есть карточки, ожидающие решения',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              const Text(
                'Проверяйте услуги, цены и деловые контакты по отправленной версии. '
                'Календарь подрядчик подтверждает самостоятельно.',
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  FilledButton(
                    onPressed: () => context.go('/admin/moderation'),
                    child: const Text('Открыть модерацию'),
                  ),
                  OutlinedButton(
                    onPressed: () => context.go('/admin/quality'),
                    child: const Text('Качество каталога'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const WorkspaceNotice(
          'Личные мероприятия и подборки клиентов доступны только их владельцам. '
          'Служебные изменения записываются в журнал.',
        ),
      ],
    );
  }

  Widget _metric(String label, String value, Color color) => SizedBox(
    width: 230,
    child: WorkspaceCard(
      color: color,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: Theme.of(context).textTheme.headlineLarge),
          Text(label),
        ],
      ),
    ),
  );

  Widget _moderation(_AdminData data) {
    final pending = data.profiles.where((p) => p.isPending).toList()
      ..sort(
        (a, b) => (a.updatedAt ?? DateTime(1970)).compareTo(
          b.updatedAt ?? DateTime(1970),
        ),
      );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const WorkspaceHeading(
          'Модерация',
          'Сравните отправленную версию с опубликованной и сохраните решение с причиной.',
        ),
        if (pending.isEmpty)
          const WorkspaceEmpty(
            title: 'Все заявки разобраны',
            message: 'Новые версии появятся здесь после отправки подрядчиками.',
          ),
        for (final profile in pending)
          _reviewCard(
            profile,
            data.published
                .where((p) => p.ownerId == profile.ownerId)
                .firstOrNull,
          ),
      ],
    );
  }

  Widget _reviewCard(
    ContractorProfile profile,
    PublishedProfile? published,
  ) => WorkspaceCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            const WorkspaceStatus('На проверке'),
            Chip(label: Text('Версия ${profile.revision}')),
          ],
        ),
        const SizedBox(height: 8),
        SelectableText('Владелец: ${profile.ownerId}'),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final submitted = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Отправлено ${workspaceDate(profile.updatedAt)}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 16),
                ProfileContentDetails(profile.content),
              ],
            );
            final current = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Сейчас в каталоге',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 16),
                if (published == null)
                  const Text('Ещё не опубликовано')
                else
                  ProfileContentDetails(published.content),
              ],
            );
            if (constraints.maxWidth < 760) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  submitted,
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Divider(),
                  ),
                  current,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: submitted),
                const SizedBox(width: 32),
                Expanded(child: current),
              ],
            );
          },
        ),
        if (published != null) ...[
          const SizedBox(height: 16),
          Text(
            'Изменения: ${_changedFields(published.content, profile.content).join(', ')}.',
          ),
        ],
        if (profile.content.issues.isNotEmpty) ...[
          const SizedBox(height: 16),
          WorkspaceNotice(
            'Не заполнено: ${profile.content.issues.join('; ')}.',
            error: true,
          ),
        ],
        const SizedBox(height: 24),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            WorkspaceAction(
              label: 'Опубликовать версию ${profile.revision}',
              icon: Icons.check_circle_outline,
              onPressed: profile.content.issues.isNotEmpty
                  ? null
                  : () async {
                      final reason = await workspaceReason(
                        context,
                        'Опубликовать проверенную карточку?',
                      );
                      if (reason != null) {
                        await _change(
                          () => widget.repository.moderateProfile(
                            widget.uid,
                            profile.ownerId,
                            approve: true,
                            reason: reason,
                            expectedRevision: profile.revision,
                          ),
                        );
                      }
                    },
            ),
            WorkspaceAction(
              label: 'Вернуть на исправление',
              icon: Icons.edit_note,
              outlined: true,
              onPressed: () async {
                final reason = await workspaceReason(
                  context,
                  'Что нужно исправить?',
                );
                if (reason != null) {
                  await _change(
                    () => widget.repository.moderateProfile(
                      widget.uid,
                      profile.ownerId,
                      approve: false,
                      reason: reason,
                      expectedRevision: profile.revision,
                    ),
                  );
                }
              },
            ),
          ],
        ),
      ],
    ),
  );

  List<String> _changedFields(ProfileContent a, ProfileContent b) {
    final old = a.toMap(), current = b.toMap();
    const labels = {
      'name': 'название',
      'city': 'город',
      'categories': 'категории',
      'price': 'цена',
      'formats': 'форматы',
      'languages': 'языки',
      'maxHours': 'длительность',
      'description': 'описание',
      'contact': 'контакты',
      'portfolioUrls': 'портфолио',
    };
    final changed = labels.entries
        .where((e) => old[e.key].toString() != current[e.key].toString())
        .map((e) => e.value)
        .toList();
    return changed.isEmpty ? ['содержимое совпадает'] : changed;
  }

  Widget _searchField(String label) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: TextField(
      controller: _search,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.search),
      ),
      onChanged: (value) => setState(() => _query = value.trim().toLowerCase()),
    ),
  );

  Widget _contractors(_AdminData data) {
    final profiles = data.profiles
        .where(
          (p) => '${p.content.name} ${p.content.city} ${p.ownerId}'
              .toLowerCase()
              .contains(_query),
        )
        .toList();
    final publishedIds = data.published.map((p) => p.ownerId).toSet();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const WorkspaceHeading(
          'Подрядчики',
          'Все живые профили и текущая публикация.',
        ),
        _searchField('Название, город или идентификатор'),
        if (profiles.isEmpty)
          const WorkspaceEmpty(
            title: 'Профилей нет',
            message: 'Подрядчики появятся после создания своих карточек.',
          ),
        for (final profile in profiles)
          WorkspaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profile.content.name.isEmpty
                      ? 'Незаполненный профиль'
                      : profile.content.name,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  '${profile.content.city} · ${profile.content.categories.join(', ')}',
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    WorkspaceStatus(profileStatusLabel(profile.status)),
                    WorkspaceStatus(
                      publishedIds.contains(profile.ownerId)
                          ? 'Опубликован'
                          : 'Не опубликован',
                      positive: publishedIds.contains(profile.ownerId),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SelectableText(profile.ownerId),
                if (publishedIds.contains(profile.ownerId)) ...[
                  const SizedBox(height: 16),
                  WorkspaceAction(
                    label: 'Снять с публикации',
                    outlined: true,
                    icon: Icons.visibility_off_outlined,
                    onPressed: () async {
                      final reason = await workspaceReason(
                        context,
                        'Снять карточку с публикации?',
                      );
                      if (reason != null) {
                        await _change(
                          () => widget.repository.unpublish(
                            widget.uid,
                            profile.ownerId,
                            reason: reason,
                          ),
                        );
                      }
                    },
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _users(_AdminData data) {
    if (!widget.isAdmin) {
      return const WorkspaceEmpty(
        title: 'Только для администратора',
        message: 'Управление пользователями не входит в права модератора.',
      );
    }
    final accounts = data.accounts
        .where(
          (a) => '${a.name} ${a.email} ${a.uid}'.toLowerCase().contains(_query),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const WorkspaceHeading(
          'Пользователи',
          'Доступ к Event Match и фиксированные служебные роли.',
        ),
        const WorkspaceNotice(
          'Блокировка закрывает доступ к Event Match и скрывает карточку. '
          'Разблокировка не публикует её повторно.',
        ),
        _searchField('Имя, email или идентификатор'),
        if (accounts.isEmpty)
          const WorkspaceEmpty(
            title: 'Пользователей не найдено',
            message: 'Попробуйте изменить поиск.',
          ),
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth >= 1000) {
              return WorkspaceCard(
                child: DataTable(
                  columnSpacing: 24,
                  columns: const [
                    DataColumn(label: Text('Пользователь')),
                    DataColumn(label: Text('Доступ')),
                    DataColumn(label: Text('Роль')),
                    DataColumn(label: Text('Действия')),
                  ],
                  dataRowMinHeight: 100,
                  dataRowMaxHeight: 180,
                  rows: accounts.map((account) {
                    final role = data.staff[account.uid]?.role ?? 'none';
                    return DataRow(
                      cells: [
                        DataCell(
                          SizedBox(
                            width: 240,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  account.name.isEmpty
                                      ? 'Без имени'
                                      : account.name,
                                ),
                                Text(account.email),
                                if (account.deletionRequested)
                                  const Text('Запрошено удаление'),
                              ],
                            ),
                          ),
                        ),
                        DataCell(Text(_accountStatus(account.status))),
                        DataCell(Text(_roleLabel(role))),
                        DataCell(
                          SizedBox(
                            width: 330,
                            child: _userActions(account, role),
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              );
            }
            return Column(
              children: accounts.map((account) {
                final role = data.staff[account.uid]?.role ?? 'none';
                return WorkspaceCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        account.name.isEmpty ? 'Без имени' : account.name,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      SelectableText(account.email),
                      const SizedBox(height: 8),
                      SelectableText(account.uid),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          WorkspaceStatus(_accountStatus(account.status)),
                          WorkspaceStatus(_roleLabel(role)),
                        ],
                      ),
                      if (account.deletionRequested)
                        const Text(
                          'Запрошено полное удаление через служебный инструмент.',
                        ),
                      const SizedBox(height: 16),
                      _userActions(account, role),
                    ],
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _userActions(Account account, String role) {
    if (account.uid == widget.uid || role == 'admin') {
      return const Text('Администратор: изменения через служебный инструмент');
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        WorkspaceAction(
          label: account.status == 'suspended'
              ? 'Разблокировать'
              : 'Заблокировать',
          icon: Icons.lock_outline,
          outlined: true,
          onPressed: () async {
            final suspended = account.status != 'suspended';
            final reason = await workspaceReason(
              context,
              suspended ? 'Заблокировать доступ?' : 'Восстановить доступ?',
            );
            if (reason != null) {
              await _change(
                () => widget.repository.setAccountStatus(
                  widget.uid,
                  account.uid,
                  suspended: suspended,
                  reason: reason,
                ),
              );
            }
          },
        ),
        WorkspaceAction(
          label: role == 'moderator'
              ? 'Отозвать роль'
              : 'Назначить модератором',
          icon: Icons.admin_panel_settings_outlined,
          outlined: true,
          onPressed: !account.isActive && role != 'moderator'
              ? null
              : () async {
                  final reason = await workspaceReason(
                    context,
                    role == 'moderator'
                        ? 'Отозвать права модератора?'
                        : 'Назначить модератора?',
                  );
                  if (reason != null) {
                    await _change(
                      () => widget.repository.setModerator(
                        widget.uid,
                        account.uid,
                        enabled: role != 'moderator',
                        reason: reason,
                      ),
                    );
                  }
                },
        ),
      ],
    );
  }

  String _accountStatus(String status) => switch (status) {
    'suspended' => 'Заблокирован',
    'deactivated' => 'Деактивирован',
    _ => 'Активен',
  };
  String _roleLabel(String role) => switch (role) {
    'admin' => 'Администратор',
    'moderator' => 'Модератор',
    _ => 'Пользователь',
  };

  Widget _audit(List<AuditEntry> entries) {
    final sorted = entries.toList()
      ..sort(
        (a, b) => (b.createdAt ?? DateTime(1970)).compareTo(
          a.createdAt ?? DateTime(1970),
        ),
      );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const WorkspaceHeading(
          'Журнал изменений',
          'Кто, когда и по какой причине изменил публикацию или права доступа.',
        ),
        if (sorted.isEmpty)
          const WorkspaceEmpty(
            title: 'Журнал пуст',
            message: 'Здесь появятся записи служебных изменений.',
          ),
        for (final entry in sorted)
          WorkspaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _actionLabel(entry.action),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  '${workspaceDate(entry.createdAt)}${entry.createdAt == null ? '' : ' · ${entry.createdAt!.hour.toString().padLeft(2, '0')}:${entry.createdAt!.minute.toString().padLeft(2, '0')}'}',
                ),
                const SizedBox(height: 8),
                SelectableText(
                  'Автор: ${entry.actorId}\nОбъект: ${entry.resourceType} / ${entry.resourceId}\nВерсия: ${entry.revision}',
                ),
                const SizedBox(height: 8),
                Text('Причина: ${entry.reason}'),
              ],
            ),
          ),
      ],
    );
  }

  String _actionLabel(String value) => switch (value) {
    'publish' || 'approved' => 'Карточка опубликована',
    'reject' || 'changes_requested' => 'Запрошены исправления',
    'unpublish' || 'unpublished' => 'Карточка снята с публикации',
    'suspend' || 'suspended' => 'Доступ заблокирован',
    'unsuspend' || 'active' => 'Доступ восстановлен',
    'grant_moderator' || 'moderator' => 'Назначен модератор',
    'revoke_moderator' || 'none' => 'Права модератора отозваны',
    'deactivate' || 'deactivated' => 'Аккаунт деактивирован',
    _ => value,
  };
}

class _QualityPanel extends StatefulWidget {
  const _QualityPanel({
    super.key,
    required this.repository,
    required this.data,
  });
  final WorkspaceRepository repository;
  final _AdminData data;
  @override
  State<_QualityPanel> createState() => _QualityPanelState();
}

class _QualityPanelState extends State<_QualityPanel> {
  late DateTime _date = DateTime.now().add(const Duration(days: 1));
  String _city = 'Алматы', _category = 'Ведущий', _format = 'свадьба';
  final _budget = TextEditingController(text: '1000000');
  final _form = GlobalKey<FormState>();
  Map<String, CalendarMonth?> _calendars = {};
  bool _loading = true;
  String? _error;
  bool _showDiagnostic = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _budget.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final values = await Future.wait(
        widget.data.published.map(
          (p) async => MapEntry(
            p.ownerId,
            await widget.repository.getCalendar(p.ownerId, _date),
          ),
        ),
      );
      if (mounted) setState(() => _calendars = Map.fromEntries(values));
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Не удалось проверить календари. Повторите загрузку.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _reason(PublishedProfile profile) {
    final content = profile.content;
    if (content.city != _city) return 'Другой город';
    if (!content.categories.contains(_category)) return 'Другая категория';
    final availability =
        _calendars[profile.ownerId]?.availabilityOn(_date, DateTime.now()) ??
        AvailabilityStatus.unconfirmed;
    if (availability == AvailabilityStatus.unconfirmed) {
      return 'Доступность не подтверждена';
    }
    if (availability == AvailabilityStatus.busy) {
      return 'Занят на выбранную дату';
    }
    if (content.price > (int.tryParse(_budget.text) ?? 0)) {
      return 'Цена выше бюджета';
    }
    if (!content.formats.contains(_format)) {
      return 'Не работает с выбранным форматом';
    }
    return 'Подходит по проверяемым условиям';
  }

  @override
  Widget build(BuildContext context) {
    final incomplete = widget.data.profiles
        .where((p) => p.content.issues.isNotEmpty)
        .toList();
    final stale = widget.data.published
        .where(
          (p) => !(_calendars[p.ownerId]?.isFresh(DateTime.now()) ?? false),
        )
        .toList();
    final coverage = <String, int>{};
    for (final profile in widget.data.published) {
      for (final category in profile.content.categories) {
        coverage.update(
          '${profile.content.city} · $category',
          (value) => value + 1,
          ifAbsent: () => 1,
        );
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const WorkspaceHeading(
          'Качество каталога',
          'Полнота профилей, покрытие и объяснимый проверочный подбор.',
        ),
        WorkspaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Неполные профили: ${incomplete.length}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              for (final profile in incomplete)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    '${profile.content.name.isEmpty ? profile.ownerId : profile.content.name}: ${profile.content.issues.join('; ')}.',
                  ),
                ),
            ],
          ),
        ),
        WorkspaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Покрытие городов и категорий',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              if (coverage.isEmpty)
                const Text('Проверенные карточки ещё не опубликованы.'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: (coverage.keys.toList()..sort())
                    .map((key) => Chip(label: Text('$key: ${coverage[key]}')))
                    .toList(),
              ),
            ],
          ),
        ),
        WorkspaceCard(
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Проверочный подбор',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Проверка города, категории, даты, бюджета и формата. '
                  'Язык и длительность здесь не ограничены.',
                ),
                const SizedBox(height: 24),
                _select('Город', _city, eventCities, (v) => _city = v),
                _select(
                  'Категория',
                  _category,
                  contractorCategories,
                  (v) => _category = v,
                ),
                _select('Формат', _format, eventFormats, (v) => _format = v),
                TextFormField(
                  controller: _budget,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Бюджет на категорию, ₸',
                  ),
                  onChanged: (_) => setState(() => _showDiagnostic = false),
                  validator: (value) => (int.tryParse(value ?? '') ?? 0) > 0
                      ? null
                      : 'Укажите положительный бюджет',
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  icon: const Icon(Icons.calendar_today_outlined),
                  label: Text('Дата: ${workspaceDate(_date)}'),
                  onPressed: _loading
                      ? null
                      : () async {
                          final now = DateTime.now();
                          final date = await showDatePicker(
                            context: context,
                            initialDate: _date,
                            firstDate: DateTime(now.year, now.month, now.day),
                            lastDate: now.add(const Duration(days: 365)),
                          );
                          if (date != null && mounted) {
                            setState(() {
                              _date = date;
                              _showDiagnostic = false;
                            });
                            await _load();
                          }
                        },
                ),
                const SizedBox(height: 16),
                if (_loading)
                  const LinearProgressIndicator()
                else if (_error != null) ...[
                  WorkspaceNotice(_error!, error: true),
                  OutlinedButton(
                    onPressed: _load,
                    child: const Text('Повторить'),
                  ),
                ] else ...[
                  Text(
                    'Нет актуального подтверждения на этот месяц: ${stale.length} из ${widget.data.published.length}.',
                  ),
                  if (stale.isNotEmpty)
                    Text(stale.map((p) => p.content.name).join(', ')),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () {
                      if (_form.currentState!.validate()) {
                        setState(() => _showDiagnostic = true);
                      }
                    },
                    icon: const Icon(Icons.manage_search),
                    label: const Text('Проверить кандидатов'),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (_showDiagnostic && !_loading && _error == null) ...[
          if (widget.data.published.isEmpty)
            const WorkspaceEmpty(
              title: 'Каталог пока пуст',
              message:
                  'Проверочный подбор станет доступен после публикации карточек.',
            ),
          for (final profile in widget.data.published)
            WorkspaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    profile.content.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(_reason(profile)),
                ],
              ),
            ),
        ],
      ],
    );
  }

  Widget _select(
    String label,
    String value,
    List<String> items,
    ValueChanged<String> change,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: items
          .map((item) => DropdownMenuItem(value: item, child: Text(item)))
          .toList(),
      onChanged: (value) {
        if (value != null) {
          setState(() {
            change(value);
            _showDiagnostic = false;
          });
        }
      },
    ),
  );
}
