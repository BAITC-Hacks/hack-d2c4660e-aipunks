import 'package:flutter/material.dart';
import '../../../../app/design_tokens.dart';

/// The photo sets the atmosphere and is not a contractor's portfolio.
class CatalogHero extends StatelessWidget {
  const CatalogHero({
    super.key,
    required this.count,
    required this.onMatch,
    required this.onBrowse,
  });
  final int count;
  final VoidCallback? onMatch;
  final VoidCallback onBrowse;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final largeText = MediaQuery.textScalerOf(context).scale(16) > 24;
      final wide = constraints.maxWidth >= 840 && !largeText;
      final compact = constraints.maxWidth < 600;
      final titleSize = wide
          ? 48.0
          : compact
          ? 30.0
          : 40.0;
      return Container(
        decoration: BoxDecoration(
          color: AppColors.hero,
          borderRadius: BorderRadius.circular(compact ? 24 : 32),
        ),
        padding: EdgeInsets.all(
          wide
              ? 40
              : compact
              ? 24
              : 32,
        ),
        child: Row(
          children: [
            Expanded(
              flex: 6,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      ExcludeSemantics(
                        child: Icon(
                          Icons.wb_sunny_outlined,
                          size: 18,
                          color: AppColors.primary,
                        ),
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'СОБЫТИЯ С ВАШИМ ХАРАКТЕРОМ',
                          style: TextStyle(
                            fontSize: 10,
                            letterSpacing: 1.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: wide ? 28 : 16),
                  Text(
                    'Особенный день.',
                    style: TextStyle(
                      fontSize: titleSize,
                      height: 1.16,
                      letterSpacing: -1.8,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
                  ),
                  Text(
                    'Подходящие люди.',
                    style: TextStyle(
                      fontFamily: 'CormorantGaramond',
                      fontStyle: FontStyle.italic,
                      fontSize: titleSize + (wide ? 12 : 8),
                      height: 1.13,
                      letterSpacing: -1,
                      color: AppColors.primary,
                    ),
                  ),
                  SizedBox(height: compact ? 12 : 18),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 450),
                    child: const Text(
                      'Ведущий, фотограф, флорист — найдите тех, кто почувствует ваше событие. Подберём по городу, дате и бюджету.',
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.65,
                        color: AppColors.muted,
                      ),
                    ),
                  ),
                  SizedBox(height: compact ? 8 : 24),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (!compact)
                        FilledButton(
                          key: const Key('hero-match'),
                          onPressed: onMatch,
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(child: Text('Найти свою команду')),
                              SizedBox(width: 14),
                              Icon(Icons.arrow_outward, size: 18),
                            ],
                          ),
                        ),
                      TextButton(
                        onPressed: onBrowse,
                        child: const Text('Смотреть каталог'),
                      ),
                    ],
                  ),
                  SizedBox(
                    height: wide
                        ? 28
                        : compact
                        ? 4
                        : 16,
                  ),
                  Wrap(
                    spacing: 16,
                    runSpacing: 8,
                    children: [
                      _Fact(
                        icon: Icons.people_outline,
                        text: '$count профилей',
                      ),
                      if (!compact)
                        const _Fact(
                          icon: Icons.check_circle_outline,
                          text: 'До 3 рекомендаций с объяснением',
                        ),
                    ],
                  ),
                ],
              ),
            ),
            if (wide) ...[
              const SizedBox(width: 36),
              Expanded(
                flex: 4,
                child: ExcludeSemantics(
                  child: SizedBox(
                    height: 348,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned.fill(
                          left: 22,
                          bottom: 16,
                          child: ClipRRect(
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(140),
                              topRight: Radius.circular(140),
                              bottomLeft: Radius.circular(20),
                              bottomRight: Radius.circular(20),
                            ),
                            child: Image.asset(
                              'assets/images/event-table.jpg',
                              key: const Key('catalog-hero-photo'),
                              fit: BoxFit.cover,
                              alignment: const Alignment(0, .72),
                              // Keep the reserved photo area intact if a stale
                              // dev bundle or failed load cannot supply it.
                              errorBuilder: (context, error, stackTrace) =>
                                  const ColoredBox(
                                    color: AppColors.sage,
                                    child: Center(
                                      child: Icon(
                                        Icons.celebration_outlined,
                                        size: 64,
                                        color: AppColors.primary,
                                      ),
                                    ),
                                  ),
                            ),
                          ),
                        ),
                        Positioned(
                          top: 8,
                          left: 0,
                          child: Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              color: AppColors.peach,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: AppColors.hero,
                                width: 5,
                              ),
                            ),
                            child: const Icon(
                              Icons.wb_sunny_outlined,
                              size: 30,
                              color: AppColors.plum,
                            ),
                          ),
                        ),
                        Positioned(
                          left: 0,
                          right: 24,
                          bottom: 0,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 16,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.white,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.plum.withValues(alpha: .07),
                                  blurRadius: 24,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: const Row(
                              children: [
                                CircleAvatar(
                                  radius: 20,
                                  backgroundColor: AppColors.sage,
                                  child: Icon(
                                    Icons.favorite_border,
                                    size: 20,
                                    color: AppColors.plum,
                                  ),
                                ),
                                SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Всё начинается с людей',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 12,
                                        ),
                                      ),
                                      SizedBox(height: 3),
                                      Text(
                                        'Остальное — дело вашей команды',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: AppColors.muted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    },
  );
}

class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      ExcludeSemantics(child: Icon(icon, size: 16, color: AppColors.primary)),
      const SizedBox(width: 6),
      Flexible(
        child: Text(
          text,
          style: const TextStyle(fontSize: 11, color: AppColors.muted),
        ),
      ),
    ],
  );
}

class BrandMark extends StatelessWidget {
  const BrandMark({super.key});
  @override
  Widget build(BuildContext context) => const Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
        child: Padding(
          padding: EdgeInsets.all(9),
          child: Icon(
            Icons.filter_vintage_outlined,
            color: AppColors.white,
            size: 22,
          ),
        ),
      ),
      SizedBox(width: 10),
      Flexible(
        child: Text(
          'event match',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 20,
            letterSpacing: -.7,
            color: AppColors.ink,
          ),
        ),
      ),
    ],
  );
}
