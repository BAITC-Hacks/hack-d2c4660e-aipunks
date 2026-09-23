import 'package:flutter/material.dart';
import '../data/catalog_repository.dart';
import '../domain/models.dart';
import '../domain/recommendation_service.dart';
import 'matching_controller.dart';
import 'widgets/contractor_card.dart';
import 'widgets/order_filters.dart';
import 'widgets/catalog_hero.dart';
import '../../../app/design_tokens.dart';

class MatchingScreen extends StatefulWidget {
  const MatchingScreen({super.key, required this.repository, this.service});
  final CatalogRepository repository;
  final RecommendationService? service;
  @override
  State<MatchingScreen> createState() => _MatchingScreenState();
}

class _MatchingScreenState extends State<MatchingScreen> {
  late final MatchingController controller;
  int visibleCount = 12;
  String query = '';
  String browseCategory = 'Все';
  final searchInput = TextEditingController();
  final pageScroll = ScrollController();
  final catalogAnchor = GlobalKey();
  final catalogFocus = FocusNode(debugLabel: 'catalog heading');

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
      title: const Text('От события — к вашей команде'),
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
          child: const Text('Понятно'),
        ),
      ],
    ),
  );

  @override
  void initState() {
    super.initState();
    controller = MatchingController(widget.repository, service: widget.service)
      ..load();
  }

  @override
  void dispose() {
    searchInput.dispose();
    catalogFocus.dispose();
    pageScroll.dispose();
    controller.dispose();
    super.dispose();
  }

  Future<void> openFilters() async {
    final request = await showDialog<MatchRequest>(
      context: context,
      builder: (dialogContext) {
        final size = MediaQuery.sizeOf(dialogContext);
        final content = OrderFilters(
          catalog: controller.catalog,
          supportsPreferences: controller.service.supportsPreferences,
          initial: controller.lastRequest,
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
      await controller.search(request);
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
          : constraints.maxWidth >= 1020
          ? 3
          : constraints.maxWidth >= 700
          ? 2
          : 1;
      final width = (constraints.maxWidth - (columns - 1) * 20) / columns;
      return Wrap(
        spacing: 20,
        runSpacing: 20,
        children: [
          for (var i = 0; i < profiles.length; i++)
            SizedBox(
              width: width,
              child: ContractorCard(
                key: ValueKey(profiles[i].id),
                contractor: profiles[i],
                explanation: recommendations?[i].explanation,
                rank: recommendations == null ? null : i + 1,
              ),
            ),
        ],
      );
    },
  );

  Widget results() {
    if (controller.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (controller.error != null) {
      return message(
        'Каталог недоступен',
        'Не удалось загрузить профили. Проверьте подключение и попробуйте ещё раз.',
        action: TextButton(
          onPressed: controller.load,
          child: const Text('Повторить загрузку'),
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
          onPressed: () => controller.search(controller.lastRequest!),
          child: const Text('Повторить подбор'),
        ),
      );
    }
    final result = controller.result;
    if (result != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            liveRegion: true,
            child: message(
              switch (result.outcome) {
                MatchOutcome.matched => 'Ваша подборка',
                MatchOutcome.categoryAbsent =>
                  'В этом городе категории пока нет',
                MatchOutcome.noEligible => 'Нет подходящих кандидатов',
              },
              result.summary,
              action: result.outcome == MatchOutcome.matched
                  ? null
                  : OutlinedButton(
                      onPressed: openFilters,
                      child: const Text('Изменить условия'),
                    ),
            ),
          ),
          const SizedBox(height: 24),
          cardList(
            result.recommendations.map((r) => r.contractor).toList(),
            recommendations: result.recommendations,
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
              child: const Text('Показать ещё'),
            ),
          ),
        ],
      ],
    );
  }

  void browseCatalog() {
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
    final label = controller.lastRequest == null
        ? 'Подобрать под событие'
        : 'Изменить фильтры';
    if (iconOnly) {
      return IconButton.filled(
        key: const Key('open-filters'),
        style: IconButton.styleFrom(foregroundColor: AppColors.white),
        onPressed: enabled ? openFilters : null,
        tooltip: label,
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
        'Команда вашего события',
        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -1,
        ),
      ),
      const SizedBox(height: 12),
      const Text('Условия подбора', style: TextStyle(color: AppColors.muted)),
      const SizedBox(height: 16),
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
        label: const Text('Сбросить фильтры'),
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
          labelText: 'Поиск в каталоге',
          hintText: 'Имя подрядчика или город',
          prefixIcon: const Icon(Icons.search, size: 21),
          fillColor: AppColors.white,
          suffixIcon: query.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Очистить поиск',
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
              label: const Text('Как это работает'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        const Text(
          'Сделано для особенных событий в Казахстане.',
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
    listenable: controller,
    builder: (context, _) {
      final size = MediaQuery.sizeOf(context);
      final largeText = MediaQuery.textScalerOf(context).scale(16) > 24;
      final mobile = size.width < 700 || largeText;
      final desktop = size.width >= 1200 && !largeText;
      final gutter = size.width < 600 ? 16.0 : 32.0;
      final request = controller.lastRequest;
      return Scaffold(
        appBar: AppBar(
          toolbarHeight: desktop ? 84 : 68,
          automaticallyImplyLeading: false,
          titleSpacing: 0,
          title: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1280),
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
                        child: const Text('Каталог специалистов'),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: showHelp,
                        child: const Text('Как это работает'),
                      ),
                      const SizedBox(width: 32),
                      const Icon(
                        Icons.place_outlined,
                        size: 17,
                        color: AppColors.muted,
                      ),
                      const SizedBox(width: 5),
                      const Text(
                        'Казахстан',
                        style: TextStyle(fontSize: 12, color: AppColors.muted),
                      ),
                      const SizedBox(width: 24),
                    ] else
                      IconButton(
                        onPressed: showHelp,
                        tooltip: 'Как это работает',
                        icon: const Icon(Icons.help_outline, size: 22),
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
                    constraints: const BoxConstraints(maxWidth: 1280),
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
                          if (request == null) ...[
                            CatalogHero(
                              count: controller.catalog.length,
                              onMatch:
                                  controller.loading ||
                                      controller.error != null ||
                                      controller.catalog.isEmpty
                                  ? null
                                  : openFilters,
                              onBrowse: browseCatalog,
                            ),
                            SizedBox(height: desktop ? 40 : 28),
                            catalogTools(),
                          ] else
                            requestSummary(request),
                          results(),
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
