part of 'communication_page.dart';

class _ConversationForm extends StatefulWidget {
  const _ConversationForm({
    super.key,
    required this.repository,
    required this.workspace,
    required this.uid,
    required this.support,
    required this.onCreated,
    this.linkedInquiryId,
    this.initialContractorId,
    this.initialEventId,
    this.onOpenEvents,
  });
  final CommunicationRepository repository;
  final WorkspaceRepository workspace;
  final String uid;
  final bool support;
  final String? linkedInquiryId, initialContractorId, initialEventId;
  final ValueChanged<String> onCreated;
  final VoidCallback? onOpenEvents;
  @override
  State<_ConversationForm> createState() => _ConversationFormState();
}

class _ConversationFormState extends State<_ConversationForm> {
  final _form = GlobalKey<FormState>();
  final _subject = TextEditingController();
  final _text = TextEditingController();
  late final String _id = widget.repository.newId();
  late Future<(List<ClientEvent>, List<PublishedProfile>)> _data = _load();
  String? _eventId, _contractorId, _category;
  bool _consent = false, _busy = false, _failed = false, _attempted = false;

  Future<(List<ClientEvent>, List<PublishedProfile>)> _load() async {
    if (widget.support) return (<ClientEvent>[], <PublishedProfile>[]);
    final results = await Future.wait([
      widget.workspace.listEvents(widget.uid),
      widget.workspace.listPublished(),
    ]);
    final events = results[0] as List<ClientEvent>;
    final profiles = (results[1] as List<PublishedProfile>)
        .where(
          (p) =>
              p.published &&
              p.ownerId != widget.uid &&
              p.content.categories.isNotEmpty,
        )
        .toList();
    _eventId = events.any((e) => e.id == widget.initialEventId)
        ? widget.initialEventId
        : (events.length == 1 ? events.first.id : null);
    _contractorId = profiles.any((p) => p.ownerId == widget.initialContractorId)
        ? widget.initialContractorId
        : null;
    final selected = profiles
        .where((p) => p.ownerId == _contractorId)
        .firstOrNull;
    _category = selected?.content.categories.firstOrNull;
    return (events, profiles);
  }

  @override
  void dispose() {
    _subject.dispose();
    _text.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    if (widget.linkedInquiryId != null && !_consent) {
      setState(() => _attempted = true);
      return;
    }
    setState(() {
      _busy = true;
      _failed = false;
      _attempted = true;
    });
    try {
      if (widget.support) {
        await widget.repository.createSupport(
          id: _id,
          uid: widget.uid,
          subject: _subject.text.trim(),
          text: _text.text.trim(),
          linkedInquiryId: widget.linkedInquiryId ?? '',
        );
      } else {
        await widget.repository.createInquiry(
          id: _id,
          uid: widget.uid,
          contractorId: _contractorId!,
          eventId: _eventId!,
          category: _category!,
          text: _text.text.trim(),
        );
      }
      if (mounted) widget.onCreated(_id);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(
    BuildContext context,
  ) => FutureBuilder<(List<ClientEvent>, List<PublishedProfile>)>(
    future: _data,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return WorkspaceEmpty(
          title: 'Не удалось подготовить форму',
          message: 'Проверьте подключение и повторите загрузку.',
          action: OutlinedButton(
            onPressed: () => setState(() => _data = _load()),
            child: const Text('Повторить'),
          ),
        );
      }
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      final (events, profiles) = snapshot.data!;
      if (!widget.support && events.isEmpty) {
        return WorkspaceEmpty(
          title: 'Сначала добавьте мероприятие',
          message: 'Подрядчик получит дату, город, формат и ваши пожелания.',
          action: widget.onOpenEvents == null
              ? null
              : FilledButton(
                  onPressed: widget.onOpenEvents,
                  child: const Text('Мои мероприятия'),
                ),
        );
      }
      if (!widget.support && profiles.isEmpty) {
        return const WorkspaceEmpty(
          title: 'Пока нет доступных подрядчиков',
          message: 'Заявки можно отправлять опубликованным реальным профилям.',
        );
      }
      final event = events.where((e) => e.id == _eventId).firstOrNull;
      final provider = profiles
          .where((p) => p.ownerId == _contractorId)
          .firstOrNull;
      final locked = _busy || _failed;
      return WorkspaceCard(
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.support ? 'Новое обращение' : 'Новая заявка',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              if (!widget.support) ...[
                DropdownButtonFormField<String>(
                  key: const Key('inquiry-event'),
                  initialValue: _eventId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Мероприятие'),
                  items: [
                    for (final e in events)
                      DropdownMenuItem(
                        value: e.id,
                        child: Text(e.name, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: locked
                      ? null
                      : (id) => setState(() => _eventId = id),
                  validator: (v) => v == null ? 'Выберите мероприятие' : null,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  key: const Key('inquiry-contractor'),
                  initialValue: _contractorId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Подрядчик'),
                  items: [
                    for (final p in profiles)
                      DropdownMenuItem(
                        value: p.ownerId,
                        child: Text(
                          p.content.name,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: locked
                      ? null
                      : (id) => setState(() {
                          _contractorId = id;
                          _category = profiles
                              .firstWhere((p) => p.ownerId == id)
                              .content
                              .categories
                              .first;
                        }),
                  validator: (v) => v == null ? 'Выберите подрядчика' : null,
                ),
                if (provider != null) ...[
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    key: ValueKey('inquiry-category:$_contractorId'),
                    initialValue: _category,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Услуга'),
                    items: [
                      for (final c in provider.content.categories.toSet())
                        DropdownMenuItem(
                          value: c,
                          child: Text(c, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: locked
                        ? null
                        : (v) => setState(() => _category = v),
                    validator: (v) => v == null ? 'Выберите услугу' : null,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Получатель: ${provider.content.name}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
                if (event != null) ...[
                  const SizedBox(height: 16),
                  _EventSummary(event.toMap()),
                  const SizedBox(height: 8),
                  const Text(
                    'Эти сведения будут сохранены в заявке и доступны подрядчику.',
                  ),
                ],
              ] else ...[
                TextFormField(
                  key: const Key('support-subject'),
                  controller: _subject,
                  readOnly: locked,
                  maxLength: 120,
                  decoration: const InputDecoration(
                    labelText: 'Тема обращения',
                  ),
                  validator: (v) =>
                      (v ?? '').trim().isEmpty ? 'Укажите тему' : null,
                ),
              ],
              const SizedBox(height: 16),
              TextFormField(
                key: const Key('conversation-first-message'),
                controller: _text,
                readOnly: locked,
                minLines: 3,
                maxLines: 8,
                maxLength: 4000,
                decoration: InputDecoration(
                  labelText: widget.support
                      ? 'Как мы можем помочь?'
                      : 'Сообщение подрядчику',
                ),
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? 'Напишите сообщение' : null,
              ),
              if (widget.linkedInquiryId != null) ...[
                CheckboxListTile(
                  key: const Key('support-consent'),
                  contentPadding: EdgeInsets.zero,
                  value: _consent,
                  controlAffinity: ListTileControlAffinity.leading,
                  onChanged: locked
                      ? null
                      : (v) => setState(() => _consent = v ?? false),
                  title: const Text(
                    'Разрешаю поддержке прочитать переписку по этой заявке',
                  ),
                  subtitle: const Text(
                    'Доступ получит только назначенный администратор этого обращения. Новое обращение заменит доступ по предыдущему: его администратор больше не сможет читать эту переписку. Доступ действует до закрытия обращения или создания нового обращения по той же заявке. Изменения доступа фиксируются в журнале.',
                  ),
                ),
                if (_attempted && !_consent)
                  const Text('Для передачи переписки нужно ваше согласие.'),
              ],
              if (_failed)
                const WorkspaceNotice(
                  'Отправка не подтверждена. Сообщение сохранено в форме. Повторите отправку: повторная попытка не создаст копию.',
                  error: true,
                ),
              const SizedBox(height: 16),
              FilledButton.icon(
                key: const Key('conversation-submit'),
                onPressed: _busy ? null : _submit,
                icon: const Icon(Icons.send_outlined),
                label: Text(
                  _busy
                      ? 'Отправляем…'
                      : _failed
                      ? 'Повторить отправку'
                      : 'Отправить',
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
