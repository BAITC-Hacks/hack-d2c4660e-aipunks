import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/design_tokens.dart';
import '../../workspace/domain/workspace_models.dart';
import '../../workspace/domain/workspace_repository.dart';
import '../../workspace/presentation/workspace_widgets.dart';
import '../domain/event_plan.dart';
import '../domain/event_plan_engine.dart';
import '../domain/event_plan_repository.dart';

/// The account shell owns navigation and scrolling.
class EventPlanPage extends StatefulWidget {
  const EventPlanPage({
    super.key,
    required this.workspace,
    required this.plans,
    required this.uid,
    this.initialEventId,
    this.onOpenEvents,
  });

  final WorkspaceRepository workspace;
  final EventPlanRepository plans;
  final String uid;
  final String? initialEventId;
  final VoidCallback? onOpenEvents;

  @override
  State<EventPlanPage> createState() => _EventPlanPageState();
}

class _EventPlanPageState extends State<EventPlanPage> {
  final _budget = TextEditingController();
  final _notes = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  List<ClientEvent> _events = [];
  List<SavedSelection> _selections = [];
  Map<String, PublishedProfile> _published = {};
  Map<String, CalendarMonth?> _calendars = {};
  ClientEvent? _event;
  EventPlan? _plan;
  bool _loading = true;
  bool _saving = false;
  bool _dirty = false;
  String? _loadError;
  String? _saveError;
  int _loadGeneration = 0;
  int _eventPickerVersion = 0;

  bool get _locked => _loading || _saving;

  @override
  void initState() {
    super.initState();
    _load(widget.initialEventId);
  }

  @override
  void didUpdateWidget(covariant EventPlanPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uid != widget.uid ||
        oldWidget.workspace != widget.workspace ||
        oldWidget.plans != widget.plans) {
      _event = null;
      _plan = null;
      _dirty = false;
      _load(widget.initialEventId);
    }
  }

  @override
  void dispose() {
    _budget.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _load(String? eventId) async {
    final generation = ++_loadGeneration;
    final uid = widget.uid;
    final workspace = widget.workspace;
    final plans = widget.plans;
    setState(() {
      _loading = true;
      _saving = false;
      _loadError = null;
    });
    try {
      final values = await Future.wait<Object>([
        workspace.listEvents(uid),
        workspace.listSelections(uid),
        workspace.listPublished(),
      ]);
      final events = values[0] as List<ClientEvent>;
      final selections = values[1] as List<SavedSelection>;
      final published = {
        for (final profile in values[2] as List<PublishedProfile>)
          if (profile.published) profile.ownerId: profile,
      };
      final event =
          events.where((e) => e.id == eventId).firstOrNull ??
          events.firstOrNull;
      final plan = event == null ? null : await plans.getPlan(uid, event.id);
      final calendars = <String, CalendarMonth?>{};
      if (event != null && plan != null) {
        final ids = <String>{
          for (final selection in selections.where(
            (s) => s.eventId == event.id,
          ))
            for (final entry in selection.entries) entry.contractor.id,
          for (final choice in plan.choices.values) choice.contractorId,
        };
        await Future.wait(
          ids.where(published.containsKey).map((id) async {
            calendars[id] = await workspace.getCalendar(id, event.date);
          }),
        );
      }
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _events = events;
        _selections = selections;
        _published = published;
        _calendars = calendars;
        _event = event;
        _plan = plan;
        _budget.text = plan?.totalBudgetKzt?.toString() ?? '';
        _notes.text = plan?.notes ?? '';
        _dirty = false;
        _saveError = null;
      });
    } catch (_) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _loadError =
            'Не удалось загрузить план и актуальные данные. '
            'Проверьте подключение и повторите. Ваши изменения остаются на странице.';
      });
    } finally {
      if (mounted && generation == _loadGeneration) {
        setState(() => _loading = false);
      }
    }
  }

  Future<bool> _allowDiscard() async {
    if (!_dirty) return true;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Есть несохранённые изменения'),
            content: const Text(
              'При загрузке другого плана или обновлении они будут потеряны.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Продолжить редактирование'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Загрузить без сохранения'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _reload([String? eventId]) async {
    if (!await _allowDiscard() || !mounted) return;
    await _load(eventId ?? _event?.id ?? widget.initialEventId);
  }

  void _edit(EventPlan plan) => setState(() {
    _plan = plan;
    _dirty = true;
    _saveError = null;
  });

  String? _validateBudget(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;
    final amount = int.tryParse(text);
    if (amount == null || amount <= 0 || amount > 1000000000) {
      return 'Укажите целое число от 1 до 1 000 000 000 или оставьте пустым';
    }
    return null;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final generation = _loadGeneration;
    final draft = _plan!.copyWith(
      totalBudgetKzt: int.tryParse(_budget.text.trim()),
      notes: _notes.text.trim(),
    );
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      final saved = await widget.plans.savePlan(widget.uid, draft);
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _plan = saved;
        _dirty = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('План сохранён')));
    } on EventPlanConflict {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _saveError =
            'План уже изменён в другом окне. Ваши правки остались здесь. '
            'Скопируйте нужные заметки и обновите данные перед повторным сохранением.';
      });
    } catch (_) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _saveError =
            'Не удалось сохранить план. Ваши изменения остались здесь. '
            'Проверьте подключение и повторите сохранение.';
      });
    } finally {
      if (mounted && generation == _loadGeneration) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(
          child: CircularProgressIndicator(semanticsLabel: 'Загрузка плана'),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const WorkspaceHeading(
          'План мероприятия',
          'Сравните подрядчиков, соберите команду и подготовьте запросы по одному брифу.',
        ),
        if (_loadError != null) ...[
          WorkspaceNotice(_loadError!, error: true),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _locked ? null : _reload,
              icon: const Icon(Icons.refresh),
              label: const Text('Повторить загрузку'),
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (_event == null && _loadError == null)
          WorkspaceEmpty(
            title: 'Начните с мероприятия',
            message:
                'Создайте мероприятие и сохраните подборку в разделе «Мои мероприятия». '
                'Здесь можно будет сравнить кандидатов и собрать план.',
            icon: Icons.event_note_outlined,
            action: widget.onOpenEvents == null
                ? null
                : FilledButton.icon(
                    onPressed: widget.onOpenEvents,
                    icon: const Icon(Icons.event_outlined),
                    label: const Text('Мои мероприятия'),
                  ),
          ),
        if (_event != null && _plan != null) _planner(),
      ],
    );
  }

  Widget _planner() {
    final event = _event!;
    final plan = _plan!;
    final review = const EventPlanEngine().build(
      event: event,
      selections: _selections,
      plan: plan,
      published: _published,
      calendars: _calendars,
      now: DateTime.now(),
    );
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          WorkspaceCard(
            color: AppColors.lavender,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<String>(
                  key: ValueKey('plan-event-${event.id}-$_eventPickerVersion'),
                  initialValue: event.id,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Мероприятие'),
                  items: [
                    for (final item in _events)
                      DropdownMenuItem(
                        value: item.id,
                        child: Text(
                          item.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: _locked
                      ? null
                      : (value) async {
                          if (value != null && value != event.id) {
                            await _reload(value);
                            // Restore the visible value if the switch was cancelled.
                            if (mounted) setState(() => _eventPickerVersion++);
                          }
                        },
                ),
                const SizedBox(height: 16),
                Text(
                  '${workspaceDate(event.date)} · ${event.city} · ${event.format}',
                ),
                if (event.preferences.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text('Пожелания: ${event.preferences}'),
                ],
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    FilledButton.icon(
                      key: const Key('save-event-plan'),
                      onPressed: _locked || !_dirty ? null : _save,
                      icon: _saving
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save_outlined),
                      label: Text(_saving ? 'Сохраняем…' : 'Сохранить план'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _locked ? null : _reload,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Обновить данные'),
                    ),
                    Text(
                      _dirty
                          ? 'Есть несохранённые изменения'
                          : plan.revision == 0
                          ? 'План ещё не сохранён'
                          : 'Все изменения сохранены',
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (_saveError != null) WorkspaceNotice(_saveError!, error: true),
          _summary(review),
          if (review.groups.isEmpty)
            WorkspaceEmpty(
              title: 'Добавьте кандидатов в план',
              message:
                  'Сохраните подборку для этого мероприятия. Затем выберите по одному подрядчику в каждой категории.',
              action: widget.onOpenEvents == null
                  ? null
                  : OutlinedButton(
                      onPressed: widget.onOpenEvents,
                      child: const Text('Мои мероприятия'),
                    ),
            ),
          for (final group in review.groups) _comparison(group),
          if (plan.choices.isNotEmpty) _choices(review),
          _checklist(),
          WorkspaceCard(
            child: TextFormField(
              key: const Key('plan-notes'),
              controller: _notes,
              enabled: !_locked,
              minLines: 3,
              maxLines: 6,
              maxLength: 2000,
              decoration: const InputDecoration(
                labelText: 'Заметки к плану',
                helperText:
                    'Личные заметки. Они не добавляются в запрос подрядчику.',
                helperMaxLines: 3,
                errorMaxLines: 3,
              ),
              validator: (value) => (value?.length ?? 0) > 2000
                  ? 'Заметка слишком длинная. Сократите текст перед сохранением.'
                  : null,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              onChanged: (value) => _edit(
                _plan!.copyWith(
                  notes: value.length <= 2000 ? value : _plan!.notes,
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              key: const Key('save-event-plan-bottom'),
              onPressed: _locked || !_dirty ? null : _save,
              icon: const Icon(Icons.save_outlined),
              label: Text(_saving ? 'Сохраняем…' : 'Сохранить план'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _summary(EventPlanReview review) => WorkspaceCard(
    color: AppColors.sage,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Команда и бюджет', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        Text(
          'Актуальный выбор: ${review.selectedCount} из ${review.categoryCount} категорий',
        ),
        Text('Требуют уточнения: ${review.unresolvedCount}'),
        if (review.unresolvedCategories.isNotEmpty)
          Text('Нужно уточнить: ${review.unresolvedCategories.join(', ')}'),
        const SizedBox(height: 12),
        Text(
          review.estimatedFromKzt == null
              ? 'Оценка пока не рассчитана'
              : 'Сумма актуальных стартовых цен: от ${_money(review.estimatedFromKzt!)} ₸',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        const Text(
          'Это ориентир по выбранным услугам. Итоговую стоимость, состав пакета и дату нужно подтвердить у подрядчиков.',
        ),
        const SizedBox(height: 20),
        TextFormField(
          key: const Key('plan-budget'),
          controller: _budget,
          enabled: !_locked,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            labelText: 'Общий бюджет, ₸',
            helperText:
                'Необязательно. Это общий ориентир, отдельный от бюджета категории.',
            helperMaxLines: 3,
            errorMaxLines: 3,
          ),
          validator: _validateBudget,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          onChanged: (value) => _edit(
            _plan!.copyWith(
              totalBudgetKzt: _validateBudget(value) == null
                  ? int.tryParse(value)
                  : null,
            ),
          ),
        ),
        if (review.remainingBudgetKzt != null) ...[
          const SizedBox(height: 12),
          Text(
            review.exceedsBudget
                ? 'Стартовые цены выше бюджета на ${_money(-review.remainingBudgetKzt!)} ₸'
                : 'После стартовых цен остаётся ${_money(review.remainingBudgetKzt!)} ₸',
          ),
        ] else if (_plan!.totalBudgetKzt != null) ...[
          const SizedBox(height: 12),
          const Text(
            'Остаток не рассчитан: сначала выберите подрядчиков и уточните все проблемные позиции.',
          ),
        ],
      ],
    ),
  );

  Widget _comparison(PlanSelectionReview group) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SizedBox(height: 12),
      Text(group.name, style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8),
      Text(
        '${group.category} · бюджет категории до ${_money(group.selection.request.budget)} ₸',
      ),
      if (group.staleBrief) ...[
        const SizedBox(height: 12),
        const WorkspaceNotice(
          'Условия мероприятия изменились. Обновите подборку в разделе «Сохранённые подборки», чтобы выбрать кандидата.',
        ),
      ],
      const SizedBox(height: 16),
      if (group.candidates.isEmpty)
        const WorkspaceNotice(
          'В этой подборке нет кандидатов. Обновите подбор с другими условиями.',
        ),
      LayoutBuilder(
        builder: (context, constraints) {
          final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
          final columns = scale > 1.3 || constraints.maxWidth < 680
              ? 1
              : constraints.maxWidth >= 1020
              ? 3
              : 2;
          final width = (constraints.maxWidth - 16 * (columns - 1)) / columns;
          return Wrap(
            spacing: 16,
            children: [
              for (final candidate in group.candidates)
                SizedBox(width: width, child: _candidate(candidate)),
            ],
          );
        },
      ),
    ],
  );

  Widget _candidate(PlanCandidate candidate) {
    final current = candidate.currentContractor;
    final provider = candidate.contractor;
    final calendar = _calendars[candidate.contractorId];
    return WorkspaceCard(
      color: candidate.isSelected ? AppColors.lavender : AppColors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (candidate.isSelected) ...[
            const Text(
              'Выбран в план',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
          ],
          Text(candidate.name, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Text(
            candidate.currentPriceKzt == null
                ? 'Текущая цена не подтверждена'
                : 'От ${_money(candidate.currentPriceKzt!)} ₸',
          ),
          Text('Город: ${provider.city}'),
          Text(
            'Языки: ${provider.languages.isEmpty ? 'не указаны' : provider.languages.join(', ')}',
          ),
          Text(
            'Форматы: ${provider.formats.isEmpty ? 'не указаны' : provider.formats.join(', ')}',
          ),
          Text(
            'Длительность: ${provider.maxHours == null ? 'уточните у подрядчика' : 'до ${provider.maxHours} ч'}',
          ),
          const SizedBox(height: 8),
          Text(
            current == null
                ? 'Профиль из истории подборки'
                : 'Текущий опубликованный профиль',
          ),
          Text(
            'Календарь подтверждён: ${workspaceDate(calendar?.confirmedAt)}',
          ),
          if (candidate.canChoose)
            const Text(
              'Дата доступна по подтверждённому календарю. Это не бронь.',
            ),
          for (final warning in [
            ...candidate.blockers,
            ...candidate.warnings,
          ]) ...[const SizedBox(height: 8), Text(warning)],
          const SizedBox(height: 12),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('Подробности и объяснение'),
            childrenPadding: const EdgeInsets.only(bottom: 16),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(provider.description),
              const SizedBox(height: 12),
              const Text(
                'Объяснение из сохранённой подборки:',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              Text(candidate.recommendation.explanation),
              if (current != null && current.contact.isNotEmpty) ...[
                const SizedBox(height: 12),
                SelectableText('Контакт: ${current.contact}'),
              ],
              if (current != null)
                for (final url in current.portfolioUrls) ...[
                  const SizedBox(height: 8),
                  SelectableText('Портфолио: $url'),
                ],
            ],
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            key: ValueKey(
              'choose-${candidate.selectionId}-${candidate.contractorId}',
            ),
            onPressed: _locked || !candidate.canChoose || candidate.isSelected
                ? null
                : () => _edit(
                    _plan!.choose(
                      candidate.category,
                      PlanChoice(
                        selectionId: candidate.selectionId,
                        contractorId: candidate.contractorId,
                      ),
                    ),
                  ),
            icon: Icon(
              candidate.isSelected
                  ? Icons.check_circle_outline
                  : Icons.add_circle_outline,
            ),
            label: Text(candidate.isSelected ? 'Выбран' : 'Выбрать в план'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: ValueKey(
              'brief-${candidate.selectionId}-${candidate.contractorId}',
            ),
            onPressed: _locked || !candidate.canChoose
                ? null
                : () => _showBrief(candidate),
            icon: const Icon(Icons.description_outlined),
            label: const Text('Черновик запроса'),
          ),
        ],
      ),
    );
  }

  Widget _choices(EventPlanReview review) => WorkspaceCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Ваш выбор по категориям',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        for (final entry in _plan!.choices.entries) ...[
          Text(entry.key, style: Theme.of(context).textTheme.titleMedium),
          Text(
            review.groups
                    .expand((group) => group.candidates)
                    .where(
                      (c) =>
                          c.category == entry.key &&
                          c.contractorId == entry.value.contractorId,
                    )
                    .firstOrNull
                    ?.name ??
                'Выбранный кандидат больше не доступен в подборке',
          ),
          if (review.unresolvedCategories.contains(entry.key))
            const Text(
              'Выбор требует уточнения и не включён в оценку бюджета.',
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: ValueKey('clear-${entry.key}'),
              onPressed: _locked ? null : () => _edit(_plan!.remove(entry.key)),
              icon: const Icon(Icons.close),
              label: const Text('Убрать из плана'),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ],
    ),
  );

  Widget _checklist() => WorkspaceCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Проверить перед договорённостью',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        const Text(
          'Отмечайте после личного обсуждения. Эти отметки не подтверждают бронирование.',
        ),
        const SizedBox(height: 12),
        for (final task in planningTasks.entries)
          CheckboxListTile(
            key: ValueKey('task-${task.key}'),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(task.value),
            value: _plan!.completedTaskIds.contains(task.key),
            onChanged: _locked
                ? null
                : (checked) {
                    final tasks = {..._plan!.completedTaskIds};
                    if (checked == true) {
                      tasks.add(task.key);
                    } else {
                      tasks.remove(task.key);
                    }
                    _edit(_plan!.copyWith(completedTaskIds: tasks));
                  },
          ),
      ],
    ),
  );

  Future<void> _showBrief(PlanCandidate candidate) => showDialog<void>(
    context: context,
    builder: (context) => _BriefDialog(initialText: candidate.draftBrief),
  );
}

class _BriefDialog extends StatefulWidget {
  const _BriefDialog({required this.initialText});
  final String initialText;

  @override
  State<_BriefDialog> createState() => _BriefDialogState();
}

class _BriefDialogState extends State<_BriefDialog> {
  late final _text = TextEditingController(text: widget.initialText);
  bool _copying = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _copy() async {
    setState(() => _copying = true);
    try {
      await Clipboard.setData(ClipboardData(text: _text.text));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Черновик скопирован. Отправка не выполнялась.'),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Не удалось скопировать. Выделите текст и скопируйте вручную.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _copying = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Черновик запроса подрядчику'),
    content: SizedBox(
      width: 620,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'При необходимости измените текст. Вы сами выбираете способ связи и отправляете запрос подрядчику.',
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('draft-request-text'),
              controller: _text,
              minLines: 8,
              maxLines: null,
              enabled: !_copying,
              decoration: const InputDecoration(labelText: 'Текст запроса'),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Закрыть'),
      ),
      FilledButton.icon(
        onPressed: _copying || _text.text.trim().isEmpty ? null : _copy,
        icon: const Icon(Icons.copy_outlined),
        label: const Text('Скопировать текст'),
      ),
    ],
  );
}

String _money(int amount) => amount.toString().replaceAllMapped(
  RegExp(r'\B(?=(\d{3})+(?!\d))'),
  (_) => ' ',
);
