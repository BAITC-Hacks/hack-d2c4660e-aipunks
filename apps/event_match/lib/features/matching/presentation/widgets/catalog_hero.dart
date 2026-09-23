import 'package:flutter/material.dart';
import '../../../../app/design_tokens.dart';

class CatalogHero extends StatelessWidget {
  const CatalogHero({super.key, required this.count});
  final int count;
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
    final wide = constraints.maxWidth > 850 && MediaQuery.textScalerOf(context).scale(16) < 24;
    return Container(padding: EdgeInsets.all(wide ? 36 : 24),
      decoration: BoxDecoration(color: AppColors.lavender, borderRadius: BorderRadius.circular(28)),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('БОЛЬШИЕ СОБЫТИЯ НАЧИНАЮТСЯ С ЛЮДЕЙ',
            style: TextStyle(fontSize: 11, letterSpacing: 1.6, fontWeight: FontWeight.w700, color: AppColors.primary)),
          const SizedBox(height: 16),
          Text('Ваше событие.\nВаша команда.', style: TextStyle(fontSize: wide ? 42 : 30,
            height: 1.12, letterSpacing: -1.2, fontWeight: FontWeight.w700, color: AppColors.ink)),
          const SizedBox(height: 16),
          const Text('Найдите тех, кто сделает ваш день особенным.\nМы поможем выбрать и объясним почему.',
            style: TextStyle(color: AppColors.muted, height: 1.5)),
          const SizedBox(height: 20),
          Wrap(spacing: 16, runSpacing: 8, children: [
            Text('$count профилей в каталоге', style: const TextStyle(fontWeight: FontWeight.w600)),
            const Text('До 3 точных рекомендаций', style: TextStyle(color: AppColors.primary)),
          ]),
        ])),
        if (wide) ...[const SizedBox(width: 32),
          ExcludeSemantics(child: SizedBox(width: 220, height: 200, child: Stack(alignment: Alignment.center, children: [
            Container(width: 180, height: 180, decoration: const BoxDecoration(color: AppColors.white, shape: BoxShape.circle)),
            Transform.rotate(angle: -.12, child: Container(width: 150, height: 160,
              decoration: BoxDecoration(color: AppColors.peach, borderRadius: BorderRadius.circular(24)))),
            Transform.rotate(angle: .10, child: Container(width: 138, height: 154,
              decoration: BoxDecoration(color: AppColors.sage, borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppColors.white, width: 3)),
              child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.celebration_outlined, size: 44, color: AppColors.primary), SizedBox(height: 16),
                Text('IT’S A MATCH', style: TextStyle(letterSpacing: 2, fontSize: 11, fontWeight: FontWeight.w700)),
              ]))),
          ]))),
        ],
      ]));
  });
}

class BrandMark extends StatelessWidget {
  const BrandMark({super.key});
  @override
  Widget build(BuildContext context) => const Row(mainAxisSize: MainAxisSize.min, children: [
    DecoratedBox(decoration: BoxDecoration(color: AppColors.primary,
      borderRadius: BorderRadius.all(Radius.circular(12))),
      child: Padding(padding: EdgeInsets.all(9), child: Icon(Icons.auto_awesome_outlined, color: AppColors.white, size: 22))),
    SizedBox(width: 10), Text('event match', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20, letterSpacing: -.5)),
  ]);
}
