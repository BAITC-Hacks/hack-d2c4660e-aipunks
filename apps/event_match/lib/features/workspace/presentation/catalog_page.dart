import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../../assistant/domain/assistant_models.dart';
import '../../assistant/presentation/assistant_controller.dart';
import '../../assistant/presentation/assistant_screen.dart';
import 'package:go_router/go_router.dart';
import '../../matching/domain/models.dart';
import '../../matching/presentation/matching_controller.dart';
import '../../matching/presentation/widgets/catalog_hero.dart';
import '../../matching/presentation/widgets/contractor_card.dart';
import '../../matching/presentation/widgets/order_filters.dart';
import '../data/workspace_catalog_repository.dart';
import '../domain/workspace_models.dart';
import '../domain/workspace_repository.dart';
import 'workspace_widgets.dart';

// A guest action is kept only until the user returns from authentication. It
// contains public catalogue data, never a previous user's private workspace.
MatchRequest? _pendingGuestRequest;
AssistantBrief? _pendingGuestBrief;
Contractor? _pendingGuestFavorite;

class CatalogPage extends StatefulWidget {
  const CatalogPage({
    super.key,
    required this.repository,
    required this.onRequireSignIn,
    this.uid,
    this.onCreateInquiry,
    this.assistant,
    this.eventId,
    this.selectionId,
    this.initialCategory,
  });
  final WorkspaceRepository repository;
  final AssistantController? assistant;
  final String? eventId, selectionId, initialCategory;
  final String? uid;
  final VoidCallback onRequireSignIn;
  final ValueChanged<Contractor>? onCreateInquiry;
  @override
  State<CatalogPage> createState() => _CatalogPageState();
}

class _CatalogPageState extends State<CatalogPage> {
  late final MatchingController controller;
  final queryInput = TextEditingController();
  String query = '', category = 'Все';
  int visible = 12;
  Set<String> favorites = {};
  String? restorationError;
  int _restoreGeneration = 0;
  int _contextGeneration = 0;
  ClientEvent? currentEvent;
  String? contextError;
  bool contextLoading = false;
  bool browse = false;
  @override
  void initState() {
    super.initState();
    controller = MatchingController(
      WorkspaceCatalogRepository(widget.repository),
      service: LiveRecommendationService(widget.repository),
      datePolicy: MatchDatePolicy.live(),
    )..load();
    _restoreAction();
    _loadContext();
  }

  @override
  void didUpdateWidget(CatalogPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.eventId != widget.eventId ||
        oldWidget.selectionId != widget.selectionId ||
        oldWidget.initialCategory != widget.initialCategory ||
        oldWidget.uid != widget.uid) {
      _loadContext();
    }
    if (oldWidget.uid != widget.uid) {
      favorites = {};
      _restoreAction();
    }
  }

  Future<void> _loadContext() async {
    final assistant = widget.assistant;
    if (assistant == null) return;
    final generation = ++_contextGeneration;
    final eventId = widget.eventId;
    currentEvent = null;
    contextError = null;
    contextLoading = eventId != null;
    if (eventId == null) {
      assistant.replaceContext(const AssistantBrief(), '${widget.uid}:catalog');
      return;
    }
    if (widget.uid == null) {
      contextLoading = false;
      contextError =
          'Войдите, чтобы подобрать специалистов для своего мероприятия.';
      return;
    }
    try {
      final events = await widget.repository.listEvents(widget.uid!);
      if (!mounted || generation != _contextGeneration) return;
      final found = events.where((e) => e.id == eventId).firstOrNull;
      if (found == null) {
        throw StateError('Мероприятие не найдено. Выберите его в кабинете.');
      }
      SavedSelection? selection;
      if (widget.selectionId != null) {
        final selections = await widget.repository.listSelections(widget.uid!);
        if (!mounted || generation != _contextGeneration) return;
        selection = selections
            .where((s) => s.id == widget.selectionId && s.eventId == found.id)
            .firstOrNull;
        if (selection == null) {
          throw StateError(
            'Сохранённая подборка не найдена. Откройте мероприятие заново.',
          );
        }
      }
      final initial = selection == null
          ? AssistantBrief(
              category: widget.initialCategory,
              preferences: found.preferences.isEmpty
                  ? const []
                  : [AssistantPreference(text: found.preferences)],
            )
          : AssistantBrief.fromRequest(selection.request);
      final brief = AssistantBrief.fromJson({
        ...initial.toJson(),
        'city': found.city,
        'date': dateKey(found.date),
        'event_format': found.format,
      });
      assistant.replaceContext(
        brief,
        '${widget.uid}:$eventId:${widget.selectionId}:${widget.initialCategory}:${jsonEncode(brief.toJson())}',
      );
      setState(() {
        currentEvent = found;
        contextLoading = false;
      });
      if (assistant.turn == null) {
        await assistant.act(
          const AssistantAction(
            id: 'event-context',
            label: 'Подобрать для мероприятия',
            type: 'show_results',
          ),
        );
      }
    } catch (e) {
      if (!mounted || generation != _contextGeneration) return;
      setState(() {
        contextLoading = false;
        contextError = e is StateError
            ? e.message.toString()
            : 'Не удалось загрузить мероприятие. Повторите попытку.';
      });
    }
  }

  void _restoreAction() {
    if (widget.uid == null) return;
    final uid = widget.uid!;
    final generation = ++_restoreGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || widget.uid != uid) return;
      setState(() => restorationError = null);
      try {
        final items = await widget.repository.listFavorites(uid);
        if (!mounted || widget.uid != uid || generation != _restoreGeneration) {
          return;
        }
        setState(() => favorites = items.map((c) => c.id).toSet());
        final pendingBrief = _pendingGuestBrief;
        if (pendingBrief != null && widget.assistant != null) {
          widget.assistant!.replaceContext(
            pendingBrief,
            widget.assistant!.contextKey ?? '$uid:catalog',
            force: true,
          );
          await widget.assistant!.act(
            const AssistantAction(
              id: 'resume-after-signin',
              label: 'Восстановить подбор',
              type: 'show_results',
            ),
          );
          if (!mounted ||
              widget.uid != uid ||
              generation != _restoreGeneration) {
            return;
          }
          final result = widget.assistant!.turn?.result;
          if (widget.assistant!.error != null || result == null) {
            throw StateError('Подбор не завершён');
          }
          await _persist(
            widget.assistant!.brief.toMatchRequest(
              datePolicy: MatchDatePolicy.live(),
            ),
            result.toMatchResult().recommendations,
          );
          _pendingGuestBrief = null;
        }
        final request = _pendingGuestRequest;
        final favorite = _pendingGuestFavorite;
        if (request != null) {
          await controller.search(request);
          if (!mounted ||
              widget.uid != uid ||
              generation != _restoreGeneration) {
            return;
          }
          if (controller.result == null) throw StateError('Подбор не завершён');
          await _save();
          _pendingGuestRequest = null;
        }
        if (favorite != null &&
            mounted &&
            widget.uid == uid &&
            generation == _restoreGeneration) {
          // The guest requested adding a favorite; an existing favorite must
          // remain saved regardless of authentication/network timing.
          await widget.repository.setFavorite(uid, favorite, favorite: true);
          if (!mounted ||
              widget.uid != uid ||
              generation != _restoreGeneration) {
            return;
          }
          _pendingGuestFavorite = null;
          setState(() => favorites.add(favorite.id));
        }
      } catch (_) {
        if (mounted && widget.uid == uid && generation == _restoreGeneration) {
          setState(
            () => restorationError =
                'Не удалось восстановить избранное или завершить действие после входа. Попробуйте ещё раз.',
          );
        }
      }
    });
  }

  @override
  void dispose() {
    ++_contextGeneration;
    ++_restoreGeneration;
    controller.dispose();
    queryInput.dispose();
    super.dispose();
  }

  MatchRequest? _filterInitial() {
    final brief = widget.assistant?.brief;
    if (brief == null) return controller.lastRequest;
    // These are editable form defaults only; they do not enter the brief until Apply.
    return MatchRequest(
      city: brief.city ?? 'Алматы',
      date:
          DateTime.tryParse(brief.date ?? '') ??
          MatchDatePolicy.live().firstDate,
      format: brief.eventFormat ?? 'свадьба',
      category: brief.category ?? 'Ведущий',
      budget: brief.budgetScope == 'contractor'
          ? brief.budgetKzt ?? 1000000
          : 1000000,
      hours: brief.hours,
      language: brief.language,
      preferences: brief.preferences.map((p) => p.text).join('; '),
    );
  }

  Future<void> _filter() async {
    final generation = _contextGeneration;
    final request = await showDialog<MatchRequest>(
      context: context,
      builder: (context) {
        final content = OrderFilters(
          catalog: controller.catalog,
          supportsPreferences: false,
          initial: _filterInitial(),
          datePolicy: MatchDatePolicy.live(),
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
    if (request != null && mounted && generation == _contextGeneration) {
      if (widget.assistant case final assistant?) {
        final before = assistant.brief;
        final next = AssistantBrief.fromRequest(request)
            .withField(
              'preferences',
              request.category == before.category
                  ? before.preferences.map((p) => p.toJson()).toList()
                  : [],
            )
            .withField(
              'excluded_ids',
              request.category == before.category ? before.excludedIds : [],
            );
        assistant.replaceContext(
          next,
          assistant.contextKey ?? '${widget.uid}:catalog',
          force: true,
        );
        setState(() => browse = false);
        await assistant.act(
          const AssistantAction(
            id: 'filters',
            label: 'Применить условия',
            type: 'show_results',
          ),
        );
      } else {
        await controller.search(request);
      }
    }
  }

  Future<void> _favorite(Contractor c) async {
    if (widget.uid == null) {
      _pendingGuestFavorite = c;
      widget.onRequireSignIn();
      return;
    }
    final uid = widget.uid!;
    final selected = !favorites.contains(c.id);
    await widget.repository.setFavorite(uid, c, favorite: selected);
    if (mounted && widget.uid == uid) {
      setState(() {
        selected ? favorites.add(c.id) : favorites.remove(c.id);
      });
    }
  }

  Future<void> _save() async {
    final request = controller.lastRequest, result = controller.result;
    if (request == null || result == null) return;
    if (widget.uid == null) {
      _pendingGuestRequest = request;
      widget.onRequireSignIn();
      return;
    }
    await _persist(request, result.recommendations);
  }

  Future<void> _saveAssistant(Future<void> Function(String) edit) async {
    final assistant = widget.assistant!;
    final generation = _contextGeneration;
    if (assistant.brief.date == null ||
        !MatchDatePolicy.live().contains(
          DateTime.parse(assistant.brief.date!),
        )) {
      await edit('date');
    }
    if (!mounted ||
        generation != _contextGeneration ||
        assistant.busy ||
        assistant.error != null ||
        assistant.brief.date == null ||
        !MatchDatePolicy.live().contains(
          DateTime.parse(assistant.brief.date!),
        )) {
      return;
    }
    if (assistant.brief.budgetKzt == null ||
        assistant.brief.budgetScope != 'contractor') {
      await edit('budget_kzt');
    }
    if (!mounted ||
        generation != _contextGeneration ||
        assistant.busy ||
        assistant.error != null) {
      return;
    }
    if (assistant.brief.budgetKzt == null ||
        assistant.brief.budgetScope != 'contractor') {
      return;
    }
    final result = assistant.turn?.result;
    if (result == null || result.recommendations.isEmpty) return;
    final request = assistant.brief.toMatchRequest(
      datePolicy: MatchDatePolicy.live(),
    );
    if (widget.uid == null) {
      _pendingGuestBrief = assistant.brief;
      widget.onRequireSignIn();
      return;
    }
    await _persist(request, result.toMatchResult().recommendations);
  }

  Future<void> _persist(
    MatchRequest request,
    List<Recommendation> entries,
  ) async {
    final uid = widget.uid!;
    final generation = _contextGeneration;
    final selectionId = widget.selectionId;
    final targetEventId = widget.eventId;
    final events = await widget.repository.listEvents(uid);
    if (!mounted || widget.uid != uid || generation != _contextGeneration) {
      return;
    }
    ClientEvent? event;
    if (targetEventId != null) {
      event = events.where((e) => e.id == targetEventId).firstOrNull;
      if (event == null) {
        throw StateError('Мероприятие удалено. Выберите другое в кабинете.');
      }
      if (event.city != request.city ||
          dateKey(event.date) != dateKey(request.date) ||
          event.format != request.format) {
        throw StateError(
          'Условия отличаются от мероприятия. Верните его город, дату и формат перед сохранением.',
        );
      }
    } else {
      event = await showDialog<ClientEvent>(
        context: context,
        builder: (_) => _ChooseEventDialog(events: events, request: request),
      );
    }
    if (event == null ||
        !mounted ||
        widget.uid != uid ||
        generation != _contextGeneration) {
      return;
    }
    // Revalidate public status and calendars before attaching a snapshot to a private event.
    final fresh = await LiveRecommendationService(
      widget.repository,
    ).recommend(request);
    final published = await widget.repository.listPublished();
    for (final entry in entries) {
      final current = published
          .where((p) => p.ownerId == entry.contractor.id)
          .firstOrNull;
      final calendar = await widget.repository.getCalendar(
        entry.contractor.id,
        request.date,
      );
      if (current == null ||
          calendar?.availabilityOn(request.date, DateTime.now()) !=
              AvailabilityStatus.available ||
          jsonEncode(
                contractorSnapshot(
                  current.content.toContractor(current.ownerId),
                ),
              ) !=
              jsonEncode(contractorSnapshot(entry.contractor))) {
        throw StateError(
          'Профиль или занятость изменились. Обновите подборку перед сохранением.',
        );
      }
    }
    if (fresh.outcome != MatchOutcome.matched) {
      throw StateError('Условия больше не выполняются. Обновите подборку.');
    }
    if (!mounted || widget.uid != uid || generation != _contextGeneration) {
      return;
    }
    final eventId = event.id.isEmpty
        ? await widget.repository.saveEvent(uid, event)
        : event.id;
    if (!mounted || widget.uid != uid || generation != _contextGeneration) {
      return;
    }
    await widget.repository.saveSelection(
      uid,
      SavedSelection(
        id: selectionId ?? '',
        eventId: eventId,
        name: '${request.category} · ${event.name}',
        request: request,
        entries: entries,
      ),
    );
    if (mounted && widget.uid == uid && generation == _contextGeneration) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Подборка сохранена'),
          action: SnackBarAction(
            label: 'Открыть',
            onPressed: () => context.go('/client/selections'),
          ),
        ),
      );
    }
  }

  Widget _cards(
    List<Contractor> items, {
    List<Recommendation>? recommendations,
  }) => LayoutBuilder(
    builder: (context, box) {
      final columns = MediaQuery.textScalerOf(context).scale(16) > 24
          ? 1
          : box.maxWidth >= 1100
          ? 3
          : box.maxWidth >= 700
          ? 2
          : 1;
      return Wrap(
        spacing: 20,
        runSpacing: 20,
        children: [
          for (var i = 0; i < items.length; i++)
            SizedBox(
              width: (box.maxWidth - (columns - 1) * 20) / columns,
              child: ContractorCard(
                contractor: items[i],
                explanation: recommendations?[i].explanation,
                rank: recommendations == null ? null : i + 1,
                footer: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (widget.onCreateInquiry != null &&
                        items[i].isLive &&
                        items[i].id != widget.uid) ...[
                      FilledButton.icon(
                        onPressed: () => widget.onCreateInquiry!(items[i]),
                        icon: const Icon(Icons.chat_bubble_outline),
                        label: const Text('Обсудить мероприятие'),
                      ),
                      const SizedBox(height: 8),
                    ],
                    WorkspaceAction(
                      label: favorites.contains(items[i].id)
                          ? 'Убрать из избранного'
                          : 'В избранное',
                      icon: favorites.contains(items[i].id)
                          ? Icons.favorite
                          : Icons.favorite_border,
                      outlined: true,
                      onPressed: () => _favorite(items[i]),
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
    },
  );
  Widget _cardActions(Contractor c) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (widget.onCreateInquiry != null && c.isLive && c.id != widget.uid)
        FilledButton.icon(
          onPressed: widget.assistant!.busy || widget.assistant!.error != null
              ? null
              : () => widget.onCreateInquiry!(c),
          icon: const Icon(Icons.chat_bubble_outline),
          label: const Text('Обсудить мероприятие'),
        ),
      const SizedBox(height: 8),
      WorkspaceAction(
        outlined: true,
        label: favorites.contains(c.id)
            ? 'Убрать из избранного'
            : 'В избранное',
        icon: favorites.contains(c.id) ? Icons.favorite : Icons.favorite_border,
        onPressed: widget.assistant!.busy || widget.assistant!.error != null
            ? null
            : () => _favorite(c),
      ),
    ],
  );

  Widget _integrated(List<Contractor> items) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (contextLoading)
        const LinearProgressIndicator()
      else if (contextError != null)
        WorkspaceEmpty(
          title: 'Мероприятие недоступно',
          message: contextError!,
          action: TextButton(
            onPressed: widget.uid == null
                ? widget.onRequireSignIn
                : _loadContext,
            child: Text(widget.uid == null ? 'Войти' : 'Повторить'),
          ),
        )
      else
        AssistantScreen(
          controller: widget.assistant!,
          embedded: true,
          contextHeader: currentEvent == null
              ? null
              : Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Chip(
                        avatar: const Icon(Icons.event_outlined),
                        label: Text(currentEvent!.name),
                      ),
                      TextButton(
                        onPressed: () => context.go(
                          '/client/planner?event=${Uri.encodeQueryComponent(currentEvent!.id)}',
                        ),
                        child: const Text('Вернуться в план'),
                      ),
                    ],
                  ),
                ),
          onOpenCatalog: () => setState(() => browse = true),
          cardFooterBuilder: _cardActions,
          resultActionsBuilder: (edit) => WorkspaceAction(
            label: currentEvent == null
                ? 'Сохранить подборку'
                : 'Сохранить в «${currentEvent!.name}»',
            icon: Icons.bookmark_border,
            onPressed: widget.assistant!.busy || widget.assistant!.error != null
                ? null
                : () => _saveAssistant(edit),
          ),
        ),
      if (restorationError != null)
        WorkspaceEmpty(
          title: 'Действие не завершено',
          message: restorationError!,
          action: TextButton(
            onPressed: _restoreAction,
            child: const Text('Повторить действие'),
          ),
        ),
      const SizedBox(height: 24),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton.icon(
            key: const Key('live-open-filters'),
            onPressed: controller.loading ? null : _filter,
            icon: const Icon(Icons.tune),
            label: const Text('Фильтры'),
          ),
          TextButton.icon(
            onPressed: () => setState(() => browse = !browse),
            icon: Icon(browse ? Icons.expand_less : Icons.storefront_outlined),
            label: Text(browse ? 'Свернуть каталог' : 'Смотреть весь каталог'),
          ),
          TextButton.icon(
            onPressed: () async {
              await controller.load();
              await widget.assistant!.loadCatalog();
            },
            icon: const Icon(Icons.refresh),
            label: const Text('Обновить'),
          ),
        ],
      ),
      if (controller.error != null)
        WorkspaceEmpty(title: 'Каталог недоступен', message: controller.error!),
      if (!controller.loading && controller.catalog.isEmpty)
        const WorkspaceEmpty(
          title: 'Пока нет опубликованных специалистов',
          message:
              'Карточки появятся после проверки. Демонстрационные примеры доступны в демокаталоге.',
        ),
      if (browse) ...[
        const SizedBox(height: 20),
        TextField(
          controller: queryInput,
          decoration: const InputDecoration(
            labelText: 'Имя подрядчика или город',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (value) => setState(() {
            query = value.trim().toLowerCase();
            visible = 12;
          }),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: category,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Категория'),
          items: [
            for (final value in [
              'Все',
              ...controller.catalog.expand((c) => c.categories).toSet().toList()
                ..sort(),
            ])
              DropdownMenuItem(value: value, child: Text(value)),
          ],
          onChanged: (value) => setState(() {
            category = value ?? 'Все';
            visible = 12;
          }),
        ),
        const SizedBox(height: 20),
        _cards(items.take(visible).toList()),
        if (items.length > visible)
          OutlinedButton(
            onPressed: () => setState(() => visible += 12),
            child: const Text('Показать ещё'),
          ),
      ],
    ],
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final request = controller.lastRequest;
      final result = controller.result;
      final items = controller.catalog
          .where(
            (c) =>
                (category == 'Все' || c.categories.contains(category)) &&
                (query.isEmpty ||
                    '${c.name} ${c.city}'.toLowerCase().contains(query)),
          )
          .toList();
      if (widget.assistant != null) return _integrated(items);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CatalogHero(count: controller.catalog.length),
          if (restorationError != null) ...[
            const SizedBox(height: 16),
            WorkspaceEmpty(
              title: 'Действие не завершено',
              message: restorationError!,
              action: OutlinedButton(
                onPressed: _restoreAction,
                child: const Text('Повторить действие'),
              ),
            ),
          ],
          const SizedBox(height: 24),
          const Text(
            'Живой каталог · карточки проходят проверку. Подбор учитывает только актуальный календарь.',
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton.icon(
                key: const Key('live-open-filters'),
                onPressed: controller.loading ? null : _filter,
                icon: const Icon(Icons.tune),
                label: Text(
                  request == null
                      ? 'Подобрать под событие'
                      : 'Изменить условия',
                ),
              ),
              OutlinedButton.icon(
                onPressed: controller.loading
                    ? null
                    : () {
                        controller.clearResult();
                        controller.load();
                      },
                icon: const Icon(Icons.refresh),
                label: const Text('Обновить каталог'),
              ),
              if (request != null)
                TextButton(
                  onPressed: controller.clearResult,
                  child: const Text('Сбросить условия'),
                ),
            ],
          ),
          const SizedBox(height: 20),
          if (request != null) ...[
            Text(
              '${request.city} · ${dateKey(request.date)} · ${request.format} · ${request.category} · до ${money(request.budget)} ₸',
            ),
            const SizedBox(height: 16),
          ] else ...[
            TextField(
              controller: queryInput,
              decoration: const InputDecoration(
                labelText: 'Имя подрядчика или город',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (s) => setState(() {
                query = s.trim().toLowerCase();
                visible = 12;
              }),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in ['Все', ...contractorCategories])
                  ChoiceChip(
                    label: Text(c),
                    selected: category == c,
                    onSelected: (_) => setState(() {
                      category = c;
                      visible = 12;
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 20),
          ],
          if (controller.loading || controller.status == SearchStatus.searching)
            const LinearProgressIndicator(),
          if (controller.error != null)
            WorkspaceEmpty(
              title: 'Каталог недоступен',
              message: controller.error!,
              action: TextButton(
                onPressed: controller.load,
                child: const Text('Повторить'),
              ),
            )
          else if (controller.searchError != null)
            WorkspaceEmpty(
              title: 'Подбор не завершён',
              message: controller.searchError!,
              action: TextButton(
                onPressed: () => controller.search(request!),
                child: const Text('Повторить'),
              ),
            )
          else if (result != null) ...[
            WorkspaceHeading(
              result.outcome == MatchOutcome.matched
                  ? 'Ваша подборка'
                  : result.outcome == MatchOutcome.categoryAbsent
                  ? 'В этом городе категории пока нет'
                  : 'Нет подходящих кандидатов',
              result.summary,
            ),
            WorkspaceAction(
              label: 'Сохранить подборку',
              icon: Icons.bookmark_border,
              onPressed: _save,
            ),
            const SizedBox(height: 20),
            _cards(
              result.recommendations.map((r) => r.contractor).toList(),
              recommendations: result.recommendations,
            ),
          ] else if (!controller.loading && controller.catalog.isEmpty)
            const WorkspaceEmpty(
              title: 'Здесь появится команда вашего события',
              message:
                  'Живых опубликованных карточек пока нет. Подрядчики появятся после регистрации и проверки. Пример подбора доступен отдельно в демокаталоге.',
              icon: Icons.storefront_outlined,
            )
          else if (items.isEmpty && !controller.loading)
            const WorkspaceEmpty(
              title: 'Ничего не нашлось',
              message: 'Попробуйте другое имя или категорию.',
            )
          else ...[
            _cards(items.take(visible).toList()),
            if (items.length > visible)
              Padding(
                padding: const EdgeInsets.only(top: 20),
                child: OutlinedButton(
                  onPressed: () => setState(() => visible += 12),
                  child: const Text('Показать ещё'),
                ),
              ),
          ],
        ],
      );
    },
  );
}

class _ChooseEventDialog extends StatefulWidget {
  const _ChooseEventDialog({required this.events, required this.request});
  final List<ClientEvent> events;
  final MatchRequest request;
  @override
  State<_ChooseEventDialog> createState() => _ChooseEventDialogState();
}

class _ChooseEventDialogState extends State<_ChooseEventDialog> {
  final name = TextEditingController();
  final form = GlobalKey<FormState>();
  String selected = '';
  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Сохранить в мероприятие'),
    content: SingleChildScrollView(
      child: Form(
        key: form,
        child: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: selected,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Мероприятие'),
                items: [
                  const DropdownMenuItem(
                    value: '',
                    child: Text('Новое мероприятие'),
                  ),
                  for (final e in widget.events.where(
                    (e) =>
                        e.city == widget.request.city &&
                        dateKey(e.date) == dateKey(widget.request.date) &&
                        e.format == widget.request.format,
                  ))
                    DropdownMenuItem(value: e.id, child: Text(e.name)),
                ],
                onChanged: (v) => setState(() => selected = v ?? ''),
              ),
              const SizedBox(height: 16),
              if (selected.isEmpty)
                TextFormField(
                  controller: name,
                  maxLength: 120,
                  decoration: const InputDecoration(
                    labelText: 'Название мероприятия',
                  ),
                  validator: (v) =>
                      (v ?? '').trim().isEmpty ? 'Укажите название' : null,
                ),
              const Text(
                'Показываем мероприятия с теми же городом, датой и форматом.',
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
          if (!form.currentState!.validate()) return;
          Navigator.pop(
            context,
            selected.isNotEmpty
                ? widget.events.firstWhere((e) => e.id == selected)
                : ClientEvent(
                    name: name.text.trim(),
                    city: widget.request.city,
                    date: widget.request.date,
                    format: widget.request.format,
                    preferences: widget.request.preferences,
                  ),
          );
        },
        child: const Text('Сохранить'),
      ),
    ],
  );
}
