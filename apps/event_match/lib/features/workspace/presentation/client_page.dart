import 'package:flutter/material.dart';
import '../../matching/domain/models.dart';
import '../../matching/presentation/widgets/contractor_card.dart';
import '../../matching/presentation/widgets/order_filters.dart';
import '../data/workspace_catalog_repository.dart';
import '../domain/workspace_models.dart';
import '../domain/workspace_repository.dart';
import 'workspace_widgets.dart';

class ClientPage extends StatefulWidget {
  const ClientPage({
    super.key,
    required this.repository,
    required this.uid,
    this.section = 'events',
  });
  final WorkspaceRepository repository;
  final String uid, section;
  @override
  State<ClientPage> createState() => _ClientPageState();
}

class _ClientData {
  const _ClientData(
    this.events,
    this.selections,
    this.favorites,
    this.published,
    this.calendars,
  );
  final List<ClientEvent> events;
  final List<SavedSelection> selections;
  final List<Contractor> favorites;
  final Map<String, PublishedProfile> published;
  final Map<String, CalendarMonth?> calendars;
}

class _ClientPageState extends State<ClientPage> {
  late Future<_ClientData> future = _load();
  Future<_ClientData> _load() async {
    final values = await Future.wait<dynamic>([
      widget.repository.listEvents(widget.uid),
      widget.repository.listSelections(widget.uid),
      widget.repository.listFavorites(widget.uid),
      widget.repository.listPublished(),
    ]);
    final events = values[0] as List<ClientEvent>;
    final selections = values[1] as List<SavedSelection>;
    final favorites = values[2] as List<Contractor>;
    final published = {
      for (final p in values[3] as List<PublishedProfile>) p.ownerId: p,
    };
    final needed = <String, ({String uid, DateTime date})>{};
    for (final s in selections) {
      for (final e in s.entries) {
        if (published.containsKey(e.contractor.id)) {
          needed[_calendarKey(e.contractor.id, s.request.date)] = (
            uid: e.contractor.id,
            date: s.request.date,
          );
        }
      }
    }
    final calendars = <String, CalendarMonth?>{};
    await Future.wait(
      needed.entries.map((e) async {
        calendars[e.key] = await widget.repository.getCalendar(
          e.value.uid,
          e.value.date,
        );
      }),
    );
    return _ClientData(events, selections, favorites, published, calendars);
  }

  String _calendarKey(String uid, DateTime date) =>
      '${uid}_${date.year}-${date.month}';
  void reload() {
    if (mounted) {
      setState(() {
        future = _load();
      });
    }
  }

  @override
  void didUpdateWidget(ClientPage old) {
    super.didUpdateWidget(old);
    if (old.uid != widget.uid || old.section != widget.section) reload();
  }

  Future<void> _editEvent([ClientEvent? event]) async {
    final value = await showDialog<ClientEvent>(
      context: context,
      builder: (context) => EventEditor(event: event),
    );
    if (value == null || !mounted) return;
    await widget.repository.saveEvent(widget.uid, value);
    reload();
  }

  Future<MatchRequest?> _conditions(
    ClientEvent event, {
    MatchRequest? previous,
  }) async {
    if (!MatchDatePolicy.live().contains(event.date)) {
      throw StateError('Выберите будущую дату в мероприятии');
    }
    final catalog = await WorkspaceCatalogRepository(widget.repository).load();
    if (!mounted) return null;
    return showDialog<MatchRequest>(
      context: context,
      builder: (context) {
        final content = OrderFilters(
          catalog: catalog,
          supportsPreferences: false,
          lockEventDetails: true,
          datePolicy: MatchDatePolicy.live(),
          initial: MatchRequest(
            city: event.city,
            date: event.date,
            format: event.format,
            category: previous?.category ?? 'Ведущий',
            budget: previous?.budget ?? 1000000,
            hours: previous?.hours,
            language: previous?.language,
            preferences: event.preferences,
          ),
        );
        return MediaQuery.sizeOf(context).width < 700
            ? Dialog.fullscreen(child: content)
            : Dialog(
                child: SizedBox(
                  width: 480,
                  height: MediaQuery.sizeOf(context).height - 64,
                  child: content,
                ),
              );
      },
    );
  }

  Future<void> _pick(ClientEvent event, {SavedSelection? saved}) async {
    final request = await _conditions(event, previous: saved?.request);
    if (request == null || !mounted) return;
    final result = await LiveRecommendationService(
      widget.repository,
    ).recommend(request);
    if (!mounted) return;
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Результат подбора'),
        content: SingleChildScrollView(
          child: SizedBox(
            width: 700,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(result.summary),
                const SizedBox(height: 16),
                for (final r in result.recommendations)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: ContractorCard(
                      contractor: r.contractor,
                      explanation: r.explanation,
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Закрыть'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              saved == null ? 'Сохранить подборку' : 'Обновить сохранённую',
            ),
          ),
        ],
      ),
    );
    if (save != true || !mounted) return;
    await widget.repository.saveSelection(
      widget.uid,
      SavedSelection(
        id: saved?.id ?? '',
        eventId: event.id,
        name: '${request.category} · ${event.name}',
        request: request,
        entries: result.recommendations,
      ),
    );
    reload();
  }

  Future<bool> _confirmDelete(String name) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Удалить?'),
          content: Text(name),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Удалить'),
            ),
          ],
        ),
      ) ??
      false;
  Widget _events(_ClientData data) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const WorkspaceHeading(
        'Мои мероприятия',
        'Сохраните условия события и соберите подборки по каждой категории.',
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: WorkspaceAction(
          label: 'Создать мероприятие',
          icon: Icons.add,
          onPressed: () => _editEvent(),
        ),
      ),
      const SizedBox(height: 24),
      if (data.events.isEmpty)
        const WorkspaceEmpty(
          title: 'Начните с вашего события',
          message:
              'Название, дата, город и формат помогут возвращаться к подбору без повторного заполнения.',
        ),
      for (final e in data.events)
        WorkspaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(e.name, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text('${workspaceDate(e.date)} · ${e.city} · ${e.format}'),
              if (e.preferences.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(e.preferences),
                ),
              const SizedBox(height: 12),
              Text(
                'Подборок: ${data.selections.where((s) => s.eventId == e.id).length}',
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  WorkspaceAction(
                    label: 'Подобрать подрядчиков',
                    icon: Icons.search,
                    onPressed: MatchDatePolicy.live().contains(e.date)
                        ? () => _pick(e)
                        : null,
                  ),
                  WorkspaceAction(
                    label: 'Изменить',
                    icon: Icons.edit_outlined,
                    outlined: true,
                    onPressed: () => _editEvent(e),
                  ),
                  WorkspaceAction(
                    label: 'Удалить',
                    icon: Icons.delete_outline,
                    outlined: true,
                    onPressed: () async {
                      if (await _confirmDelete(e.name)) {
                        await widget.repository.deleteEvent(widget.uid, e.id);
                        reload();
                      }
                    },
                  ),
                ],
              ),
              if (!MatchDatePolicy.live().contains(e.date))
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text(
                    'Для нового подбора измените дату мероприятия. Сохранённые результаты остаются в истории.',
                  ),
                ),
            ],
          ),
        ),
    ],
  );
  List<String> _changes(SavedSelection s, _ClientData data) {
    final changes = <String>[];
    final event = data.events.where((e) => e.id == s.eventId).firstOrNull;
    if (event == null) {
      changes.add('Мероприятие удалено');
    } else if (event.city != s.request.city ||
        dateKey(event.date) != dateKey(s.request.date) ||
        event.format != s.request.format ||
        event.preferences != s.request.preferences) {
      changes.add('Условия мероприятия изменились');
    }
    for (final r in s.entries) {
      final id = r.contractor.id;
      final current = data.published[id];
      if (current == null) {
        changes.add('${r.contractor.name}: карточка снята с публикации');
        continue;
      }
      if (current.content.price != r.contractor.price) {
        changes.add(
          '${r.contractor.name}: цена теперь от ${money(current.content.price)} ₸',
        );
      }
      final status =
          data.calendars[_calendarKey(id, s.request.date)]?.availabilityOn(
            s.request.date,
            DateTime.now(),
          ) ??
          AvailabilityStatus.unconfirmed;
      if (status != AvailabilityStatus.available) {
        changes.add(
          '${r.contractor.name}: ${status == AvailabilityStatus.busy ? 'дата занята' : 'доступность не подтверждена'}',
        );
      }
    }
    return changes;
  }

  Widget _selections(_ClientData data) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const WorkspaceHeading(
        'Сохранённые подборки',
        'Это снимки результатов на момент сохранения. Цена и доступность проверяются заново при обновлении.',
      ),
      if (data.selections.isEmpty)
        const WorkspaceEmpty(
          title: 'Подборок пока нет',
          message:
              'Откройте мероприятие или каталог, выполните подбор и сохраните результат.',
        ),
      for (final s in data.selections) _selection(s, data),
    ],
  );
  Widget _selection(SavedSelection s, _ClientData data) {
    final changes = _changes(s, data);
    final event = data.events.where((e) => e.id == s.eventId).firstOrNull;
    return WorkspaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(s.name, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            '${dateKey(s.request.date)} · ${s.request.city} · бюджет категории до ${money(s.request.budget)} ₸',
          ),
          Text('Сохранено: ${workspaceDate(s.savedAt)}'),
          if (changes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: WorkspaceNotice(changes.join('\n')),
            ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              WorkspaceAction(
                label: 'Обновить подбор',
                icon: Icons.refresh,
                onPressed:
                    event != null && MatchDatePolicy.live().contains(event.date)
                    ? () => _pick(event, saved: s)
                    : null,
              ),
              WorkspaceAction(
                label: 'Удалить подборку',
                icon: Icons.delete_outline,
                outlined: true,
                onPressed: () async {
                  if (await _confirmDelete(s.name)) {
                    await widget.repository.deleteSelection(widget.uid, s.id);
                    reload();
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (s.entries.isEmpty)
            const Text('В сохранённом результате нет подходящих кандидатов.'),
          for (final r in s.entries)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text(
                '${r.contractor.name} · от ${money(r.contractor.price)} ₸',
              ),
              subtitle: const Text('Данные на момент сохранения'),
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: SelectableText(r.explanation),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _favorites(_ClientData data) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const WorkspaceHeading(
        'Избранное',
        'Подрядчики, к которым хочется вернуться. Доступность зависит от даты события.',
      ),
      if (data.favorites.isEmpty)
        const WorkspaceEmpty(
          title: 'Здесь будут ваши избранные',
          message: 'Добавляйте интересные карточки из живого каталога.',
        ),
      for (final c in data.favorites)
        Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: data.published[c.id] == null
              ? WorkspaceCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        c.name,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const Text('Карточка больше не опубликована.'),
                      const SizedBox(height: 12),
                      WorkspaceAction(
                        label: 'Убрать из избранного',
                        outlined: true,
                        onPressed: () async {
                          await widget.repository.setFavorite(
                            widget.uid,
                            c,
                            favorite: false,
                          );
                          reload();
                        },
                      ),
                    ],
                  ),
                )
              : ContractorCard(
                  contractor: data.published[c.id]!.content.toContractor(c.id),
                  footer: WorkspaceAction(
                    label: 'Убрать из избранного',
                    outlined: true,
                    icon: Icons.favorite,
                    onPressed: () async {
                      await widget.repository.setFavorite(
                        widget.uid,
                        c,
                        favorite: false,
                      );
                      reload();
                    },
                  ),
                ),
        ),
    ],
  );
  @override
  Widget build(BuildContext context) => FutureBuilder<_ClientData>(
    future: future,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return WorkspaceEmpty(
          title: 'Не удалось загрузить кабинет',
          message:
              'Проверьте соединение и повторите. Ваши сохранённые данные не потеряны.',
          action: OutlinedButton(
            onPressed: reload,
            child: const Text('Повторить'),
          ),
        );
      }
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: IconButton(
              onPressed: reload,
              tooltip: 'Обновить данные',
              icon: const Icon(Icons.refresh),
            ),
          ),
          switch (widget.section) {
            'selections' => _selections(snapshot.data!),
            'favorites' => _favorites(snapshot.data!),
            _ => _events(snapshot.data!),
          },
        ],
      );
    },
  );
}

class EventEditor extends StatefulWidget {
  const EventEditor({super.key, this.event});
  final ClientEvent? event;
  @override
  State<EventEditor> createState() => _EventEditorState();
}

class _EventEditorState extends State<EventEditor> {
  final form = GlobalKey<FormState>();
  late final name = TextEditingController(text: widget.event?.name ?? '');
  late final preferences = TextEditingController(
    text: widget.event?.preferences ?? '',
  );
  late String city = widget.event?.city ?? 'Алматы',
      format = widget.event?.format ?? 'свадьба';
  late DateTime date = widget.event?.date ?? eventToday();
  @override
  void dispose() {
    name.dispose();
    preferences.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.event == null ? 'Новое мероприятие' : 'Изменить мероприятие',
    ),
    content: SingleChildScrollView(
      child: SizedBox(
        width: 480,
        child: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: name,
                maxLength: 120,
                decoration: const InputDecoration(labelText: 'Название'),
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? 'Укажите название' : null,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: city,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Город'),
                items: [
                  for (final c in eventCities)
                    DropdownMenuItem(value: c, child: Text(c)),
                ],
                onChanged: (v) => setState(() => city = v!),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: format,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Формат'),
                items: [
                  for (final f in eventFormats)
                    DropdownMenuItem(value: f, child: Text(f)),
                ],
                onChanged: (v) => setState(() => format = v!),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () async {
                  final policy = MatchDatePolicy.live();
                  final value = await showDatePicker(
                    context: context,
                    initialDate: policy.contains(date)
                        ? date
                        : policy.firstDate,
                    firstDate: policy.firstDate,
                    lastDate: policy.lastDate,
                  );
                  if (value != null && mounted) setState(() => date = value);
                },
                icon: const Icon(Icons.calendar_today_outlined),
                label: Text('Дата: ${workspaceDate(date)}'),
              ),
              const SizedBox(height: 16),
              if (!MatchDatePolicy.live().contains(date))
                const Text('Выберите дату в ближайшие 365 дней.'),
              TextFormField(
                controller: preferences,
                minLines: 3,
                maxLines: 5,
                maxLength: 1000,
                decoration: const InputDecoration(
                  labelText: 'Что важно для события?',
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Отмена'),
      ),
      FilledButton(
        onPressed: () {
          if (!form.currentState!.validate() ||
              !MatchDatePolicy.live().contains(date)) {
            return;
          }
          Navigator.pop(
            context,
            ClientEvent(
              id: widget.event?.id ?? '',
              name: name.text.trim(),
              city: city,
              date: date,
              format: format,
              preferences: preferences.text.trim(),
            ),
          );
        },
        child: const Text('Сохранить'),
      ),
    ],
  );
}
