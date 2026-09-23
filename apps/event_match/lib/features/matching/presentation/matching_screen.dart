import 'package:event_match/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import '../data/catalog_repository.dart';
import '../data/api_recommendation_service.dart';
import '../domain/models.dart';
import '../domain/recommendation_service.dart';
import 'matching_controller.dart';
import 'widgets/contractor_card.dart';
import 'widgets/order_filters.dart';
import 'widgets/catalog_hero.dart';
import '../../../app/design_tokens.dart';
import '../data/favorites_repository.dart';
import 'favorites_controller.dart';
import 'favorites_page.dart';
import 'widgets/favorite_folder_picker.dart';
import 'widgets/alternative_dates_strip.dart';
import '../../../app/communication_scope.dart';
import '../../assistant/domain/assistant_models.dart';
import '../../assistant/presentation/assistant_controller.dart';
import '../../assistant/presentation/widgets/assistant_recommendations.dart';
import 'selection_presentation.dart';
import 'widgets/selection_overview.dart';
import 'widgets/recommendation_comparison.dart';

class MatchingScreen extends StatefulWidget {
  const MatchingScreen({
    super.key,
    required this.repository,
    this.service,
    this.favoritesRepository,
    this.onOpenAssistant,
    this.onOpenAccount,
    this.onOpenLiveCatalog,
    this.assistantController,
  });
  final CatalogRepository repository;
  final RecommendationService? service;
  final FavoritesRepository? favoritesRepository;
  final ValueChanged<MatchRequest?>? onOpenAssistant;
  final VoidCallback? onOpenAccount, onOpenLiveCatalog;
  final AssistantController? assistantController;
  @override
  State<MatchingScreen> createState() => _MatchingScreenState();
}

class _MatchingScreenState extends State<MatchingScreen> {
  late final MatchingController controller;
  late final FavoritesController favorites;
  int visibleCount = 12;
  String query = '';
  String browseCategory = 'Все';
  final searchInput = TextEditingController();
  final pageScroll = ScrollController();
  final catalogAnchor = GlobalKey();
  final catalogFocus = FocusNode(debugLabel: 'catalog heading');
  final filtersAnchor = GlobalKey();
  bool filtersExpanded = false;
  final summaries = <String, String>{};
  final summaryAttempts = <String>{};
  bool summaryBusy = false;
  bool summaryFailed = false;
  AssistantTurn? _assistantTurn;
  AssistantTurn? _lastAssistantTurn;

  MatchRequest? get _filterRequest {
    if (_assistantTurn == null) return controller.lastRequest;
    try {
      return _assistantTurn!.brief.toMatchRequest();
    } on StateError {
      return null;
    } on FormatException {
      return null;
    } on ArgumentError {
      return null;
    }
  }

  void _assistantChanged() {
    final latest = widget.assistantController?.turn;
    if (!identical(latest, _lastAssistantTurn)) {
      _lastAssistantTurn = latest;
      setState(() {
        _assistantTurn = latest?.result == null ? null : latest;
        filtersExpanded = false;
      });
      if (_assistantTurn != null) controller.clearResult();
      if (pageScroll.hasClients) pageScroll.jumpTo(0);
    } else if (_assistantTurn != null) {
      setState(
        () {},
      ); // Busy/error state disables actions on the same shortlist.
    }
  }

  Future<void> _search(MatchRequest request) async {
    setState(() => _assistantTurn = null);
    await controller.search(request);
  }

  bool get aiEnabled =>
      controller.service is ApiRecommendationService &&
      (controller.service as ApiRecommendationService).aiEnabled;

  Future<void> loadNextSummaries() async {
    if (!mounted ||
        !aiEnabled ||
        summaryBusy ||
        summaryFailed ||
        _assistantTurn != null ||
        controller.result != null ||
        controller.status == SearchStatus.searching) {
      return;
    }
    final batch = browsed
        .take(visibleCount)
        .where((c) => !summaryAttempts.contains(c.id))
        .take(3)
        .toList();
    if (batch.isEmpty) return;
    setState(() {
      summaryBusy = true;
      summaryAttempts.addAll(batch.map((c) => c.id));
    });
    final texts = await (controller.service as ApiRecommendationService)
        .summarize(batch, controller.catalog);
    if (!mounted) return;
    setState(() {
      summaries.addAll(texts);
      summaryBusy = false;
      summaryFailed = batch.any((c) => !texts.containsKey(c.id));
    });
  }

  List<Contractor> get browsed => controller.catalog
      .where(
        (c) =>
            (browseCategory == 'Все' ||
                c.categories.contains(browseCategory)) &&
            (query.isEmpty ||
                c.name.toLowerCase().contains(query) ||
                c.city.toLowerCase().contains(query)),
      )
      .toList();

  void showHelp() => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title:  Text(tr(context, 'От события — к вашей команде')),
      content: const SingleChildScrollView(
        child: Text(
          '1. Посмотрите каталог и выберите категорию.\n\n'
          '2. Укажите город, дату, формат и бюджет в фильтрах события.\n\n'
          '3. Получите до трёх рекомендаций с объяснением. Занятые на вашу дату не попадут в подборку.\n\n'
          'Цена указана «от». Данные анонимизированы; синтетические профили отмечены. Бронирование пока не предусмотрено.',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child:  Text(tr(context, 'Понятно')),
        ),
      ],
    ),
  );

  @override
  void initState() {
    super.initState();
    controller = MatchingController(widget.repository, service: widget.service)
      ..load();
    favorites = FavoritesController(
      widget.favoritesRepository ?? LocalFavoritesRepository(),
    )..load();
    _lastAssistantTurn = widget.assistantController?.turn;
    _assistantTurn = _lastAssistantTurn?.result == null
        ? null
        : _lastAssistantTurn;
    widget.assistantController?.addListener(_assistantChanged);
  }

  @override
  void didUpdateWidget(covariant MatchingScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.assistantController != widget.assistantController) {
      oldWidget.assistantController?.removeListener(_assistantChanged);
      widget.assistantController?.addListener(_assistantChanged);
      _assistantChanged();
    }
  }

  @override
  void dispose() {
    widget.assistantController?.removeListener(_assistantChanged);
    searchInput.dispose();
    catalogFocus.dispose();
    pageScroll.dispose();
    controller.dispose();
    favorites.dispose();
    super.dispose();
  }

  Future<void> saveFavorite(Contractor contractor) async {
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => FavoriteFolderPicker(
        controller: favorites,
        contractor: contractor,
        request: _assistantTurn != null
            ? _filterRequest
            : controller.result == null
            ? null
            : controller.lastRequest,
      ),
    );
    if (changed == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:  Text(tr(context, 'Избранное обновлено')),
          action: SnackBarAction(label: 'Открыть', onPressed: openFavorites),
        ),
      );
    }
  }

  Future<void> openFavorites() async {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    final request = await showFavoritesPanel(
      context,
      controller: favorites,
      catalog: controller.catalog,
      catalogAvailable: !controller.loading && controller.error == null,
    );
    if (request != null && mounted) {
      if (pageScroll.hasClients) pageScroll.jumpTo(0);
      await _search(request);
    }
  }

  Future<void> openFilters() async {
    if (MediaQuery.sizeOf(context).width >= 1200) {
      setState(() => filtersExpanded = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final target = filtersAnchor.currentContext;
        if (mounted && target != null) {
          Scrollable.ensureVisible(
            target,
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 250),
          );
        }
      });
      return;
    }
    final request = await showDialog<MatchRequest>(
      context: context,
      builder: (dialogContext) {
        final size = MediaQuery.sizeOf(dialogContext);
        final content = OrderFilters(
          catalog: controller.catalog,
          initial: _filterRequest,
        );
        if (size.width < 700) return Dialog.fullscreen(child: content);
        return Dialog(
          alignment: Alignment.centerRight,
          insetPadding: const EdgeInsets.all(16),
          child: SizedBox(width: 480, height: size.height - 32, child: content),
        );
      },
    );
    if (request != null && mounted) {
      if (pageScroll.hasClients) pageScroll.jumpTo(0);
      await _search(request);
    }
  }

  Widget message(String title, String text, {Widget? action}) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(text),
        if (action != null) ...[const SizedBox(height: 16), action],
      ],
    ),
  );

  Widget cardList(
    List<Contractor> profiles, {
    List<Recommendation>? recommendations,
  }) => LayoutBuilder(
    builder: (context, constraints) {
      final largeText = MediaQuery.textScalerOf(context).scale(16) > 24;
      final columns = largeText
          ? 1
          : constraints.maxWidth >= 1320
          ? 3
          : constraints.maxWidth >= 840
          ? 2
          : 1;
      Widget card(int i) => ContractorCard(
        key: ValueKey(profiles[i].id),
        contractor: profiles[i],
        isFavorite: favorites.contains(profiles[i].id),
        onFavorite: () => saveFavorite(profiles[i]),
        explanation: recommendations?[i].explanation,
        rank: recommendations == null ? null : i + 1,
        recommendation: recommendations?[i],
        aiSummary: recommendations == null && aiEnabled
            ? summaries[profiles[i].id]
            : null,
        summaryPending:
            recommendations == null &&
            aiEnabled &&
            !summaryFailed &&
            !summaries.containsKey(profiles[i].id),
      );
      // Table measures actual child layouts before stretching the row. Unlike
      // IntrinsicHeight, it does not rely on text's estimated intrinsic height,
      // which can be a pixel shorter than the final browser layout.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var start = 0; start < profiles.length; start += columns)
            Padding(
              padding: EdgeInsets.only(
                bottom: start + columns < profiles.length ? 20 : 0,
              ),
              child: columns == 1
                  ? card(start)
                  : Table(
                      defaultVerticalAlignment:
                          TableCellVerticalAlignment.intrinsicHeight,
                      columnWidths: {
                        for (var offset = 1; offset < columns; offset++)
                          offset * 2 - 1: const FixedColumnWidth(20),
                      },
                      children: [
                        TableRow(
                          children: [
                            for (
                              var offset = 0;
                              offset < columns;
                              offset++
                            ) ...[
                              if (offset > 0) const SizedBox.shrink(),
                              start + offset < profiles.length
                                  ? card(start + offset)
                                  : const SizedBox.shrink(),
                            ],
                          ],
                        ),
                      ],
                    ),
            ),
        ],
      );
    },
  );

  Widget results() {
    final assistant = _assistantTurn;
    final assistantResult = assistant?.result;
    if (assistant != null && assistantResult != null) {
      final brief = assistant.brief;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SelectionOverview(
            presentation: SelectionPresentation(
              outcome: assistantResult.outcome,
              count: assistantResult.recommendations.length,
              summary: assistantResult.summary,
              preliminary: assistantResult.preliminary,
            ),
            unchecked: assistantResult.unchecked,
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final value in [
                brief.city,
                brief.category,
                brief.eventFormat,
                brief.date,
                if (brief.budgetKzt != null)
                  '${brief.budgetScope == 'event' ? 'Общий бюджет' : 'До'} ${money(brief.budgetKzt!)} ₸',
                brief.language,
                if (brief.hours != null) '${brief.hours} ч',
              ].whereType<String>())
                Chip(label: Text(value)),
            ],
          ),
          const SizedBox(height: 16),
          AssistantRecommendations(
            recommendations: assistantResult.toMatchResult().recommendations,
            unverified: {
              for (final r in assistantResult.recommendations)
                r.contractor.id: {
                  ...assistantResult.unchecked,
                  ...r.unchecked,
                }.toList(),
            },
            preliminary: assistantResult.preliminary,
            isFavorite: favorites.contains,
            onFavorite: saveFavorite,
            enabled:
                widget.assistantController?.busy == false &&
                widget.assistantController?.error == null,
            onReject: (id, reason) async {
              await widget.assistantController?.act(
                AssistantAction(
                  id: 'manual:reject:$id',
                  label: 'Не подходит',
                  type: 'reject',
                  value: {
                    'contractor_id': id,
                    'reason': switch (reason) {
                      'Дорого' => 'price',
                      'Не мой стиль' => 'style',
                      'Мало информации' => 'experience',
                      _ => 'other',
                    },
                    'detail': reason,
                  },
                ),
              );
            },
          ),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => widget.onOpenAssistant?.call(null),
                icon: const Icon(Icons.auto_awesome_outlined),
                label:  Text(tr(context, 'Уточнить с помощником')),
              ),
              TextButton(
                onPressed: browseCatalog,
                child:  Text(tr(context, 'Вернуться в каталог')),
              ),
            ],
          ),
          if (widget.assistantController?.error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(widget.assistantController!.error!),
            ),
          const SizedBox(height: 24),
        ],
      );
    }
    if (controller.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (controller.error != null) {
      return message(
        'Каталог недоступен',
        controller.error!,
        action: TextButton(
          onPressed: controller.load,
          child:  Text(tr(context, 'Повторить загрузку')),
        ),
      );
    }
    if (controller.status == SearchStatus.searching) {
      return const Column(
        children: [
          LinearProgressIndicator(),
          SizedBox(height: 20),
          Text('Проверяем доступность и условия…'),
        ],
      );
    }
    if (controller.searchError != null) {
      return message(
        'Не удалось выполнить подбор',
        controller.searchError!,
        action: TextButton(
          onPressed: () => _search(controller.lastRequest!),
          child:  Text(tr(context, 'Повторить подбор')),
        ),
      );
    }
    final result = controller.result;
    if (result != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SelectionOverview(
            presentation: SelectionPresentation(
              outcome: result.outcome,
              count: result.recommendations.length,
              summary: result.summary,
            ),
            action: result.outcome == MatchOutcome.matched
                ? null
                : OutlinedButton(
                    onPressed: openFilters,
                    child:  Text(tr(context, 'Изменить условия')),
                  ),
          ),
          const SizedBox(height: 24),
          RecommendationComparison(
            recommendations: result.recommendations,
            isFavorite: favorites.contains,
            onFavorite: saveFavorite,
          ),
          if (result.notice.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(result.notice),
            ),
          if (result.relaxations.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text(
              'Можно изменить одно условие',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < result.relaxations.length; i++)
                  OutlinedButton(
                    key: ValueKey('relaxation-$i'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(48, 48),
                    ),
                    onPressed: () {
                      if (pageScroll.hasClients) pageScroll.jumpTo(0);
                      _search(result.relaxations[i].request);
                    },
                    child: Text(result.relaxations[i].label),
                  ),
              ],
            ),
          ],
          if (result.catalogVersion.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(
                'Каталог ${result.catalogVersion.substring(0, 12)} · ${result.algorithmVersion}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ],
      );
    }
    if (controller.catalog.isEmpty) {
      return message(
        'Каталог пока пуст',
        'Профили появятся после загрузки данных.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (browsed.isEmpty)
          message(
            'Ничего не нашлось',
            'Попробуйте другое имя, город или категорию.',
          ),
        cardList(browsed.take(visibleCount).toList()),
        if (summaryFailed && aiEnabled) ...[
          const SizedBox(height: 16),
           Text(
            tr(context, 'Часть AI-сводок недоступна. Показаны исходные описания из каталога.'),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => setState(() {
                summaryFailed = false;
                summaryAttempts.removeWhere((id) => !summaries.containsKey(id));
              }),
              child:  Text(tr(context, 'Повторить загрузку объяснений')),
            ),
          ),
        ],
        const SizedBox(height: 24),
        Center(
          child: Text(
            'Показано ${browsed.take(visibleCount).length} из ${browsed.length}',
          ),
        ),
        if (visibleCount < browsed.length) ...[
          const SizedBox(height: 12),
          Center(
            child: OutlinedButton(
              onPressed: () => setState(() => visibleCount += 12),
              child:  Text(tr(context, 'Показать ещё')),
            ),
          ),
        ],
      ],
    );
  }

  void browseCatalog() {
    setState(() => _assistantTurn = null);
    controller.clearResult();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final target = catalogAnchor.currentContext;
      if (target == null || !mounted) return;
      await Scrollable.ensureVisible(
        target,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
      if (mounted) catalogFocus.requestFocus();
    });
  }

  Widget matchButton({bool iconOnly = false}) {
    final enabled =
        !controller.loading &&
        controller.error == null &&
        controller.catalog.isNotEmpty;
    final label = controller.lastRequest == null && _assistantTurn == null
        ? 'Подобрать под событие'
        : 'Изменить фильтры';
    if (iconOnly) {
      return IconButton.filled(
        key: const Key('open-filters'),
        style: IconButton.styleFrom(foregroundColor: AppColors.white),
        onPressed: enabled ? openFilters : null,
        tooltip: trNullable(context, label),
        icon: const Icon(Icons.tune),
      );
    }
    return FilledButton.icon(
      key: const Key('open-filters'),
      onPressed: enabled ? openFilters : null,
      icon: const Icon(Icons.tune, size: 18),
      label: Text(label),
    );
  }

  Widget requestSummary(MatchRequest request) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Условия подбора',
        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -1,
        ),
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final label in [
            request.city,
            request.category,
            request.format,
            '${request.date.day}.${request.date.month}.${request.date.year}',
            'до ${money(request.budget)} ₸',
            if (request.language != null) request.language!,
            if (request.hours != null) '${request.hours} ч',
          ])
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.lavender,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                label,
                style: const TextStyle(fontSize: 13, color: AppColors.plum),
              ),
            ),
        ],
      ),
      if (request.preferences.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(
            'Пожелания${controller.service.supportsPreferences ? '' : ' (пока не учитываются)'}: ${request.preferences}',
          ),
        ),
      const SizedBox(height: 8),
      TextButton.icon(
        key: const Key('reset-filters'),
        onPressed: controller.clearResult,
        icon: const Icon(Icons.close, size: 18),
        label:  Text(tr(context, 'Сбросить фильтры')),
      ),
      const SizedBox(height: 24),
    ],
  );

  Widget catalogTools() => LayoutBuilder(
    builder: (context, constraints) {
      final wide =
          constraints.maxWidth >= 760 &&
          MediaQuery.textScalerOf(context).scale(16) <= 24;
      final heading = Focus(
        key: const Key('catalog-heading'),
        focusNode: catalogFocus,
        skipTraversal: true,
        child: Semantics(
          header: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Найдите своих людей',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -.7,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Каталог · ${controller.catalog.length} профилей',
                style: const TextStyle(color: AppColors.muted, fontSize: 13),
              ),
            ],
          ),
        ),
      );
      final search = TextField(
        key: const Key('catalog-search'),
        controller: searchInput,
        onChanged: (value) => setState(() {
          query = value.trim().toLowerCase();
          visibleCount = 12;
        }),
        decoration: InputDecoration(
          labelText: trNullable(context, 'Поиск в каталоге'),
          hintText: trNullable(context, 'Имя подрядчика или город'),
          prefixIcon: const Icon(Icons.search, size: 21),
          fillColor: AppColors.white,
          suffixIcon: query.isEmpty
              ? null
              : IconButton(
                  tooltip: trNullable(context, 'Очистить поиск'),
                  onPressed: () {
                    searchInput.clear();
                    setState(() {
                      query = '';
                      visibleCount = 12;
                    });
                  },
                  icon: const Icon(Icons.close, size: 18),
                ),
        ),
      );
      return Column(
        key: catalogAnchor,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (wide)
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: heading),
                const SizedBox(width: 24),
                SizedBox(width: 320, child: search),
              ],
            )
          else ...[
            heading,
            const SizedBox(height: 20),
            search,
          ],
          const SizedBox(height: 22),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final category in [
                'Все',
                'Ведущий',
                'Фотограф',
                'Банкетный зал',
                'Флорист',
              ])
                ChoiceChip(
                  avatar: ExcludeSemantics(
                    child: Icon(
                      category == 'Все'
                          ? Icons.grid_view_outlined
                          : categoryIcon(category),
                      size: 18,
                      color: browseCategory == category
                          ? AppColors.white
                          : AppColors.muted,
                    ),
                  ),
                  label: Text(category),
                  labelStyle: TextStyle(
                    color: browseCategory == category
                        ? AppColors.white
                        : AppColors.ink,
                    fontWeight: browseCategory == category
                        ? FontWeight.w600
                        : FontWeight.w500,
                    fontSize: 13,
                  ),
                  selectedColor: AppColors.primary,
                  side: BorderSide(
                    color: browseCategory == category
                        ? AppColors.primary
                        : AppColors.border,
                  ),
                  selected: browseCategory == category,
                  onSelected: (_) => setState(() {
                    browseCategory = category;
                    visibleCount = 12;
                  }),
                ),
            ],
          ),
          const SizedBox(height: 18),
          const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ExcludeSemantics(
                child: Icon(
                  Icons.info_outline,
                  size: 16,
                  color: AppColors.muted,
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Укажите дату и бюджет в подборе, чтобы проверить доступность.',
                  style: TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
        ],
      );
    },
  );

  Widget aiToggle() => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: SwitchListTile.adaptive(
      contentPadding: EdgeInsets.zero,
      title:  Text(tr(context, 'Объяснения от ИИ')),
      subtitle:  Text(
        tr(context, 'Коротко о подрядчике. Без сети остаются исходные описания.'),
      ),
      value: aiEnabled,
      onChanged: controller.status == SearchStatus.searching
          ? null
          : (value) {
              setState(
                () =>
                    (controller.service as ApiRecommendationService).aiEnabled =
                        value,
              );
              if (controller.lastRequest != null) {
                _search(controller.lastRequest!);
              }
            },
    ),
  );

  Widget advancedFilters() => Container(
    key: filtersAnchor,
    margin: const EdgeInsets.only(bottom: 24),
    decoration: BoxDecoration(
      color: AppColors.white,
      border: Border.all(color: AppColors.border),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            expanded: filtersExpanded,
            child: ListTile(
              key: const Key('advanced-filters-toggle'),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              leading: const Icon(Icons.tune),
              title:  Text(tr(context, 'Расширенные фильтры')),
              subtitle: Text(
                controller.lastRequest == null
                    ? 'Город, дата, бюджет, язык и длительность'
                    : 'Условия применены · можно уточнить подбор',
              ),
              trailing: Icon(
                filtersExpanded
                    ? Icons.keyboard_arrow_up
                    : Icons.keyboard_arrow_down,
              ),
              onTap: controller.status == SearchStatus.searching
                  ? null
                  : () => setState(() => filtersExpanded = !filtersExpanded),
            ),
          ),
          if (filtersExpanded)
            OrderFilters(
              key: ValueKey(_assistantTurn ?? controller.lastRequest),
              catalog: controller.catalog,
              initial: _filterRequest,
              embedded: true,
              onCancel: () => setState(() => filtersExpanded = false),
              onApply: (request) {
                setState(() => filtersExpanded = false);
                if (pageScroll.hasClients) pageScroll.jumpTo(0);
                _search(request);
              },
            ),
        ],
      ),
    ),
  );

  Widget footer() => Padding(
    padding: const EdgeInsets.only(top: 40, bottom: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(),
        const SizedBox(height: 24),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 24,
          runSpacing: 16,
          children: [
            const BrandMark(),
            TextButton.icon(
              onPressed: showHelp,
              icon: const Icon(Icons.help_outline, size: 18),
              label:  Text(tr(context, 'Как это работает')),
            ),
          ],
        ),
        const SizedBox(height: 12),
         Text(
          tr(context, 'Сделано для особенных событий в Казахстане.'),
          style: TextStyle(fontSize: 12, color: AppColors.muted),
        ),
        const SizedBox(height: 8),
        Text(
          'Имена анонимизированы · ${controller.catalog.where((c) => c.synthetic).length} синтетических профилей отмечены в карточках.',
          style: const TextStyle(fontSize: 11, color: AppColors.muted),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([controller, favorites]),
    builder: (context, _) {
      final size = MediaQuery.sizeOf(context);
      final largeText = MediaQuery.textScalerOf(context).scale(16) > 24;
      final mobile = size.width < 700 || largeText;
      final desktop = size.width >= 1200 && !largeText;
      final gutter = size.width < 600 ? 16.0 : 32.0;
      final request = controller.lastRequest;
      final hasSelection = request != null || _assistantTurn != null;
      WidgetsBinding.instance.addPostFrameCallback((_) => loadNextSummaries());
      return Scaffold(
        appBar: AppBar(
          toolbarHeight: desktop ? 84 : 68,
          automaticallyImplyLeading: false,
          titleSpacing: 0,
          title: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1760),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: gutter),
                child: Row(
                  children: [
                    const Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: BrandMark(),
                      ),
                    ),
                    if (desktop) ...[
                      TextButton(
                        onPressed: browseCatalog,
                        child:  Text(tr(context, 'Каталог специалистов')),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: showHelp,
                        child:  Text(tr(context, 'Как это работает')),
                      ),
                      const SizedBox(width: 12),
                      const Icon(
                        Icons.place_outlined,
                        size: 17,
                        color: AppColors.muted,
                      ),
                      const SizedBox(width: 5),
                       Text(
                        tr(context, 'Казахстан'),
                        style: TextStyle(fontSize: 12, color: AppColors.muted),
                      ),
                      const SizedBox(width: 24),
                    ] else
                      IconButton(
                        onPressed: showHelp,
                        tooltip: trNullable(context, 'Как это работает'),
                        icon: const Icon(Icons.help_outline, size: 22),
                      ),
                    if (!mobile)
                      IconButton(
                        key: const Key('open-assistant'),
                        tooltip: trNullable(context, 'ИИ-помощник'),
                        onPressed: () => widget.onOpenAssistant?.call(
                          controller.lastRequest,
                        ),
                        icon: const Icon(Icons.auto_awesome_outlined),
                      ),
                    if (widget.onOpenAccount != null) ...[
                      if (!mobile)
                        IconButton(
                          key: const Key('open-messages'),
                          tooltip: trNullable(context, 'Сообщения'),
                          onPressed: () => CommunicationScope.maybeOf(
                            context,
                          )?.openMessages(context, null),
                          icon: const Icon(Icons.chat_bubble_outline),
                        ),
                      PopupMenuButton<String>(
                        tooltip: trNullable(context, 'Кабинеты и живой каталог'),
                        icon: const Icon(Icons.person_outline),
                        onSelected: (v) {
                          switch (v) {
                            case 'catalog':
                              widget.onOpenLiveCatalog?.call();
                            case 'assistant':
                              widget.onOpenAssistant?.call(
                                controller.lastRequest,
                              );
                            case 'messages':
                              CommunicationScope.maybeOf(
                                context,
                              )?.openMessages(context, null);
                            default:
                              widget.onOpenAccount?.call();
                          }
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                            value: 'account',
                            child: Text('Мой кабинет'),
                          ),
                          const PopupMenuItem(
                            value: 'catalog',
                            child: Text('Опубликованные подрядчики'),
                          ),
                          if (mobile)
                            const PopupMenuItem(
                              value: 'assistant',
                              child: Text('ИИ-помощник'),
                            ),
                          if (mobile)
                            const PopupMenuItem(
                              value: 'messages',
                              child: Text('Сообщения'),
                            ),
                        ],
                      ),
                    ],
                    IconButton(
                      key: Key(
                        desktop
                            ? 'open-favorites-desktop'
                            : 'open-favorites-mobile',
                      ),
                      onPressed: openFavorites,
                      tooltip: trNullable(context, 'Избранное'),
                      icon: const Icon(Icons.favorite_border),
                    ),
                    if (!mobile) matchButton(iconOnly: !desktop),
                  ],
                ),
              ),
            ),
          ),
          bottom: const PreferredSize(
            preferredSize: Size.fromHeight(1),
            child: Divider(height: 1),
          ),
        ),
        bottomNavigationBar: mobile
            ? Container(
                decoration: const BoxDecoration(
                  color: AppColors.canvas,
                  border: Border(top: BorderSide(color: AppColors.border)),
                ),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                    child: SizedBox(
                      width: double.infinity,
                      child: matchButton(),
                    ),
                  ),
                ),
              )
            : null,
        body: SafeArea(
          top: false,
          child: CustomScrollView(
            controller: pageScroll,
            slivers: [
              SliverToBoxAdapter(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1760),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        gutter,
                        desktop ? 28 : 20,
                        gutter,
                        12,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (!hasSelection) ...[
                            CatalogHero(
                              count: controller.catalog.length,
                              onBrowse: browseCatalog,
                            ),
                            SizedBox(height: desktop ? 40 : 28),
                            catalogTools(),
                          ],
                          if (hasSelection) results(),
                          if (request != null) requestSummary(request),
                          if (size.width >= 1200) advancedFilters(),
                          if (_assistantTurn == null &&
                              controller.service is ApiRecommendationService)
                            aiToggle(),
                          if (request != null &&
                              controller.dateOptions.isNotEmpty) ...[
                            AlternativeDatesStrip(
                              days: controller.dateOptions,
                              selectedDate: request.date,
                              enabled:
                                  controller.status != SearchStatus.searching,
                              onSelected: (date) =>
                                  _search(request.copyWith(date: date)),
                            ),
                            const SizedBox(height: 24),
                          ],
                          if (!hasSelection) results(),
                          footer(),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
