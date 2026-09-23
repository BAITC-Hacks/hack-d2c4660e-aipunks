import 'package:event_match/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import '../../domain/models.dart';
import '../../../../app/design_tokens.dart';
import 'ai_explanation.dart';
import 'contractor_details.dart';
import '../../../../app/communication_scope.dart';

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
    this.isFavorite = false,
    this.onFavorite,
    this.favoriteTooltip,
    this.aiSummary,
    this.summaryPending = false,
    this.footer,
    this.favoriteBusy = false,
  });
  final Contractor contractor;
  final String? explanation;
  final int? rank;
  final Recommendation? recommendation;
  final bool isFavorite;
  final VoidCallback? onFavorite;
  final String? favoriteTooltip;
  final String? aiSummary;
  final bool summaryPending;
  final Widget? footer;
  final bool favoriteBusy;

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
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Keep the content together and anchor the footer at the bottom.
          // With no flex children the card can first measure its natural height.
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _CategoryHeader(
                contractor: c,
                rank: rank,
                trailing: onFavorite != null || isFavorite
                    ? IconButton(
                        key: ValueKey('favorite-${c.id}'),
                        tooltip:
                            trNullable(context, favoriteTooltip ??
                            (isFavorite
                                ? 'Сохранено в избранном'
                                : 'Сохранить в избранное')),
                        isSelected: isFavorite,
                        onPressed: favoriteBusy ? null : onFavorite,
                        style: IconButton.styleFrom(
                          minimumSize: const Size(48, 48),
                          backgroundColor: colors.surface,
                          foregroundColor: colors.primary,
                        ),
                        icon: favoriteBusy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.favorite_border),
                        selectedIcon: const Icon(Icons.favorite),
                      )
                    : null,
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      c.name,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -.6,
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
                  ],
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  c.isLive
                      ? 'Опубликованный профиль'
                      : c.synthetic
                      ? 'Демонстрационный профиль'
                      : 'Анонимизированный профиль',
                  style: theme.textTheme.labelMedium,
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  key: ValueKey('profile-${c.id}'),
                  onPressed: () => showContractorDetails(
                    context,
                    contractor: c,
                    explanation: explanation ?? aiSummary,
                    generated:
                        recommendation?.source == 'llm' ||
                        (recommendation == null && aiSummary != null),
                    recommendation: recommendation,
                  ),
                  icon: const Icon(Icons.arrow_outward, size: 18),
                  label:  Text(tr(context, 'Посмотреть профиль')),
                ),
                const SizedBox(height: 8),
                Tooltip(
                  message: c.isLive
                      ? 'Связаться внутри Event Match'
                      : 'У демонстрационной анкеты нет аккаунта для переписки',
                  child: FilledButton.tonalIcon(
                    key: ValueKey('message-${c.id}'),
                    onPressed:
                        c.isLive && CommunicationScope.maybeOf(context) != null
                        ? () => CommunicationScope.maybeOf(
                            context,
                          )!.openMessages(context, c)
                        : null,
                    icon: const Icon(Icons.chat_bubble_outline, size: 18),
                    label: Text(
                      c.isLive ? 'Написать' : 'Сообщения недоступны · демо',
                    ),
                  ),
                ),
                if (footer != null) ...[const SizedBox(height: 8), footer!],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryHeader extends StatelessWidget {
  const _CategoryHeader({
    required this.contractor,
    required this.rank,
    this.trailing,
  });

  final Contractor contractor;
  final int? rank;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = contractor;
    final showSymbol = MediaQuery.textScalerOf(context).scale(16) <= 24;
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
                                style: theme.textTheme.labelMedium?.copyWith(
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
                if (trailing != null)
                  trailing!
                else if (showSymbol) ...[
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
