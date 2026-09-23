import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../app/design_tokens.dart';
import '../../workspace/domain/workspace_models.dart';
import '../../workspace/domain/workspace_repository.dart';
import '../../workspace/presentation/workspace_widgets.dart';
import '../domain/communication_models.dart';
import '../domain/communication_repository.dart';

part 'communication_forms.dart';
part 'conversation_detail.dart';

/// Content only; AccountShell provides the page scroll and session boundary.
class CommunicationPage extends StatefulWidget {
  const CommunicationPage({
    super.key,
    required this.repository,
    required this.workspace,
    required this.uid,
    required this.mode,
    this.isAdmin = false,
    this.initialConversationId,
    this.initialContractorId,
    this.initialEventId,
    this.onSelectConversation,
    this.onOpenEvents,
  });

  final CommunicationRepository repository;
  final WorkspaceRepository workspace;
  final String uid;
  final CommunicationMode mode;
  final bool isAdmin;
  final String? initialConversationId, initialContractorId, initialEventId;
  final ValueChanged<String>? onSelectConversation;
  final VoidCallback? onOpenEvents;

  @override
  State<CommunicationPage> createState() => _CommunicationPageState();
}

class _CommunicationPageState extends State<CommunicationPage> {
  String? _selected;
  bool _creating = false;
  String? _linkedInquiry;
  int _limit = 50;
  int _epoch = 0;

  @override
  void initState() {
    super.initState();
    _reset();
  }

  void _reset() {
    _selected = (widget.initialConversationId?.trim().isEmpty ?? true)
        ? null
        : widget.initialConversationId!.trim();
    _creating =
        (widget.initialContractorId?.trim().isNotEmpty ?? false) &&
        _selected == null;
    _linkedInquiry = null;
    _limit = 50;
    _epoch++;
  }

  @override
  void didUpdateWidget(covariant CommunicationPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uid != widget.uid ||
        oldWidget.repository != widget.repository ||
        oldWidget.workspace != widget.workspace ||
        oldWidget.mode != widget.mode ||
        oldWidget.isAdmin != widget.isAdmin) {
      _reset();
    } else if (oldWidget.initialConversationId !=
            widget.initialConversationId ||
        oldWidget.initialContractorId != widget.initialContractorId ||
        oldWidget.initialEventId != widget.initialEventId) {
      _reset();
    }
  }

  void _open(String id) {
    setState(() {
      _selected = id;
      _creating = false;
      _linkedInquiry = null;
    });
    widget.onSelectConversation?.call(id);
  }

  void _back() {
    setState(() {
      _selected = null;
      _creating = false;
      _linkedInquiry = null;
      _epoch++;
    });
    widget.onSelectConversation?.call('');
  }

  bool _matches(Conversation c) => switch (widget.mode) {
    CommunicationMode.client => !c.isSupport && c.clientId == widget.uid,
    CommunicationMode.contractor =>
      !c.isSupport && c.contractorId == widget.uid,
    CommunicationMode.support => c.isSupport && c.clientId == widget.uid,
    CommunicationMode.admin => c.isSupport,
  };

  @override
  Widget build(BuildContext context) {
    if (widget.mode == CommunicationMode.admin && !widget.isAdmin) {
      return const WorkspaceNotice(
        'Очередь поддержки доступна администратору.',
      );
    }
    return KeyedSubtree(
      key: ValueKey('${widget.uid}:$_epoch'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          WorkspaceHeading(
            switch (widget.mode) {
              CommunicationMode.client => 'Заявки и сообщения',
              CommunicationMode.contractor => 'Входящие заявки',
              CommunicationMode.support => 'Поддержка',
              CommunicationMode.admin => 'Очередь поддержки',
            },
            widget.mode == CommunicationMode.admin
                ? 'Возьмите обращение в работу, чтобы ответить и помочь.'
                : 'Все договорённости и вопросы — в одном разговоре.',
          ),
          if (_creating || _selected != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: OutlinedButton.icon(
                onPressed: _back,
                icon: const Icon(Icons.arrow_back),
                label: const Text('К списку'),
              ),
            ),
          if (_creating)
            _ConversationForm(
              key: ValueKey('form:$_epoch:${_linkedInquiry ?? ''}'),
              repository: widget.repository,
              workspace: widget.workspace,
              uid: widget.uid,
              support:
                  _linkedInquiry != null ||
                  widget.mode == CommunicationMode.support,
              linkedInquiryId: _linkedInquiry,
              initialContractorId: widget.initialContractorId,
              initialEventId: widget.initialEventId,
              onCreated: _open,
              onOpenEvents: widget.onOpenEvents,
            )
          else if (_selected != null)
            _ConversationDetail(
              key: ValueKey('detail:$_selected'),
              id: _selected!,
              repository: widget.repository,
              uid: widget.uid,
              isAdmin: widget.isAdmin,
              onSupport: (id) => setState(() {
                _linkedInquiry = id;
                _creating = true;
                _epoch++;
              }),
            )
          else ...[
            if (widget.mode == CommunicationMode.client ||
                widget.mode == CommunicationMode.support)
              Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: FilledButton.icon(
                  key: const Key('communication-create'),
                  onPressed: () => setState(() {
                    _creating = true;
                    _epoch++;
                  }),
                  icon: const Icon(Icons.add_comment_outlined),
                  label: Text(
                    widget.mode == CommunicationMode.support
                        ? 'Написать в поддержку'
                        : 'Новая заявка',
                  ),
                ),
              ),
            WorkspaceStream<List<Conversation>>(
              key: ValueKey('inbox:$_limit'),
              create: () => widget.repository.watchInbox(
                widget.uid,
                supportQueue: widget.mode == CommunicationMode.admin,
                limit: _limit,
              ),
              builder: (context, all) {
                final conversations = all.where(_matches).toList();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (conversations.isEmpty)
                      const WorkspaceEmpty(
                        title: 'Пока нет сообщений',
                        message: 'Новые заявки и ответы появятся здесь.',
                        icon: Icons.chat_bubble_outline,
                      ),
                    for (final c in conversations)
                      WorkspaceCard(
                        key: ValueKey('conversation:${c.id}'),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              c.subject,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              c.isSupport
                                  ? (widget.mode == CommunicationMode.admin
                                        ? c.clientName
                                        : 'Администратор поддержки')
                                  : (widget.uid == c.clientId
                                        ? c.contractorName
                                        : c.clientName),
                            ),
                            const SizedBox(height: 8),
                            Text(c.statusLabel),
                            const SizedBox(height: 8),
                            WorkspaceStream<int>(
                              key: ValueKey('unread:${c.id}:${widget.uid}'),
                              create: () => widget.repository.watchReadSequence(
                                c.id,
                                widget.uid,
                              ),
                              builder: (context, read) =>
                                  c.lastSenderId != widget.uid &&
                                      c.messageCount > read
                                  ? Semantics(
                                      liveRegion: true,
                                      child: Text(
                                        'Есть непрочитанные сообщения',
                                        key: ValueKey('unread:${c.id}'),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    )
                                  : const SizedBox.shrink(),
                            ),
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              key: ValueKey('open:${c.id}'),
                              onPressed: () => _open(c.id),
                              icon: const Icon(Icons.chat_bubble_outline),
                              label: const Text('Открыть переписку'),
                            ),
                          ],
                        ),
                      ),
                    if (all.length >= _limit)
                      OutlinedButton(
                        onPressed: () => setState(() => _limit += 50),
                        child: const Text('Загрузить ещё'),
                      ),
                  ],
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _EventSummary extends StatelessWidget {
  const _EventSummary(this.value);
  final Map<String, dynamic> value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        value['name']?.toString() ?? 'Мероприятие',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 8),
      Text('${value['city'] ?? ''} · ${value['format'] ?? ''}'),
      Text('Дата: ${_eventDate(value['date'])}'),
      if ((value['preferences']?.toString() ?? '').isNotEmpty)
        Text('Пожелания: ${value['preferences']}'),
    ],
  );
}

String _eventDate(dynamic value) {
  final date = value is DateTime ? value : DateTime.tryParse('$value');
  return date == null ? 'Не указана' : workspaceDate(date);
}

String _time(DateTime? date) => date == null
    ? 'Время уточняется'
    : '${workspaceDate(date)} · ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

class _SafeAction extends StatefulWidget {
  const _SafeAction({super.key, required this.label, required this.run});
  final String label;
  final Future<void> Function() run;
  @override
  State<_SafeAction> createState() => _SafeActionState();
}

class _SafeActionState extends State<_SafeAction> {
  bool _busy = false, _failed = false;
  Future<void> _run() async {
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      await widget.run();
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      OutlinedButton.icon(
        onPressed: _busy ? null : _run,
        icon: const Icon(Icons.check),
        label: Text(_busy ? 'Сохраняем…' : widget.label),
      ),
      if (_failed)
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text(
            'Изменение не подтверждено. Обновите данные и повторите.',
          ),
        ),
    ],
  );
}
