import 'package:flutter/material.dart';
import '../data/catalog_repository.dart';
import '../domain/models.dart';
import '../domain/recommendation_service.dart';
import 'matching_controller.dart';
import 'widgets/contractor_card.dart';
import 'widgets/order_filters.dart';

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

  @override
  void initState() {
    super.initState();
    controller = MatchingController(widget.repository, service: widget.service)
      ..load();
  }

  @override
  void dispose() {
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
    if (request != null && mounted) await controller.search(request);
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
          : constraints.maxWidth >= 1120
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
        cardList(controller.catalog.take(visibleCount).toList()),
        const SizedBox(height: 24),
        Center(
          child: Text(
            'Показано ${controller.catalog.take(visibleCount).length} из ${controller.catalog.length}',
          ),
        ),
        if (visibleCount < controller.catalog.length) ...[
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
    appBar: AppBar(title: const Text('Event Match'), centerTitle: false),
    body: SafeArea(
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final request = controller.lastRequest;
          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1280),
                    child: Padding(
                      padding: EdgeInsets.all(
                        MediaQuery.sizeOf(context).width < 600 ? 16 : 32,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Люди и места для вашего события',
                            style: Theme.of(context).textTheme.headlineMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            request == null
                                ? 'Знакомьтесь с подрядчиками или задайте условия — мы подберём до трёх подходящих вариантов.'
                                : 'Подбор по условиям вашего события. Доступность проверена на выбранную дату.',
                          ),
                          const SizedBox(height: 24),
                          Wrap(
                            alignment: WrapAlignment.spaceBetween,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 16,
                            runSpacing: 12,
                            children: [
                              Text(
                                request == null
                                    ? 'Каталог · ${controller.catalog.length} профилей'
                                    : 'Условия подбора',
                                style: Theme.of(context).textTheme.titleLarge,
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
                                      borderRadius: BorderRadius.circular(12),
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
  );
}
