import 'package:flutter/material.dart';

import '../../../../app/design_tokens.dart';
import '../../../matching/presentation/widgets/contractor_details.dart';
import '../../../matching/presentation/widgets/side_panel.dart';
import '../../../matching/domain/models.dart';
import '../../../matching/presentation/widgets/contractor_card.dart';

/// Compact results keep the next decision visible; details reuse the catalogue.
class AssistantRecommendations extends StatelessWidget {
  const AssistantRecommendations({
    super.key,
    required this.recommendations,
    required this.unverified,
    required this.preliminary,
    required this.onReject,
    this.enabled = true,
  });

  final List<Recommendation> recommendations;
  final Map<String, List<String>> unverified;
  final bool preliminary;
  final bool enabled;
  final Future<void> Function(String id, String reason) onReject;

  Future<void> _reject(BuildContext context, Contractor contractor) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => _RejectDialog(name: contractor.name),
    );
    if (reason != null) await onReject(contractor.id, reason);
  }

  void _compare(BuildContext context) {
    showSidePanel<void>(
      context,
      barrierLabel: 'Закрыть сравнение',
      builder: (context) => SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Сравнение подборки',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'Закрыть сравнение',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'Только сведения из профилей. Стоимость — от указанной суммы.',
            ),
            const SizedBox(height: 24),
            LayoutBuilder(
              builder: (context, constraints) {
                final largeText =
                    MediaQuery.textScalerOf(context).scale(16) > 24;
                final columns = largeText || constraints.maxWidth < 700
                    ? 1
                    : recommendations.length;
                final width =
                    (constraints.maxWidth - (columns - 1) * 16) / columns;
                return Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: [
                    for (final recommendation in recommendations)
                      SizedBox(
                        width: width,
                        child: _ComparisonProfile(
                          recommendation: recommendation,
                          unverified:
                              unverified[recommendation.contractor.id] ??
                              const [],
                        ),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 24),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Вернуться к чату'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _details(BuildContext context, Recommendation recommendation, int rank) {
    showContractorDetails(
      context,
      contractor: recommendation.contractor,
      explanation: recommendation.explanation,
      generated: recommendation.source == 'llm',
    );
  }

  Widget _card(BuildContext context, Recommendation recommendation, int rank) {
    final c = recommendation.contractor;
    final theme = Theme.of(context);
    final unchecked = unverified[c.id] ?? const [];
    return Container(
      key: ValueKey('assistant-contractor-${c.id}'),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ExcludeSemantics(
                child: CircleAvatar(
                  radius: 22,
                  backgroundColor: AppColors.categorySurface(
                    c.categories.first,
                  ),
                  child: Icon(
                    categoryIcon(c.categories.first),
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '№$rank · ${c.categories.join(', ')} · ${c.city}',
                      style: theme.textTheme.labelMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      c.name,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text('от ${money(c.price)} ₸', style: theme.textTheme.titleLarge),
          const SizedBox(height: 12),
          Text(recommendation.explanation),
          if (unchecked.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(unchecked.join(' · '), style: theme.textTheme.bodySmall),
          ],
          const SizedBox(height: 12),
          Text(
            [
              c.synthetic
                  ? 'Синтетический профиль'
                  : 'Анонимизированный профиль',
              if (c.priceImputed) 'Цена восстановлена',
              if (c.cityImputed) 'Город восстановлен',
            ].join(' · '),
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                key: ValueKey('assistant-details-${c.id}'),
                onPressed: enabled
                    ? () => _details(context, recommendation, rank)
                    : null,
                child: Text(
                  'Подробнее',
                  semanticsLabel: 'Подробнее о ${c.name}',
                ),
              ),
              if (recommendations.length > 1)
                OutlinedButton(
                  key: ValueKey('assistant-compare-${c.id}'),
                  onPressed: enabled ? () => _compare(context) : null,
                  child: Text(
                    'Сравнить',
                    semanticsLabel: 'Сравнить ${c.name} с другими вариантами',
                  ),
                ),
              TextButton(
                key: ValueKey('assistant-reject-${c.id}'),
                onPressed: enabled ? () => _reject(context, c) : null,
                child: Text(
                  'Не подходит',
                  semanticsLabel: 'Исключить ${c.name} из подборки',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (preliminary)
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Text(
            'Предварительная подборка',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
      LayoutBuilder(
        builder: (context, constraints) {
          final columns =
              constraints.maxWidth >= 800 &&
                  MediaQuery.textScalerOf(context).scale(16) <= 24
              ? 2
              : 1;
          final width = (constraints.maxWidth - (columns - 1) * 16) / columns;
          return Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              for (var index = 0; index < recommendations.length; index++)
                SizedBox(
                  width: width,
                  child: _card(context, recommendations[index], index + 1),
                ),
            ],
          );
        },
      ),
    ],
  );
}

class _ComparisonProfile extends StatelessWidget {
  const _ComparisonProfile({
    required this.recommendation,
    required this.unverified,
  });
  final Recommendation recommendation;
  final List<String> unverified;

  @override
  Widget build(BuildContext context) {
    final c = recommendation.contractor;
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(c.name, style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          Text('${c.categories.join(', ')} · ${c.city}'),
          const SizedBox(height: 12),
          Text('от ${money(c.price)} ₸', style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          Text('Языки: ${c.languages.join(', ')}'),
          const SizedBox(height: 12),
          Text(
            c.maxHours == null
                ? 'Длительность не указана'
                : 'До ${c.maxHours!.toString().replaceFirst(RegExp(r'\.0$'), '')} ч',
          ),
          const SizedBox(height: 12),
          Text('Форматы: ${c.formats.join(', ')}'),
          const SizedBox(height: 12),
          Text(
            [
              c.synthetic
                  ? 'Синтетический профиль'
                  : 'Анонимизированный профиль',
              if (c.priceImputed) 'Цена восстановлена',
              if (c.cityImputed) 'Город восстановлен',
            ].join(' · '),
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          Text(recommendation.explanation),
          if (unverified.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Нужно уточнить: ${unverified.join(' · ')}'),
          ],
        ],
      ),
    );
  }
}

class _RejectDialog extends StatefulWidget {
  const _RejectDialog({required this.name});
  final String name;

  @override
  State<_RejectDialog> createState() => _RejectDialogState();
}

class _RejectDialogState extends State<_RejectDialog> {
  final _reason = TextEditingController();
  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: const Text('Что не подошло?'),
    content: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Уберём «${widget.name}» из подборки и учтём причину.'),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final reason in ['Дорого', 'Не мой стиль', 'Мало информации'])
              ActionChip(
                label: Text(reason),
                onPressed: () => Navigator.pop(context, reason),
              ),
          ],
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _reason,
          maxLength: 300,
          minLines: 1,
          maxLines: 4,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(labelText: 'Своя причина'),
          onChanged: (_) => setState(() {}),
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) Navigator.pop(context, value.trim());
          },
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Отмена'),
      ),
      FilledButton(
        onPressed: _reason.text.trim().isEmpty
            ? null
            : () => Navigator.pop(context, _reason.text.trim()),
        child: const Text('Обновить подборку'),
      ),
    ],
  );
}
