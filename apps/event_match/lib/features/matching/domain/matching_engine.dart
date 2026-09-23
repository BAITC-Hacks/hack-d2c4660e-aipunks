import 'models.dart';

/// Deterministic baseline; independent of Flutter, network, clocks and randomness.
class MatchingEngine {
  const MatchingEngine();
  MatchResult match(List<Contractor> catalog, MatchRequest r) {
    r.validate();
    if (r.budget <= 0 ||
        (r.hours != null && (!r.hours!.isFinite || r.hours! <= 0))) {
      throw ArgumentError('Budget and duration must be positive.');
    }
    final pool = catalog
        .where((c) => c.city == r.city && c.categories.contains(r.category))
        .toList();
    if (pool.isEmpty) {
      return const MatchResult(
        MatchOutcome.categoryAbsent,
        [],
        'В этом городе такой категории пока нет в каталоге.',
      );
    }
    final rejected = <String, int>{};
    final eligible = <Contractor>[];
    for (final c in pool) {
      // One first failure per profile: counts remain additive.
      final reason = c.busyDates.contains(dateKey(r.date))
          ? 'заняты на дату'
          : c.price > r.budget
          ? 'выше бюджета'
          : !c.formats.contains(r.format)
          ? 'не берут этот формат'
          : r.language != null && !c.languages.contains(r.language)
          ? 'не работают на выбранном языке'
          : r.hours != null && c.maxHours != null && c.maxHours! < r.hours!
          ? 'не подходят по длительности'
          : null;
      if (reason != null) {
        rejected.update(reason, (n) => n + 1, ifAbsent: () => 1);
      } else {
        eligible.add(c);
      }
    }
    eligible.sort((a, b) {
      final price = a.price.compareTo(b.price);
      return price != 0 ? price : a.id.compareTo(b.id);
    });
    final reasons = rejected.entries
        .map((e) => '${e.value} — ${e.key}')
        .join('; ');
    final summary = eligible.isEmpty
        ? 'Кандидаты есть, но никто не проходит по условиям. $reasons.'
        : 'Подходят ${eligible.length} из ${pool.length}; показано ${eligible.take(3).length}.'
              '${reasons.isEmpty ? '' : ' Исключены: $reasons.'}'
              '${eligible.length < 3 && rejected.isEmpty ? ' В этой категории города всего ${pool.length} профилей.' : ''}';
    return MatchResult(
      eligible.isEmpty ? MatchOutcome.noEligible : MatchOutcome.matched,
      eligible
          .take(3)
          .map((c) {
            final facts = <String>[
              'Свободен ${dateKey(r.date)}',
              'берёт формат «${r.format}»',
              'цена от ${c.price} ₸ при бюджете ${r.budget} ₸',
              if (r.language != null) 'язык — ${r.language}',
              if (r.hours != null && c.maxHours != null)
                'работает до ${c.maxHours} ч при запросе ${r.hours} ч',
              if (r.hours != null && c.maxHours == null)
                'работа не привязана к часам присутствия',
            ];
            return Recommendation(
              c,
              '${facts.join('; ')}. Из описания: «${_excerpt(c.description)}»',
            );
          })
          .toList(growable: false),
      summary,
    );
  }
}

String _excerpt(String text) {
  final clean = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  final sentence =
      RegExp(r'^.*?[.!?](?:\s|$)').firstMatch(clean)?.group(0)?.trim() ?? clean;
  if (sentence.length <= 220) return sentence;
  final cut = sentence.lastIndexOf(' ', 220);
  return '${sentence.substring(0, cut > 0 ? cut : 220)}…';
}
