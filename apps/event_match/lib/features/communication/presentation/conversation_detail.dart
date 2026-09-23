part of 'communication_page.dart';

class _ConversationDetail extends StatefulWidget {
  const _ConversationDetail({
    super.key,
    required this.id,
    required this.repository,
    required this.uid,
    required this.isAdmin,
    required this.onSupport,
    this.readOnly = false,
  });
  final String id, uid;
  final CommunicationRepository repository;
  final bool isAdmin, readOnly;
  final ValueChanged<String> onSupport;
  @override
  State<_ConversationDetail> createState() => _ConversationDetailState();
}

class _ConversationDetailState extends State<_ConversationDetail> {
  bool _context = false;
  int _limit = 50;

  @override
  Widget build(BuildContext context) => _ConversationStream(
    key: ValueKey('conversation:${widget.id}:${widget.uid}'),
    create: () => widget.repository.watchConversation(widget.id),
    contextReadOnly: widget.readOnly,
    builder: (context, c) {
      if (c == null) {
        return const WorkspaceEmpty(
          title: 'Переписка недоступна',
          message: 'Она удалена или у вас больше нет доступа.',
        );
      }
      final canReadContext =
          c.isSupport &&
          c.linkedInquiryId.isNotEmpty &&
          c.assignedAdminId == widget.uid &&
          widget.isAdmin &&
          c.status == 'in_progress';
      if (_context && canReadContext) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            OutlinedButton.icon(
              onPressed: () => setState(() => _context = false),
              icon: const Icon(Icons.arrow_back),
              label: const Text('К обращению'),
            ),
            const SizedBox(height: 16),
            const WorkspaceNotice(
              'Переписка по обращению. Доступ назначенного администратора действует до закрытия обращения или замены доступа новым обращением по этой заявке.',
            ),
            _ConversationDetail(
              key: ValueKey('context:${c.linkedInquiryId}'),
              id: c.linkedInquiryId,
              repository: widget.repository,
              uid: widget.uid,
              isAdmin: widget.isAdmin,
              readOnly: true,
              onSupport: widget.onSupport,
            ),
          ],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          WorkspaceCard(
            color: c.isSupport ? AppColors.blue : AppColors.lavender,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(c.subject, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                Text(
                  c.isSupport
                      ? 'Обращение: ${c.clientName} · Поддержка'
                      : '${c.clientName} · ${c.contractorName}',
                ),
                const SizedBox(height: 8),
                Text(
                  c.statusLabel,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                if (!c.isSupport) ...[
                  const SizedBox(height: 16),
                  _EventSummary(c.eventSnapshot),
                  const SizedBox(height: 8),
                  const Text('Сведения на момент отправки заявки.'),
                ],
                if (!widget.readOnly) ...[
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (final status in c.transitionsFor(
                        widget.uid,
                        isAdmin: widget.isAdmin,
                      ))
                        _SafeAction(
                          key: ValueKey('status:$status:${c.revision}'),
                          label: _transitionLabel(status),
                          run: () => widget.repository.changeStatus(
                            conversationId: c.id,
                            uid: widget.uid,
                            status: status,
                            expectedRevision: c.revision,
                          ),
                        ),
                      if (!c.isSupport && c.participantIds.contains(widget.uid))
                        OutlinedButton.icon(
                          onPressed: () => widget.onSupport(c.id),
                          icon: const Icon(Icons.support_agent_outlined),
                          label: const Text('Обратиться в поддержку'),
                        ),
                      if (canReadContext)
                        OutlinedButton.icon(
                          onPressed: () => setState(() => _context = true),
                          icon: const Icon(Icons.article_outlined),
                          label: const Text('Открыть контекст'),
                        ),
                    ],
                  ),
                ],
                if (c.isSupport && c.linkedInquiryId.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'К обращению приложена переписка по заявке. Только назначенный администратор может читать её во время работы. При закрытии обращения или создании нового обращения по той же заявке этот доступ прекращается, а доступ по новому обращению получает его назначенный администратор.',
                  ),
                ],
              ],
            ),
          ),
          if (c.isSupport)
            ExpansionTile(
              title: const Text('Журнал обращения'),
              tilePadding: EdgeInsets.zero,
              children: [
                WorkspaceStream<List<CommunicationAudit>>(
                  key: ValueKey('audit:${c.id}:${widget.uid}'),
                  create: () => widget.repository.watchAudit(c.id),
                  builder: (context, entries) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final entry in entries)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            '${_auditLabel(entry.action)} · ${entry.actorId == widget.uid ? 'Вы' : 'Участник обращения'}\n${_time(entry.createdAt)}',
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          const SizedBox(height: 16),
          Text('Переписка', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          WorkspaceStream<List<ConversationMessage>>(
            key: ValueKey('messages:${c.id}:${widget.uid}:$_limit'),
            create: () => widget.repository.watchMessages(c.id, limit: _limit),
            builder: (context, messages) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (messages.length >= _limit &&
                    (messages.firstOrNull?.sequence ?? 0) > 1)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: OutlinedButton(
                      onPressed: () => setState(() => _limit += 50),
                      child: const Text('Загрузить предыдущие сообщения'),
                    ),
                  ),
                if (messages.isEmpty)
                  const WorkspaceNotice('Сообщений пока нет.'),
                _VisibleMessages(
                  key: ValueKey('visible:${c.id}:${widget.uid}'),
                  conversation: c,
                  messages: messages,
                  repository: widget.repository,
                  uid: widget.uid,
                  canMarkRead:
                      !widget.readOnly &&
                      (c.participantIds.contains(widget.uid) ||
                          c.assignedAdminId == widget.uid),
                ),
              ],
            ),
          ),
          if (!widget.readOnly &&
              c.canSend(widget.uid, isAdmin: widget.isAdmin))
            _MessageComposer(
              key: ValueKey('composer:${c.id}:${widget.uid}'),
              conversationId: c.id,
              repository: widget.repository,
              uid: widget.uid,
            )
          else
            WorkspaceNotice(
              c.isTerminal
                  ? 'Переписка закрыта. История сообщений сохранена.'
                  : widget.readOnly
                  ? 'Контекст доступен только для чтения.'
                  : 'Возьмите обращение в работу, чтобы ответить.',
            ),
        ],
      );
    },
  );
}

/// On a denied context read, never retain the last private snapshot.
class _ConversationStream extends StatefulWidget {
  const _ConversationStream({
    super.key,
    required this.create,
    required this.builder,
    required this.contextReadOnly,
  });
  final Stream<Conversation?> Function() create;
  final Widget Function(BuildContext, Conversation?) builder;
  final bool contextReadOnly;

  @override
  State<_ConversationStream> createState() => _ConversationStreamState();
}

class _ConversationStreamState extends State<_ConversationStream> {
  late Stream<Conversation?> _stream = widget.create();

  @override
  Widget build(BuildContext context) => StreamBuilder<Conversation?>(
    stream: _stream,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return WorkspaceEmpty(
          title: widget.contextReadOnly
              ? 'Контекст недоступен'
              : 'Не удалось загрузить данные',
          message: widget.contextReadOnly
              ? 'Обращение могло быть закрыто, передано другому администратору или заменено новым обращением по этой заявке. Вернитесь к обращению. Если дело в подключении, повторите загрузку.'
              : 'Проверьте подключение и права доступа. Данные не потеряны.',
          icon: Icons.cloud_off_outlined,
          action: OutlinedButton.icon(
            onPressed: () => setState(() => _stream = widget.create()),
            icon: const Icon(Icons.refresh),
            label: const Text('Повторить'),
          ),
        );
      }
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: CircularProgressIndicator()),
        );
      }
      return widget.builder(context, snapshot.data);
    },
  );
}

String _transitionLabel(String value) => switch (value) {
  'discussing' => 'Принять к обсуждению',
  'declined' => 'Отклонить заявку',
  'cancelled' => 'Отменить заявку',
  'closed' => 'Закрыть заявку',
  'in_progress' => 'Взять в работу',
  'resolved' => 'Завершить обращение',
  _ => value,
};

String _auditLabel(String value) => switch (value) {
  'opened' || 'created' => 'Обращение создано',
  'claimed' || 'in_progress' => 'Администратор принял обращение',
  'resolved' => 'Обращение закрыто, доступ к контексту завершён',
  _ => 'Статус обращения обновлён',
};

class _VisibleMessages extends StatefulWidget {
  const _VisibleMessages({
    super.key,
    required this.conversation,
    required this.messages,
    required this.repository,
    required this.uid,
    required this.canMarkRead,
  });
  final Conversation conversation;
  final List<ConversationMessage> messages;
  final CommunicationRepository repository;
  final String uid;
  final bool canMarkRead;
  @override
  State<_VisibleMessages> createState() => _VisibleMessagesState();
}

class _VisibleMessagesState extends State<_VisibleMessages> {
  final _keys = <String, GlobalKey>{};
  ScrollPosition? _position;
  int _marked = 0;
  bool _scheduled = false, _writing = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final position = Scrollable.maybeOf(context)?.position;
    if (_position != position) {
      _position?.removeListener(_schedule);
      _position = position;
      _position?.addListener(_schedule);
    }
    _schedule();
  }

  @override
  void didUpdateWidget(covariant _VisibleMessages oldWidget) {
    super.didUpdateWidget(oldWidget);
    _schedule();
  }

  @override
  void dispose() {
    _position?.removeListener(_schedule);
    super.dispose();
  }

  void _schedule() {
    if (_scheduled || !widget.canMarkRead) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (mounted) _markVisible();
    });
  }

  Future<void> _markVisible() async {
    if (_writing || !widget.canMarkRead) return;
    var seen = _marked;
    for (final message in widget.messages) {
      final box = _keys[message.id]?.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.attached || !box.hasSize) continue;
      final viewport = RenderAbstractViewport.maybeOf(box);
      final bounds = viewport is RenderBox
          ? (viewport as RenderBox).localToGlobal(Offset.zero) &
                (viewport as RenderBox).size
          : Offset.zero & MediaQuery.sizeOf(context);
      final messageBounds = box.localToGlobal(Offset.zero) & box.size;
      // A rendered widget below the viewport is not a read message.
      if (bounds.overlaps(messageBounds) && message.sequence > seen) {
        seen = message.sequence;
      }
    }
    if (seen <= _marked) return;
    _writing = true;
    try {
      await widget.repository.markRead(
        widget.conversation.id,
        widget.uid,
        seen,
      );
      _marked = seen;
    } catch (_) {
      // A failed receipt must never turn a message into a confirmed read.
      // The next visible scroll/update retries the same delivered sequence.
    } finally {
      _writing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    _schedule();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final message in widget.messages)
          WorkspaceCard(
            key: _keys.putIfAbsent(message.id, GlobalKey.new),
            color: message.senderId == widget.uid
                ? AppColors.sage
                : AppColors.white,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message.senderId == widget.uid
                      ? 'Вы'
                      : widget.conversation.isSupport
                      ? (message.senderId == widget.conversation.clientId
                            ? widget.conversation.clientName
                            : 'Администратор поддержки')
                      : (message.senderId == widget.conversation.clientId
                            ? widget.conversation.clientName
                            : widget.conversation.contractorName),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                SelectableText(message.text),
                const SizedBox(height: 8),
                Text(
                  _time(message.createdAt),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _MessageComposer extends StatefulWidget {
  const _MessageComposer({
    super.key,
    required this.conversationId,
    required this.repository,
    required this.uid,
  });
  final String conversationId, uid;
  final CommunicationRepository repository;
  @override
  State<_MessageComposer> createState() => _MessageComposerState();
}

class _MessageComposerState extends State<_MessageComposer> {
  final _text = TextEditingController();
  final _form = GlobalKey<FormState>();
  String? _pendingId, _pendingText;
  bool _busy = false, _failed = false;
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _startNew() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: const Text('Начать новое сообщение?'),
        content: const Text(
          'Доставка предыдущего сообщения пока не подтверждена: оно могло быть получено. Для проверки и отправки без копии используйте повторную попытку. Новое сообщение отправится отдельно.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Оставить текущий текст'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Начать новое'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    setState(() {
      _pendingId = null;
      _pendingText = null;
      _failed = false;
      _text.clear();
    });
  }

  Future<void> _send() async {
    if (!_form.currentState!.validate()) return;
    _pendingId ??= widget.repository.newId();
    _pendingText ??= _text.text.trim();
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      await widget.repository.sendMessage(
        conversationId: widget.conversationId,
        messageId: _pendingId!,
        uid: widget.uid,
        text: _pendingText!,
      );
      if (mounted) {
        _text.clear();
        _pendingId = null;
        _pendingText = null;
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => WorkspaceCard(
    child: Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFormField(
            key: const Key('message-draft'),
            controller: _text,
            readOnly: _busy || _failed,
            minLines: 2,
            maxLines: 8,
            maxLength: 4000,
            decoration: const InputDecoration(labelText: 'Сообщение'),
            validator: (v) =>
                (v ?? '').trim().isEmpty ? 'Напишите сообщение' : null,
          ),
          if (_failed)
            const WorkspaceNotice(
              'Доставка не подтверждена. Текст сохранён. Повторите отправку этого сообщения.',
              error: true,
            ),
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const Key('message-send'),
            onPressed: _busy ? null : _send,
            icon: const Icon(Icons.send_outlined),
            label: Text(
              _busy
                  ? 'Отправляем…'
                  : _failed
                  ? 'Повторить отправку'
                  : 'Отправить сообщение',
            ),
          ),
          if (_failed)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: TextButton(
                onPressed: _busy ? null : _startNew,
                child: const Text('Начать новое сообщение'),
              ),
            ),
        ],
      ),
    ),
  );
}
