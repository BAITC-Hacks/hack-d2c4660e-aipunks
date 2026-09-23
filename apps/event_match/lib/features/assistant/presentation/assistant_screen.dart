import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/design_tokens.dart';
import '../../matching/domain/models.dart';
import '../../matching/presentation/widgets/contractor_card.dart';
import '../domain/assistant_models.dart';
import 'assistant_controller.dart';
import 'widgets/assistant_recommendations.dart';

class AssistantScreen extends StatefulWidget {
  const AssistantScreen({
    super.key,
    required this.controller,
    this.onOpenCatalog,
    this.embedded = false,
    this.contextHeader,
    this.cardFooterBuilder,
    this.resultActionsBuilder,
  });

  final AssistantController controller;
  final VoidCallback? onOpenCatalog;
  final bool embedded;
  final Widget? contextHeader;
  final Widget Function(Contractor)? cardFooterBuilder;
  final Widget Function(Future<void> Function(String) editField)?
  resultActionsBuilder;

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen> {
  final _input = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  final _latestMessage = GlobalKey();
  int _messageCount = 0;
  int _inputRevision = 0;

  AssistantController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _inputRevision = controller.contextRevision;
    controller.addListener(_changed);
  }

  @override
  void didUpdateWidget(AssistantScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != controller) {
      oldWidget.controller.removeListener(_changed);
      _input.clear();
      _inputRevision = controller.contextRevision;
      controller.addListener(_changed);
    }
  }

  void _changed() {
    if (!mounted) return;
    if (_inputRevision != controller.contextRevision) {
      _inputRevision = controller.contextRevision;
      _input.clear();
    }
    if (widget.embedded) return;
    if (controller.messages.length != _messageCount) {
      _messageCount = controller.messages.length;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final target = _latestMessage.currentContext;
        if (target != null) {
          Scrollable.ensureVisible(
            target,
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 180),
            alignment: 0,
          );
        } else if (_scroll.hasClients) {
          // A long conversation can leave the newest lazy list child unbuilt.
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final newest = _latestMessage.currentContext;
            if (mounted && newest != null) {
              Scrollable.ensureVisible(newest, alignment: 0);
            }
          });
        }
      });
    }
  }

  @override
  void dispose() {
    controller.removeListener(_changed);
    _input.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final activeController = controller;
    final revision = activeController.contextRevision;
    final value = _input.text.trim();
    if (value.isEmpty || controller.busy) return;
    _input.clear();
    setState(() {});
    await activeController.sendMessage(value);
    if (mounted &&
        identical(controller, activeController) &&
        controller.contextRevision == revision &&
        controller.error != null &&
        _input.text.isEmpty) {
      _input.text = value;
      setState(() {});
    }
  }

  Future<void> _setField(String field, Object value, String label) =>
      controller.act(
        AssistantAction(
          id: 'edit-$field',
          label: label,
          type: 'set_field',
          field: field,
          value: value,
        ),
      );

  Future<void> _editField(String field) async {
    final activeController = controller;
    final revision = controller.contextRevision;
    bool current() =>
        mounted &&
        identical(controller, activeController) &&
        controller.contextRevision == revision;
    if (field == 'preferences') {
      if (controller.service.supportsFreeText &&
          !(widget.embedded && controller.turn?.mode == 'basic')) {
        _focus.requestFocus();
        if (_input.text.trim().isEmpty) _input.text = 'Для меня важно: ';
        _input.selection = TextSelection.collapsed(offset: _input.text.length);
        setState(() {});
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'В базовом режиме пожелания по стилю не анализируются. Можно изменить бюджет, дату и другие условия.',
            ),
          ),
        );
      }
      return;
    }
    final brief = controller.brief;
    if (field == 'date') {
      final existing = DateTime.tryParse(brief.date ?? '');
      final date = await showDatePicker(
        context: context,
        initialDate:
            existing != null && existing.year >= 1900 && existing.year <= 2100
            ? existing
            : widget.embedded
            ? DateTime.now()
            : DateTime(2026, 9, 23),
        firstDate: DateTime(1900),
        lastDate: DateTime(2100, 12, 31),
        helpText: 'Дата события',
        cancelText: 'Отмена',
        confirmText: 'Выбрать',
      );
      if (date != null && current()) {
        await _setField(
          field,
          dateKey(date),
          'Дата: ${_displayDate(dateKey(date))}',
        );
      }
      return;
    }
    if (field == 'budget_kzt' || field == 'hours') {
      final value = await showDialog<num>(
        context: context,
        builder: (_) => _NumberDialog(
          budget: field == 'budget_kzt',
          initial: field == 'budget_kzt' ? brief.budgetKzt : brief.hours,
        ),
      );
      if (value != null && current()) {
        await _setField(
          field,
          field == 'budget_kzt' ? value.toInt() : value.toDouble(),
          field == 'budget_kzt'
              ? 'Бюджет подрядчика: до ${money(value.toInt())} ₸'
              : 'Продолжительность: $value ч',
        );
      }
      return;
    }
    final values = switch (field) {
      'city' => controller.catalog.map((c) => c.city).toSet().toList(),
      'category' =>
        controller.catalog.expand((c) => c.categories).toSet().toList(),
      'event_format' =>
        controller.catalog.expand((c) => c.formats).toSet().toList(),
      'language' =>
        controller.catalog.expand((c) => c.languages).toSet().toList(),
      _ => <String>[],
    }..sort();
    final value = await showDialog<String>(
      context: context,
      builder: (_) => _ValuePicker(title: _fieldName(field), values: values),
    );
    if (value != null && current()) {
      await _setField(field, value, '${_fieldName(field)}: $value');
    }
  }

  Future<void> _act(AssistantAction action) async {
    if (controller.busy) return;
    switch (action.type) {
      case 'pick_date':
        await _editField('date');
      case 'pick_budget':
        await _editField('budget_kzt');
      case 'pick_field':
        if (action.field != null) await _editField(action.field!);
      default:
        await controller.act(action);
    }
  }

  Future<void> _reject(String id, String detail) => controller.act(
    AssistantAction(
      id: 'reject-$id',
      label: 'Не подходит',
      type: 'reject',
      value: {
        'contractor_id': id,
        'reason': switch (detail) {
          'Дорого' => 'price',
          'Не мой стиль' => 'style',
          'Мало информации' => 'experience',
          _ => 'other',
        },
        'detail': detail,
      },
    ),
  );

  Widget _brief({required bool compact, VoidCallback? beforeFreeText}) {
    final brief = controller.brief;
    final values = <String, String?>{
      'category': brief.category,
      'city': brief.city,
      'event_format': brief.eventFormat,
      'date': brief.date == null ? null : _displayDate(brief.date!),
      'budget_kzt': brief.budgetKzt == null
          ? null
          : 'до ${money(brief.budgetKzt!)} ₸${brief.budgetScope == 'event' ? ' на всё событие' : ''}',
      'language': brief.language,
      'hours': brief.hours == null ? null : '${brief.hours} ч',
    };
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Нажмите на условие, чтобы изменить его.'),
        const SizedBox(height: 12),
        for (final entry in values.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                Expanded(
                  child: TextButton(
                    key: Key('brief-${entry.key}'),
                    onPressed: controller.busy
                        ? null
                        : () => _editField(entry.key),
                    style: TextButton.styleFrom(
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 12,
                      ),
                      minimumSize: const Size(48, 48),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _fieldName(entry.key),
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          entry.value ??
                              (brief.skippedFields.contains(entry.key)
                                  ? 'Пока не знаю'
                                  : 'Не задано'),
                        ),
                      ],
                    ),
                  ),
                ),
                if (entry.value != null)
                  IconButton(
                    tooltip: 'Убрать: ${_fieldName(entry.key)}',
                    onPressed: controller.busy
                        ? null
                        : () => controller.act(
                            AssistantAction(
                              id: 'clear-${entry.key}',
                              label: 'Убрать: ${_fieldName(entry.key)}',
                              type: 'clear_field',
                              field: entry.key,
                            ),
                          ),
                    icon: const Icon(Icons.close, size: 18),
                  )
                else
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: ExcludeSemantics(
                      child: Icon(Icons.edit_outlined, size: 18),
                    ),
                  ),
              ],
            ),
          ),
        if (brief.preferences.isNotEmpty) ...[
          const Divider(),
          const SizedBox(height: 8),
          Text('Пожелания', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          for (var i = 0; i < brief.preferences.length; i++)
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${brief.preferences[i].text}${brief.preferences[i].importance == 'required' ? ' · обязательно' : ''}',
                  ),
                ),
                IconButton(
                  tooltip: 'Убрать пожелание: ${brief.preferences[i].text}',
                  onPressed: controller.busy
                      ? null
                      : () => controller.act(
                          AssistantAction(
                            id: 'remove-preference-$i',
                            label: 'Убрать пожелание',
                            type: 'remove_preference',
                            value: i,
                          ),
                        ),
                  icon: const Icon(Icons.close, size: 18),
                ),
              ],
            ),
        ],
        if (controller.service.supportsFreeText &&
            !(widget.embedded && controller.turn?.mode == 'basic'))
          TextButton.icon(
            onPressed: controller.busy
                ? null
                : () {
                    beforeFreeText?.call();
                    _editField('preferences');
                  },
            icon: const Icon(Icons.add),
            label: const Text('Добавить пожелание'),
          ),
        if (brief.canRecommend)
          OutlinedButton.icon(
            onPressed: controller.busy
                ? null
                : () => controller.act(
                    const AssistantAction(
                      id: 'next-category',
                      label: 'Подобрать следующего специалиста',
                      type: 'next_category',
                    ),
                  ),
            icon: const Icon(Icons.person_add_alt_outlined),
            label: const Text('Следующий специалист'),
          ),
      ],
    );
    return Container(
      key: Key(compact ? 'assistant-brief-compact' : 'assistant-brief-sidebar'),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: compact
          ? ExpansionTile(
              shape: const Border(),
              collapsedShape: const Border(),
              title: const Text('Уже учтено'),
              subtitle: Text(
                [
                      brief.category,
                      brief.city,
                      brief.eventFormat,
                    ].whereType<String>().join(' · ').isEmpty
                    ? 'Ваши условия появятся здесь'
                    : [
                        brief.category,
                        brief.city,
                        brief.eventFormat,
                      ].whereType<String>().join(' · '),
              ),
              childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
              children: [content],
            )
          : Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Уже учтено',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  content,
                ],
              ),
            ),
    );
  }

  Widget _welcome() {
    final freeText = controller.service.supportsFreeText;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ExcludeSemantics(
            child: CircleAvatar(
              radius: 28,
              backgroundColor: AppColors.lavender,
              child: Icon(
                Icons.auto_awesome_outlined,
                color: AppColors.primary,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Кого подберём для вашего события?',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Text(
            freeText
                ? 'Расскажите, кого ищете и что для вас важно. Можно сразу указать город, дату и бюджет — учту всё в одном сообщении.'
                : 'Выберите специалиста. Затем уточним город и формат, чтобы показать первые варианты.',
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final example in const {
                'Ведущий на свадьбу': 'Ведущий',
                'Фотограф': 'Фотограф',
                'Площадка': 'Банкетный зал',
              }.entries)
                ActionChip(
                  label: Text(freeText ? example.key : example.value),
                  onPressed: controller.busy
                      ? null
                      : () {
                          if (freeText) {
                            controller.sendMessage(example.key);
                          } else {
                            _setField('category', example.value, example.value);
                          }
                        },
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Один специалист за раз · до трёх вариантов с объяснением',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _actions(List<AssistantAction> actions) {
    final revision = controller.contextRevision;
    final enabled = !controller.busy && controller.error == null;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final action in actions.take(actions.length > 5 ? 4 : 5))
          ActionChip(
            key: ValueKey('assistant-action-${action.id}'),
            label: Text(action.label),
            onPressed: enabled ? () => _act(action) : null,
          ),
        if (actions.length > 5)
          ActionChip(
            label: const Text('Ещё варианты'),
            onPressed: !enabled
                ? null
                : () async {
                    final action = await showDialog<AssistantAction>(
                      context: context,
                      builder: (context) => SimpleDialog(
                        title: const Text('Выберите вариант'),
                        children: [
                          for (final action in actions.skip(4))
                            SimpleDialogOption(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 16,
                              ),
                              onPressed: () => Navigator.pop(context, action),
                              child: Text(action.label),
                            ),
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Отмена'),
                          ),
                        ],
                      ),
                    );
                    if (action != null &&
                        mounted &&
                        controller.contextRevision == revision) {
                      await _act(action);
                    }
                  },
          ),
      ],
    );
  }

  Widget _message(AssistantMessage message, bool latest) {
    final revision = controller.contextRevision;
    final user = message.role == 'user';
    final turn = message.turn;
    final result = turn?.result;
    return Padding(
      key: latest ? _latestMessage : null,
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: user ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 720),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: user
                    ? AppColors.lavender
                    : Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Semantics(
                key: latest && !user
                    ? const Key('assistant-latest-response')
                    : null,
                container: true,
                liveRegion: latest && !user,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user ? 'Вы' : 'Помощник',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 8),
                    SelectionArea(
                      child: Text(
                        message.text,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (turn != null && identical(turn, controller.turn)) ...[
            if (turn.warnings.isNotEmpty) ...[
              const SizedBox(height: 12),
              for (final warning in turn.warnings)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(warning),
                ),
            ],
            if (turn.actions.isNotEmpty) ...[
              const SizedBox(height: 12),
              _actions(turn.actions),
            ],
            if (result != null) ...[
              const SizedBox(height: 20),
              if (!message.text.contains(result.summary)) ...[
                Text(result.summary),
                const SizedBox(height: 12),
              ],
              AssistantRecommendations(
                recommendations: result.toMatchResult().recommendations,
                unverified: {
                  for (final r in result.recommendations)
                    r.contractor.id: {
                      ...result.unchecked,
                      ...r.unchecked,
                    }.toList(),
                },
                preliminary: result.preliminary,
                enabled: !controller.busy && controller.error == null,
                onReject: (id, detail) async {
                  if (mounted && controller.contextRevision == revision) {
                    await _reject(id, detail);
                  }
                },
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _error() => Semantics(
    liveRegion: true,
    child: Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.peach,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Не удалось ответить',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(controller.error!),
          const SizedBox(height: 8),
          const Text('Ваши условия сохранены.'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: controller.busy ? null : controller.retry,
                child: const Text('Повторить'),
              ),
              if (controller.service.supportsFreeText)
                TextButton(
                  onPressed: controller.busy ? null : controller.useBasicMode,
                  child: const Text('Продолжить кнопками'),
                ),
              if (widget.onOpenCatalog != null)
                TextButton(
                  onPressed: widget.onOpenCatalog,
                  child: const Text('Открыть каталог'),
                ),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _composer() {
    final freeText = controller.service.supportsFreeText;
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  key: const Key('assistant-input'),
                  controller: _input,
                  focusNode: _focus,
                  enabled: freeText,
                  maxLength: 2000,
                  minLines: 1,
                  maxLines: 3,
                  textInputAction: TextInputAction.send,
                  decoration: InputDecoration(
                    labelText: freeText
                        ? (widget.embedded
                              ? 'Кого ищете и что важно?'
                              : 'Ваше сообщение')
                        : (widget.embedded
                              ? 'Подбор по условиям'
                              : 'Подбор кнопками'),
                    hintText: freeText
                        ? 'Кого ищете и что важно?'
                        : 'Выберите ответ или измените условия',
                    counterText: '',
                  ),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => unawaited(_send()),
                ),
              ),
              if (freeText) ...[
                const SizedBox(width: 8),
                IconButton.filled(
                  key: const Key('assistant-send'),
                  tooltip: 'Отправить сообщение',
                  onPressed: controller.busy || _input.text.trim().isEmpty
                      ? null
                      : _send,
                  style: IconButton.styleFrom(minimumSize: const Size(52, 52)),
                  icon: const Icon(Icons.arrow_upward),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _inline() {
    final revision = controller.contextRevision;
    final freeText =
        controller.service.supportsFreeText && controller.turn?.mode != 'basic';
    final brief = controller.brief;
    final turn = controller.turn;
    final result = turn?.result;
    final fields = <String, String?>{
      'category': brief.category,
      'city': brief.city,
      'event_format': brief.eventFormat,
      'date': brief.date == null ? null : _displayDate(brief.date!),
      'budget_kzt': brief.budgetKzt == null
          ? null
          : 'до ${money(brief.budgetKzt!)} ₸',
      'language': brief.language,
      'hours': brief.hours == null ? null : '${brief.hours} ч',
    };
    return Column(
      key: const Key('integrated-assistant'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.lavender,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Найдём специалиста для вашего события',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              if (widget.contextHeader != null) widget.contextHeader!,
              Text(
                freeText
                    ? 'Опишите задачу одной фразой. Учтём условия и покажем до трёх вариантов.'
                    : 'Выберите условия — покажем до трёх вариантов. Текстовый AI сейчас недоступен; пожелания по стилю нужно уточнить у подрядчика.',
              ),
              if (freeText) _composer(),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final entry in fields.entries)
                    if (entry.value != null ||
                        const [
                          'category',
                          'city',
                          'event_format',
                        ].contains(entry.key))
                      ActionChip(
                        key: Key('inline-${entry.key}'),
                        avatar: const Icon(Icons.edit_outlined, size: 16),
                        label: Text(entry.value ?? _fieldName(entry.key)),
                        onPressed: controller.busy
                            ? null
                            : () => _editField(entry.key),
                      ),
                  ActionChip(
                    label: const Text('Все условия'),
                    avatar: const Icon(Icons.tune, size: 16),
                    onPressed: controller.busy
                        ? null
                        : () => showDialog<void>(
                            context: context,
                            builder: (dialogContext) => Dialog(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 440,
                                ),
                                child: SingleChildScrollView(
                                  padding: const EdgeInsets.all(16),
                                  child: ListenableBuilder(
                                    listenable: controller,
                                    builder: (_, _) => Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        _brief(
                                          compact: false,
                                          beforeFreeText: () =>
                                              Navigator.pop(dialogContext),
                                        ),
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(dialogContext),
                                          child: const Text('Готово'),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                  ),
                  if (brief.canRecommend)
                    ActionChip(
                      label: const Text('Следующий специалист'),
                      onPressed: controller.busy
                          ? null
                          : () => controller.act(
                              const AssistantAction(
                                id: 'next-category',
                                label: 'Следующий специалист',
                                type: 'next_category',
                              ),
                            ),
                    ),
                ],
              ),
              if (brief.preferences.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'Учтено: ${brief.preferences.map((p) => p.text).join('; ')}',
                ),
              ],
              if (turn == null && !brief.canRecommend) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final category in [
                      'Ведущий',
                      'Фотограф',
                      'Банкетный зал',
                    ])
                      if (controller.catalog.any(
                        (c) => c.categories.contains(category),
                      ))
                        ActionChip(
                          label: Text(category),
                          onPressed: controller.busy
                              ? null
                              : () => _setField('category', category, category),
                        ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (controller.busy)
          Semantics(
            liveRegion: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LinearProgressIndicator(),
                SizedBox(height: 8),
                Text('Проверяем условия и календарь…'),
              ],
            ),
          ),
        if (controller.error != null) _error(),
        if (turn != null) ...[
          Semantics(
            liveRegion: true,
            child: Text(
              turn.message,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          for (final warning in turn.warnings)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(warning),
            ),
          const SizedBox(height: 12),
          _actions(turn.actions),
          if (result != null) ...[
            const SizedBox(height: 20),
            AssistantRecommendations(
              recommendations: result.toMatchResult().recommendations,
              unverified: {
                for (final r in result.recommendations)
                  r.contractor.id: {
                    ...result.unchecked,
                    ...r.unchecked,
                  }.toList(),
              },
              preliminary: result.preliminary,
              enabled: !controller.busy && controller.error == null,
              onReject: (id, detail) async {
                if (mounted && controller.contextRevision == revision) {
                  await _reject(id, detail);
                }
              },
              footerBuilder: widget.cardFooterBuilder,
            ),
            if (result.recommendations.isNotEmpty &&
                widget.resultActionsBuilder != null) ...[
              const SizedBox(height: 16),
              widget.resultActionsBuilder!(_editField),
            ],
          ],
        ],
        if (controller.messages.isNotEmpty)
          ExpansionTile(
            title: const Text('История уточнений'),
            children: [
              for (final message in controller.messages)
                ListTile(
                  dense: true,
                  title: Text(message.text),
                  leading: Icon(
                    message.role == 'user'
                        ? Icons.person_outline
                        : Icons.auto_awesome_outlined,
                  ),
                ),
            ],
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => widget.embedded
      ? ListenableBuilder(listenable: controller, builder: (_, _) => _inline())
      : SafeArea(
          child: ListenableBuilder(
            listenable: controller,
            builder: (context, _) => LayoutBuilder(
              builder: (context, constraints) {
                final wide =
                    constraints.maxWidth >= 1000 &&
                    MediaQuery.textScalerOf(context).scale(16) <= 24;
                final padding = constraints.maxWidth < 600 ? 16.0 : 24.0;
                return Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1280),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(padding, 8, padding, 0),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Помощник',
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                              ),
                              if (controller.messages.isNotEmpty)
                                IconButton(
                                  tooltip: 'Начать новый подбор',
                                  onPressed: controller.busy
                                      ? null
                                      : () {
                                          controller.reset();
                                          _input.clear();
                                          setState(() {});
                                        },
                                  icon: const Icon(Icons.restart_alt),
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Expanded(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    children: [
                                      if (!wide) ...[
                                        ConstrainedBox(
                                          constraints: BoxConstraints(
                                            maxHeight:
                                                constraints.maxHeight *
                                                (constraints.maxHeight < 600
                                                    ? .2
                                                    : .35),
                                          ),
                                          child: SingleChildScrollView(
                                            child: _brief(compact: true),
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                      ],
                                      Expanded(
                                        child: ListView(
                                          controller: _scroll,
                                          keyboardDismissBehavior:
                                              ScrollViewKeyboardDismissBehavior
                                                  .onDrag,
                                          padding: const EdgeInsets.only(
                                            bottom: 16,
                                          ),
                                          children: [
                                            if (!controller
                                                .service
                                                .supportsFreeText) ...[
                                              Container(
                                                padding: const EdgeInsets.all(
                                                  16,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: AppColors.sage,
                                                  borderRadius:
                                                      BorderRadius.circular(16),
                                                ),
                                                child: const Text(
                                                  'Базовый режим · подбор по условиям кнопками. Смысл пожеланий пока не учитывается.',
                                                ),
                                              ),
                                              const SizedBox(height: 16),
                                            ],
                                            if (controller.messages.isEmpty)
                                              _welcome(),
                                            for (
                                              var i = 0;
                                              i < controller.messages.length;
                                              i++
                                            )
                                              _message(
                                                controller.messages[i],
                                                i ==
                                                    controller.messages.length -
                                                        1,
                                              ),
                                            if (controller.busy)
                                              Semantics(
                                                liveRegion: true,
                                                child: const Padding(
                                                  padding: EdgeInsets.symmetric(
                                                    vertical: 16,
                                                  ),
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .stretch,
                                                    children: [
                                                      LinearProgressIndicator(),
                                                      SizedBox(height: 12),
                                                      Text(
                                                        'Учитываю условия и проверяю варианты…',
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            if (controller.error != null)
                                              _error(),
                                          ],
                                        ),
                                      ),
                                      _composer(),
                                    ],
                                  ),
                                ),
                                if (wide) ...[
                                  const SizedBox(width: 24),
                                  SizedBox(
                                    width: 300,
                                    child: SingleChildScrollView(
                                      child: _brief(compact: false),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        );
}

String _displayDate(String value) {
  final date = DateTime.tryParse(value);
  return date == null
      ? value
      : '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
}

String _fieldName(String field) => switch (field) {
  'city' => 'Город',
  'category' => 'Специалист',
  'event_format' => 'Формат события',
  'date' => 'Дата',
  'budget_kzt' => 'Бюджет подрядчика',
  'hours' => 'Продолжительность',
  'language' => 'Язык',
  _ => field,
};

class _ValuePicker extends StatefulWidget {
  const _ValuePicker({required this.title, required this.values});
  final String title;
  final List<String> values;
  @override
  State<_ValuePicker> createState() => _ValuePickerState();
}

class _ValuePickerState extends State<_ValuePicker> {
  String query = '';
  @override
  Widget build(BuildContext context) {
    final values = widget.values
        .where((value) => value.toLowerCase().contains(query.toLowerCase()))
        .toList();
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 420,
        height: MediaQuery.sizeOf(context).height * .45,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              maxLength: 100,
              decoration: const InputDecoration(
                labelText: 'Поиск вариантов',
                counterText: '',
              ),
              onChanged: (value) => setState(() => query = value.trim()),
              onSubmitted: (value) {
                final exact = widget.values.where(
                  (option) =>
                      option.toLowerCase() == value.trim().toLowerCase(),
                );
                if (exact.length == 1) {
                  Navigator.pop(context, exact.single);
                }
              },
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView(
                children: [
                  if (values.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        'Такого варианта пока нет в каталоге. Попробуйте другой запрос.',
                      ),
                    ),
                  for (final value in values)
                    ListTile(
                      title: Text(value),
                      onTap: () => Navigator.pop(context, value),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
      ],
    );
  }
}

class _NumberDialog extends StatefulWidget {
  const _NumberDialog({required this.budget, this.initial});
  final bool budget;
  final num? initial;
  @override
  State<_NumberDialog> createState() => _NumberDialogState();
}

class _NumberDialogState extends State<_NumberDialog> {
  final _form = GlobalKey<FormState>();
  late final _value = TextEditingController(
    text: widget.initial?.toString() ?? '',
  );
  num? get value => widget.budget
      ? int.tryParse(_value.text.replaceAll(RegExp(r'\s'), ''))
      : double.tryParse(_value.text.replaceAll(',', '.'));
  void _submit() {
    if (_form.currentState!.validate()) Navigator.pop(context, value);
  }

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: Text(widget.budget ? 'Бюджет подрядчика' : 'Продолжительность'),
    content: Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.budget) ...[
            const Text(
              'Максимальная сумма для этого специалиста, не всего события.',
            ),
            const SizedBox(height: 16),
          ],
          TextFormField(
            controller: _value,
            autofocus: true,
            keyboardType: TextInputType.numberWithOptions(
              decimal: !widget.budget,
            ),
            inputFormatters: [
              FilteringTextInputFormatter.allow(
                widget.budget ? RegExp(r'[0-9\s]') : RegExp(r'[0-9.,]'),
              ),
            ],
            decoration: InputDecoration(
              labelText: widget.budget ? 'Сумма, ₸' : 'Часы',
            ),
            textInputAction: TextInputAction.done,
            validator: (_) => value == null || !value!.isFinite || value! <= 0
                ? 'Введите число больше нуля'
                : null,
            onFieldSubmitted: (_) => _submit(),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Отмена'),
      ),
      FilledButton(onPressed: _submit, child: const Text('Применить')),
    ],
  );
}
