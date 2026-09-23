import 'package:flutter/material.dart';
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
  });

  final Contractor contractor;
  final String? explanation;
  final int? rank;

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
          _CategoryHeader(contractor: c, rank: rank),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  c.name,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -.6,
                    height: 1.22,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'от ${money(c.price)} ₸',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontSize: 25,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -.7,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'за мероприятие · цена предварительная',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 18),
                _ProfileDetail(
                  icon: Icons.translate_outlined,
                  text: 'Языки: ${c.languages.join(', ')}',
                ),
                const SizedBox(height: 9),
                _ProfileDetail(
                  icon: Icons.schedule_outlined,
                  text: c.maxHours == null
                      ? 'Без привязки к часам присутствия'
                      : 'Продолжительность: до ${c.maxHours!.toString().replaceFirst(RegExp(r'\.0$'), '')} ч',
                ),
                const SizedBox(height: 9),
                _ProfileDetail(
                  icon: Icons.celebration_outlined,
                  text: 'Форматы: ${c.formats.join(', ')}',
                  maxLines: 2,
                ),
                const SizedBox(height: 18),
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
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          explanation!,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colors.onSecondaryContainer,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Text(
                    c.description,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                const SizedBox(height: 6),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(bottom: 18),
                  shape: const Border(),
                  collapsedShape: const Border(),
                  iconColor: colors.primary,
                  collapsedIconColor: colors.primary,
                  title: Text(
                    'Подробнее о подрядчике',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: colors.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Все форматы: ${c.formats.join(', ')}'),
                          const SizedBox(height: 12),
                          SelectableText(c.description),
                        ],
                      ),
                    ),
                  ],
                ),
                const Divider(height: 1),
                const SizedBox(height: 14),
                _ProvenanceBadge(
                  text: c.synthetic
                      ? 'Синтетический профиль организаторов'
                      : 'Анонимизированный профиль',
                  synthetic: c.synthetic,
                ),
                if (c.priceImputed) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Цена заполнена при подготовке датасета',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
                if (c.cityImputed) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Город заполнен при подготовке датасета',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryHeader extends StatelessWidget {
  const _CategoryHeader({required this.contractor, required this.rank});

  final Contractor contractor;
  final int? rank;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = contractor;
    return LayoutBuilder(
      builder: (context, constraints) {
        final showSymbol =
            constraints.maxWidth >= 330 &&
            MediaQuery.textScalerOf(context).scale(16) <= 24;
        return Container(
          color: AppColors.categorySurface(c.categories.first),
          constraints: const BoxConstraints(minHeight: 136),
          child: Stack(
            children: [
              const Positioned.fill(
                child: ExcludeSemantics(
                  child: CustomPaint(painter: _CategoryBackdrop()),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.white.withValues(alpha: .82),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ExcludeSemantics(
                                  child: Icon(
                                    categoryIcon(c.categories.first),
                                    size: 15,
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    c.categories.join(' · '),
                                    style: theme.textTheme.labelMedium
                                        ?.copyWith(
                                          color: theme.colorScheme.onSurface,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          height: 1.35,
                                        ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ExcludeSemantics(
                                child: Icon(
                                  Icons.place_outlined,
                                  size: 16,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(width: 5),
                              Expanded(
                                child: Text(
                                  rank == null
                                      ? c.city
                                      : 'Рекомендация №$rank · ${c.city}',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurface,
                                    fontWeight: FontWeight.w500,
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (showSymbol) ...[
                      const SizedBox(width: 14),
                      ExcludeSemantics(
                        child: Container(
                          width: 68,
                          height: 68,
                          decoration: BoxDecoration(
                            color: AppColors.white.withValues(alpha: .72),
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(
                              color: AppColors.white.withValues(alpha: .8),
                            ),
                          ),
                          child: Icon(
                            categoryIcon(c.categories.first),
                            size: 32,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _CategoryBackdrop extends CustomPainter {
  const _CategoryBackdrop();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = AppColors.white.withValues(alpha: .34);
    final shape = Path()
      ..moveTo(size.width * .7, 0)
      ..cubicTo(
        size.width * .58,
        size.height * .32,
        size.width * .94,
        size.height * .53,
        size.width * .74,
        size.height,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(size.width, 0)
      ..close();
    canvas.drawPath(shape, paint);
    paint
      ..color = AppColors.white.withValues(alpha: .66)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(Offset(size.width - 44, size.height + 8), 49, paint);
    canvas.drawCircle(Offset(size.width - 44, size.height + 8), 64, paint);
    paint
      ..style = PaintingStyle.fill
      ..color = AppColors.white.withValues(alpha: .75);
    canvas.drawCircle(Offset(size.width * .57, 21), 3, paint);
    canvas.drawCircle(Offset(size.width * .64, size.height - 22), 2, paint);
  }

  @override
  bool shouldRepaint(covariant _CategoryBackdrop oldDelegate) => false;
}

class _ProfileDetail extends StatelessWidget {
  const _ProfileDetail({required this.icon, required this.text, this.maxLines});

  final IconData icon;
  final String text;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExcludeSemantics(
          child: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              icon,
              size: 17,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            text,
            maxLines: maxLines,
            overflow: maxLines == null ? null : TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontSize: 13,
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }
}

class _ProvenanceBadge extends StatelessWidget {
  const _ProvenanceBadge({required this.text, required this.synthetic});

  final String text;
  final bool synthetic;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: synthetic ? AppColors.peach : AppColors.canvas,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(
                Icons.info_outline,
                size: 14,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
