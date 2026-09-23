import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../domain/models.dart';
import '../../../../app/design_tokens.dart';

String money(int value) => value.toString().replaceAllMapped(
  RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
  (m) => '${m[1]} ',
);

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
    this.footer,
  });
  final Contractor contractor;
  final String? explanation;
  final int? rank;
  final Widget? footer;

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
                if (explanation != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: colors.secondaryContainer,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Почему подходит',
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: colors.onSecondaryContainer,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          explanation!,
                          style: TextStyle(color: colors.onSecondaryContainer),
                        ),
                      ],
                    ),
                  )
                else
                  Text(
                    c.description,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
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
                            if (c.isLive && c.contact.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              SelectableText('Контакты: ${c.contact}'),
                            ],
                            for (final url in c.portfolioUrls)
                              TextButton.icon(
                                onPressed: () async {
                                  final uri = Uri.tryParse(url);
                                  if (uri == null ||
                                      uri.scheme != 'https' ||
                                      uri.host.isEmpty) {
                                    return;
                                  }
                                  final opened = await launchUrl(
                                    uri,
                                    mode: LaunchMode.externalApplication,
                                  );
                                  if (!opened && context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Не удалось открыть ссылку',
                                        ),
                                      ),
                                    );
                                  }
                                },
                                icon: const Icon(Icons.open_in_new, size: 18),
                                label: Text(
                                  url,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  c.isLive
                      ? 'Карточка проверена'
                      : c.synthetic
                      ? 'Синтетический профиль организаторов'
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
                if (c.isLive && explanation == null)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('Доступность проверим после выбора даты.'),
                  ),
                if (footer != null) ...[const SizedBox(height: 16), footer!],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
