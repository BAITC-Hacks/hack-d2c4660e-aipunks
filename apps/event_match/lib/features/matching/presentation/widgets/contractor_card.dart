import 'package:flutter/material.dart';
import '../../domain/models.dart';
import '../../../../app/design_tokens.dart';
import 'ai_explanation.dart';

String money(int value) => value.toString().replaceAllMapped(
  RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
  (m) => '${m[1]} ',
);

const featureLabels = {
  'budget': 'Бюджет',
  'focus': 'Фокус форматов',
  'description': 'Совпадения описания',
  'language': 'Языки',
  'hours': 'Запас часов',
  'provenance': 'Множитель происхождения данных',
};

IconData categoryIcon(String category) => switch (category) {
  'Ведущий' || 'Ведущий церемонии' => Icons.mic_none_outlined,
  'Фотограф' || 'Фото и видеобудки' => Icons.camera_alt_outlined,
  'Банкетный зал' || 'Отель' => Icons.location_city_outlined,
  'Флорист' || 'Декоратор' => Icons.local_florist_outlined,
  _ => Icons.celebration_outlined,
};

class ContractorCard extends StatelessWidget {
  const ContractorCard({
    super.key,
    required this.contractor,
    this.explanation,
    this.rank,
    this.recommendation,
    this.aiSummary,
    this.summaryPending = false,
  });
  final Contractor contractor;
  final String? explanation;
  final int? rank;
  final Recommendation? recommendation;
  final String? aiSummary;
  final bool summaryPending;

  @override
  Widget build(BuildContext context) {
    final c = contractor;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            color: AppColors.categorySurface(c.categories.first),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ExcludeSemantics(
                  child: CircleAvatar(
                    radius: 34,
                    backgroundColor: colors.surface,
                    child: Icon(
                      categoryIcon(c.categories.first),
                      color: colors.primary,
                      size: 32,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        c.categories.join(' · '),
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: colors.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        rank == null
                            ? c.city
                            : 'Рекомендация №$rank · ${c.city}',
                        style: TextStyle(color: colors.onPrimaryContainer),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  c.name,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'от ${money(c.price)} ₸',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  'за мероприятие · цена предварительная',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                Text('Языки: ${c.languages.join(', ')}'),
                const SizedBox(height: 8),
                Text(
                  c.maxHours == null
                      ? 'Без привязки к часам присутствия'
                      : 'Продолжительность: до ${c.maxHours!.toString().replaceFirst(RegExp(r'\.0$'), '')} ч',
                ),
                const SizedBox(height: 8),
                Text(
                  'Форматы: ${c.formats.join(', ')}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 16),
                if (explanation != null || aiSummary != null)
                  AiExplanation(
                    text: explanation ?? aiSummary!,
                    generated:
                        recommendation?.source == 'llm' ||
                        (recommendation == null && aiSummary != null),
                  )
                else
                  Text(
                    c.description,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                if (summaryPending && aiSummary == null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Готовим краткое объяснение…',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: const Text('Подробнее о подрядчике'),
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Все форматы: ${c.formats.join(', ')}'),
                            const SizedBox(height: 12),
                            SelectableText(c.description),
                            if (recommendation != null) ...[
                              const SizedBox(height: 12),
                              Text(
                                'Оценка соответствия: ${recommendation!.score.toStringAsFixed(3)} (не рейтинг качества)',
                              ),
                              for (final entry
                                  in recommendation!.features.entries)
                                Text(
                                  '${featureLabels[entry.key] ?? entry.key}: ${entry.value.toStringAsFixed(3)}',
                                ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (recommendation != null && recommendation!.source != 'llm')
                  Text(
                    'Текст: локальные факты',
                    style: theme.textTheme.labelMedium,
                  ),
                if (recommendation?.equivalent ?? false)
                  const Text(
                    'В данных недостаточно отличий — не считаем этот вариант уникально лучшим.',
                  ),
                Text(
                  c.synthetic
                      ? (c.id.startsWith('DEMO-')
                            ? 'Демонстрационный профиль · добавлен нами'
                            : 'Синтетический профиль организаторов')
                      : 'Анонимизированный профиль',
                  style: theme.textTheme.labelMedium,
                ),
                if (c.priceImputed)
                  Text(
                    'Цена заполнена при подготовке датасета',
                    style: theme.textTheme.bodySmall,
                  ),
                if (c.cityImputed)
                  Text(
                    'Город заполнен при подготовке датасета',
                    style: theme.textTheme.bodySmall,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
