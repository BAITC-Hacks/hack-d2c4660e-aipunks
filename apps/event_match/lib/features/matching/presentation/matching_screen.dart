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
  final summaries = <String, String>{};
  final summaryAttempts = <String>{};
  bool summaryBusy = false;
  bool summaryFailed = false;
  bool get aiEnabled =>
      controller.service is ApiRecommendationService &&
      (controller.service as ApiRecommendationService).aiEnabled;

  Future<void> loadNextSummaries() async {
    if (!mounted ||
        !aiEnabled ||
        summaryBusy ||
        summaryFailed ||
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

  Widget sidebar() => Container(
    width: 228,
    decoration: const BoxDecoration(
      color: AppColors.white,
      border: Border(right: BorderSide(color: AppColors.border)),
    ),
    child: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: BrandMark(),
            ),
            const SizedBox(height: 36),
            const Text(
              'ВАШЕ ПРОСТРАНСТВО',
              style: TextStyle(
                fontSize: 10,
                letterSpacing: 1.5,
                color: AppColors.muted,
              ),
            ),
            const SizedBox(height: 16),
            Material(
              color: Colors.transparent,
              child: ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                selected: true,
                selectedTileColor: AppColors.lavender,
                leading: const Icon(Icons.grid_view_outlined),
                title: const Text('Подрядчики'),
                onTap: () {
                  controller.clearResult();
                  searchInput.clear();
                  setState(() {
                    query = '';
                    browseCategory = 'Все';
                    visibleCount = 12;
                  });
                },
              ),
            ),
            const SizedBox(height: 8),
            Material(
              color: Colors.transparent,
              child: ListTile(
                leading: const Icon(Icons.lightbulb_outline),
                title: const Text('Как это работает'),
                onTap: showHelp,
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppColors.sage,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.favorite_border, color: AppColors.primary),
                  SizedBox(height: 12),
                  Text(
                    'Меньше поиска.\nБольше предвкушения.',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Всё начинается с вашего события.',
                    style: TextStyle(fontSize: 12, color: AppColors.muted),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Сделано для событий в Казахстане',
              style: TextStyle(fontSize: 11, color: AppColors.muted),
            ),
          ],
        ),
      ),
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
          : constraints.maxWidth >= 1320
          ? 3
          : constraints.maxWidth >= 840
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
                recommendation: recommendations?[i],
                aiSummary: recommendations == null && aiEnabled
                    ? summaries[profiles[i].id]
                    : null,
                summaryPending:
                    recommendations == null &&
                    aiEnabled &&
                    !summaryFailed &&
                    !summaries.containsKey(profiles[i].id),
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
        controller.error!,
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
                      controller.search(result.relaxations[i].request);
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
          const Text(
            'Часть AI-сводок недоступна. Показаны исходные описания из каталога.',
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => setState(() {
                summaryFailed = false;
                summaryAttempts.removeWhere((id) => !summaries.containsKey(id));
              }),
              child: const Text('Повторить загрузку объяснений'),
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
              child: const Text('Показать ещё'),
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar:
        MediaQuery.sizeOf(context).width >= 1200 &&
            MediaQuery.textScalerOf(context).scale(16) <= 24
        ? null
        : AppBar(
            title: const BrandMark(),
            centerTitle: false,
            actions: [
              IconButton(
                onPressed: showHelp,
                tooltip: 'Как это работает',
                icon: const Icon(Icons.help_outline),
              ),
              const SizedBox(width: 8),
            ],
          ),
    body: Row(
      children: [
        if (MediaQuery.sizeOf(context).width >= 1200 &&
            MediaQuery.textScalerOf(context).scale(16) <= 24)
          sidebar(),
        Expanded(
          child: SafeArea(
            child: ListenableBuilder(
              listenable: controller,
              builder: (context, _) {
                final request = controller.lastRequest;
                WidgetsBinding.instance.addPostFrameCallback(
                  (_) => loadNextSummaries(),
                );
                return CustomScrollView(
                  controller: pageScroll,
                  slivers: [
                    SliverToBoxAdapter(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1760),
                          child: Padding(
                            padding: EdgeInsets.all(
                              MediaQuery.sizeOf(context).width < 600 ? 16 : 24,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (request == null)
                                  CatalogHero(count: controller.catalog.length)
                                else
                                  Text(
                                    'Команда вашего события',
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineMedium
                                        ?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                const SizedBox(height: 32),
                                Wrap(
                                  // Native controls keep keyboard and touch semantics.
                                  alignment: WrapAlignment.spaceBetween,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  spacing: 16,
                                  runSpacing: 12,
                                  children: [
                                    Text(
                                      request == null
                                          ? 'Каталог · ${controller.catalog.length} профилей'
                                          : 'Условия подбора',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleLarge,
                                    ),
                                    FilledButton.icon(
                                      key: const Key('open-filters'),
                                      onPressed:
                                          controller.loading ||
                                              controller.error != null
                                          ? null
                                          : openFilters,
                                      icon: const Icon(Icons.tune),
                                      label: Text(
                                        request == null
                                            ? 'Подобрать под событие'
                                            : 'Изменить фильтры',
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                if (controller.service
                                    is ApiRecommendationService)
                                  SwitchListTile.adaptive(
                                    contentPadding: EdgeInsets.zero,
                                    title: const Text('Объяснения от ИИ'),
                                    subtitle: const Text(
                                      'Не меняет состав и порядок; без сети работают локальные объяснения',
                                    ),
                                    value:
                                        (controller.service
                                                as ApiRecommendationService)
                                            .aiEnabled,
                                    onChanged:
                                        controller.status ==
                                            SearchStatus.searching
                                        ? null
                                        : (value) {
                                            setState(
                                              () =>
                                                  (controller.service
                                                              as ApiRecommendationService)
                                                          .aiEnabled =
                                                      value,
                                            );
                                            if (controller.lastRequest !=
                                                null) {
                                              controller.search(
                                                controller.lastRequest!,
                                              );
                                            }
                                          },
                                  ),
                                if (request == null) ...[
                                  TextField(
                                    key: const Key('catalog-search'),
                                    controller: searchInput,
                                    onChanged: (value) => setState(() {
                                      query = value.trim().toLowerCase();
                                      visibleCount = 12;
                                    }),
                                    decoration: InputDecoration(
                                      hintText: 'Имя подрядчика или город',
                                      prefixIcon: const Icon(Icons.search),
                                      suffixIcon: query.isEmpty
                                          ? null
                                          : IconButton(
                                              tooltip: 'Очистить поиск',
                                              onPressed: () {
                                                searchInput.clear();
                                                setState(() => query = '');
                                              },
                                              icon: const Icon(Icons.close),
                                            ),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
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
                                          label: Text(category),
                                          selected: browseCategory == category,
                                          onSelected: (_) => setState(() {
                                            browseCategory = category;
                                            visibleCount = 12;
                                          }),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 20),
                                ],
                                if (request != null) ...[
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
                                        if (request.language != null)
                                          request.language!,
                                        if (request.hours != null)
                                          '${request.hours} ч',
                                      ])
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 8,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.secondaryContainer,
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                          child: Text(label),
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
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: TextButton.icon(
                                      key: const Key('reset-filters'),
                                      onPressed: controller.clearResult,
                                      icon: const Icon(Icons.close),
                                      label: const Text('Сбросить фильтры'),
                                    ),
                                  ),
                                ] else
                                  const Text(
                                    'Доступность и соответствие бюджету проверим после выбора условий.',
                                  ),
                                const SizedBox(height: 24),
                                results(),
                                const SizedBox(height: 32),
                                Text(
                                  'Данные организаторов · имена анонимизированы · '
                                  '${controller.catalog.where((c) => c.synthetic).length} синтетических профилей отмечены в карточках.',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    ),
  );
}
