import 'package:flutter/material.dart';
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
Contractor? _pendingGuestFavorite;

class CatalogPage extends StatefulWidget {
  const CatalogPage({
    super.key,
    required this.repository,
    required this.onRequireSignIn,
    this.uid,
    this.onCreateInquiry,
  });
  final WorkspaceRepository repository;
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
  @override
  void initState() {
    super.initState();
    controller = MatchingController(
      WorkspaceCatalogRepository(widget.repository),
      service: LiveRecommendationService(widget.repository),
      datePolicy: MatchDatePolicy.live(),
    )..load();
    _restoreAction();
  }

  @override
  void didUpdateWidget(CatalogPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uid != widget.uid) {
      favorites = {};
      _restoreAction();
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
    controller.dispose();
    queryInput.dispose();
    super.dispose();
  }

  Future<void> _filter() async {
    final request = await showDialog<MatchRequest>(
      context: context,
      builder: (context) {
        final content = OrderFilters(
          catalog: controller.catalog,
          supportsPreferences: false,
          initial: controller.lastRequest,
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
    if (request != null && mounted) await controller.search(request);
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
    final uid = widget.uid!;
    final events = await widget.repository.listEvents(uid);
    if (!mounted || widget.uid != uid) return;
    final event = await showDialog<ClientEvent>(
      context: context,
      builder: (context) =>
          _ChooseEventDialog(events: events, request: request),
    );
    if (event == null || !mounted || widget.uid != uid) return;
    final eventId = event.id.isEmpty
        ? await widget.repository.saveEvent(uid, event)
        : event.id;
    await widget.repository.saveSelection(
      uid,
      SavedSelection(
        eventId: eventId,
        name: '${request.category} · ${event.name}',
        request: request,
        entries: result.recommendations,
      ),
    );
    if (mounted) {
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
