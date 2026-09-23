import 'package:event_match/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import '../../../../app/communication_scope.dart';
import '../../domain/models.dart';
import 'ai_explanation.dart';
import 'contractor_card.dart';
import 'contractor_details.dart';

/// The selected shortlist is the comparison: all cells in a row share a height.
/// No extra selection, re-ranking, generated labels or explanation requests.
class RecommendationComparison extends StatelessWidget {
  const RecommendationComparison({
    super.key,
    required this.recommendations,
    this.unverified = const {},
    this.isFavorite,
    this.onFavorite,
    this.onReject,
    this.enabled = true,
  });
  final List<Recommendation> recommendations;
  final Map<String, List<String>> unverified;
  final bool Function(String id)? isFavorite;
  final ValueChanged<Contractor>? onFavorite;
  final ValueChanged<Contractor>? onReject;
  final bool enabled;

  Widget _content(BuildContext context, Recommendation r, int index, int row) {
    final c = r.contractor;
    final theme = Theme.of(context);
    Widget fact(String label, String value) => Column(
      key: ValueKey('comparison-${c.id}-$row'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.labelMedium),
        const SizedBox(height: 6),
        Text(value, style: theme.textTheme.bodyLarge),
      ],
    );
    switch (row) {
      case 0:
        return Column(
          key: ValueKey('comparison-profile-${c.id}'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Вариант ${index + 1}',
                    style: theme.textTheme.labelLarge,
                  ),
                ),
                if (onFavorite != null)
                  IconButton(
                    key: ValueKey('favorite-${c.id}'),
                    tooltip: trNullable(
                      context,
                      isFavorite?.call(c.id) == true
                          ? 'Сохранено в избранном'
                          : 'Сохранить в избранное',
                    ),
                    onPressed: enabled ? () => onFavorite!(c) : null,
                    icon: Icon(
                      isFavorite?.call(c.id) == true
                          ? Icons.favorite
                          : Icons.favorite_border,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              c.name,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text('${c.categories.join(' · ')} · ${c.city}'),
          ],
        );
      case 1:
        return Column(
          key: ValueKey('comparison-${c.id}-$row'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Стоимость', style: theme.textTheme.labelMedium),
            const SizedBox(height: 6),
            Text(
              'от ${money(c.price)} ₸',
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: 4),
            Text(
              'За мероприятие · предварительная цена',
              style: theme.textTheme.bodySmall,
            ),
          ],
        );
      case 2:
        return fact(
          'Длительность',
          c.maxHours == null
              ? c.isLive
                    ? 'Длительность не подтверждена'
                    : 'Без привязки к часам присутствия'
              : 'До ${c.maxHours!.toString().replaceFirst(RegExp(r'\.0$'), '')} ч',
        );
      case 3:
        return fact('Языки', c.languages.join(', '));
      case 4:
        return fact('Форматы', c.formats.join(', '));
      case 5:
        return AiExplanation(text: r.explanation, source: r.source);
      case 6:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExplanationLimitations(
              items: {...r.unchecked, ...?unverified[c.id]}.toList(),
            ),
            const SizedBox(height: 8),
            Text(
              [
                c.isLive
                    ? 'Опубликованный профиль'
                    : c.synthetic
                    ? 'Демонстрационный профиль'
                    : 'Анонимизированный профиль',
                if (c.priceImputed) 'Цена восстановлена',
                if (c.cityImputed) 'Город восстановлен',
              ].join(' · '),
              style: theme.textTheme.bodySmall,
            ),
          ],
        );
      default:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OutlinedButton.icon(
              key: ValueKey('profile-${c.id}'),
              onPressed: enabled
                  ? () => showContractorDetails(
                      context,
                      contractor: c,
                      explanation: r.explanation,
                      source: r.source,
                      unchecked: {
                        ...r.unchecked,
                        ...?unverified[c.id],
                      }.toList(),
                      recommendation: r,
                    )
                  : null,
              icon: const Icon(Icons.arrow_outward, size: 18),
              label: Text(
                'Посмотреть профиль',
                semanticsLabel: trNullable(
                  context,
                  'Посмотреть профиль ${c.name}',
                ),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              key: ValueKey('message-${c.id}'),
              onPressed:
                  enabled &&
                      c.isLive &&
                      CommunicationScope.maybeOf(context) != null
                  ? () => CommunicationScope.maybeOf(
                      context,
                    )!.openMessages(context, c)
                  : null,
              icon: const Icon(Icons.chat_bubble_outline, size: 18),
              label: Text(
                c.isLive ? 'Написать' : 'Сообщения недоступны · демо',
              ),
            ),
            if (onReject != null) ...[
              const SizedBox(height: 8),
              TextButton(
                key: ValueKey('assistant-reject-${c.id}'),
                onPressed: enabled ? () => onReject!(c) : null,
                child: Text(tr(context, 'Не подходит')),
              ),
            ],
          ],
        );
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final largeText = MediaQuery.textScalerOf(context).scale(16) > 24;
      final columns = largeText
          ? 1
          : constraints.maxWidth >= 940
          ? 3
          : constraints.maxWidth >= 620
          ? 2
          : 1;
      final colors = Theme.of(context).colorScheme;
      return Column(
        key: const Key('recommendation-comparison'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var start = 0; start < recommendations.length; start += columns)
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Table(
                defaultVerticalAlignment:
                    TableCellVerticalAlignment.intrinsicHeight,
                columnWidths: {
                  for (var i = 1; i < columns * 2 - 1; i += 2)
                    i: const FixedColumnWidth(20),
                },
                children: [
                  for (var row = 0; row < 8; row++)
                    TableRow(
                      children: [
                        for (var offset = 0; offset < columns; offset++) ...[
                          if (offset > 0) const SizedBox.shrink(),
                          if (start + offset >= recommendations.length)
                            const SizedBox.shrink()
                          else
                            Container(
                              decoration: BoxDecoration(
                                color: row == 0
                                    ? colors.primaryContainer
                                    : colors.surface,
                                border: row == 0 || row == 7
                                    ? Border.all(color: colors.outlineVariant)
                                    : Border(
                                        left: BorderSide(
                                          color: colors.outlineVariant,
                                        ),
                                        right: BorderSide(
                                          color: colors.outlineVariant,
                                        ),
                                      ),
                                borderRadius: row == 0
                                    ? const BorderRadius.vertical(
                                        top: Radius.circular(20),
                                      )
                                    : row == 7
                                    ? const BorderRadius.vertical(
                                        bottom: Radius.circular(20),
                                      )
                                    : null,
                              ),
                              padding: const EdgeInsets.all(16),
                              child: _content(
                                context,
                                recommendations[start + offset],
                                start + offset,
                                row,
                              ),
                            ),
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
}
