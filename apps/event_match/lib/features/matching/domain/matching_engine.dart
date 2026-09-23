import 'catalog_version.dart';
import 'explanation_policy.dart';
import 'models.dart';
import 'normalization.dart';

const scoreWeights = {
  'budget': .30,
  'focus': .20,
  'description': .20,
  'language': .15,
  'hours': .15,
};

class MatchingEngine {
  const MatchingEngine();

  List<Evaluation> evaluate(
    List<Contractor> catalog,
    MatchRequest request, {
    Map<String, AvailabilityStatus> availability = const {},
  }) {
    final r = request.normalized();
    return catalog
        .where(
          (c) =>
              canonical('city', c.city) == canonical('city', r.city) &&
              c.categories.any(
                (v) =>
                    canonical('category', v) ==
                    canonical('category', r.category),
              ),
        )
        .map(
          (c) => Evaluation(c, {
            if (!c.formats.any(
              (v) => canonical('format', v) == canonical('format', r.format),
            ))
              Violation.format,
            if (r.language != null &&
                !c.languages.any(
                  (v) =>
                      canonical('language', v) ==
                      canonical('language', r.language!),
                ))
              Violation.language,
            if (r.hours != null && c.maxHours != null && c.maxHours! < r.hours!)
              Violation.hours,
            if (c.isLive
                ? availability[c.id] == AvailabilityStatus.busy
                : c.busyDates.contains(dateKey(r.date)))
              Violation.busy,
            if (c.isLive &&
                (availability[c.id] == null ||
                    availability[c.id] == AvailabilityStatus.unconfirmed))
              Violation.unconfirmed,
            if (c.price > r.budget) Violation.budget,
          }),
        )
        .toList();
  }

  Map<String, double> features(Contractor c, MatchRequest r) {
    final ratio = c.price / r.budget;
    final languages = c.languages.map((v) => canonical('language', v)).toSet();
    final text = normalize(c.description);
    final hits = keywords(r).where((word) => text.contains(word)).length;
    return {
      'budget': ratio < .6
          ? .5 + .5 * ratio / .6
          : ratio <= .9
          ? 1
          : (1 - 4 * (ratio - .9)).clamp(0, 1),
      'focus': (1 - (c.formats.toSet().length - 1) / 5).clamp(0, 1),
      'description': (hits / 2).clamp(0, 1),
      'language': r.language != null
          ? 1
          : languages.containsAll(['ru', 'kk'])
          ? 1
          : languages.any(['ru', 'kk'].contains)
          ? .5
          : 0,
      'hours': c.maxHours == null
          ? .5
          : (r.hours == null ? c.maxHours! / 8 : (c.maxHours! - r.hours!) / 4)
                .clamp(0, 1),
      'provenance':
          (c.priceImputed ? .9 : 1) *
          (c.cityImputed ? .9 : 1) *
          (c.synthetic ? .85 : 1),
    };
  }

  double score(Map<String, double> f) =>
      scoreWeights.entries.fold<double>(
        0,
        (value, e) => value + e.value * f[e.key]!,
      ) *
      f['provenance']!;

  MatchResult match(
    List<Contractor> catalog,
    MatchRequest request, {
    MatchDatePolicy datePolicy = const MatchDatePolicy.demo(),
    Map<String, AvailabilityStatus> availability = const {},
  }) {
    request.validate(datePolicy: datePolicy);
    final r = request.normalized();
    final evaluations = evaluate(catalog, r, availability: availability);
    final eligible = evaluations
        .where((e) => e.passed)
        .map((e) => e.contractor)
        .toList();
    final featureMap = {for (final c in eligible) c.id: features(c, r)};
    eligible.sort((a, b) {
      final rank = score(featureMap[b.id]!).compareTo(score(featureMap[a.id]!));
      if (rank != 0) return rank;
      final price = a.price.compareTo(b.price);
      return price != 0 ? price : a.id.compareTo(b.id);
    });
    final top = eligible.take(3).toList();
    final counts = <Violation, int>{};
    for (final e in evaluations.where((e) => !e.passed)) {
      counts.update(e.primary!, (n) => n + 1, ifAbsent: () => 1);
    }
    const labels = {
      Violation.format: 'не берут этот формат',
      Violation.language: 'не работают на выбранном языке',
      Violation.hours: 'не подходят по длительности',
      Violation.busy: 'заняты на дату',
      Violation.budget: 'выше бюджета',
      Violation.unconfirmed: 'доступность не подтверждена',
    };
    final rejected = Violation.values
        .where(counts.containsKey)
        .map((v) => '${counts[v]} — ${labels[v]}')
        .join('; ');
    final outcome = evaluations.isEmpty
        ? MatchOutcome.categoryAbsent
        : top.isEmpty
        ? MatchOutcome.noEligible
        : MatchOutcome.matched;
    final summary = outcome == MatchOutcome.categoryAbsent
        ? 'В этом городе такой категории пока нет в каталоге.'
        : '${top.isEmpty ? 'Кандидаты есть, но никто не проходит по условиям.' : 'Подходят ${eligible.length} из ${evaluations.length}; показано ${top.length}. По календарю свободны ${dateKey(r.date)}, в профиле есть формат «${r.format}»; стартовая цена не выше ${r.budget} ₸, итоговую стоимость нужно уточнить.'}'
              '${rejected.isEmpty ? '' : ' Исключены: $rejected.'}'
              '${top.isNotEmpty && top.length < 3 && rejected.isEmpty ? ' В этой категории города всего ${evaluations.length} профилей.' : ''}';
    final mainFacts = {
      for (final c in top) c.id: _facts(c, top, r, featureMap[c.id]!),
    };
    final used = <String>{};
    final recommendations = <Recommendation>[];
    for (final c in top) {
      final distinguishing = mainFacts[c.id]!
          .where(
            (f) =>
                !used.contains(f.$1) &&
                top
                    .where((p) => p.id != c.id)
                    .every(
                      (p) => !mainFacts[p.id]!.any(
                        (other) => sameFact(other.$1, f.$1),
                      ),
                    ),
          )
          .toList();
      final equivalent =
          distinguishing.isEmpty &&
          top.any((p) => p.id != c.id && p.price == c.price);
      final main = distinguishing.isNotEmpty
          ? distinguishing.first.$1
          : mainFacts[c.id]!.first.$1;
      used.add(main);
      final fit = priceFit(c, r.budget);
      final options = ['$main. $fit.', '$fit. $main.'];
      recommendations.add(
        Recommendation(
          c,
          options.first,
          score: score(featureMap[c.id]!),
          features: featureMap[c.id]!,
          mainFact: main,
          fitFact: fit,
          equivalent: equivalent,
          explanationOptions: equivalent ? [options.first] : options,
          unchecked: [
            if (datePolicy.isLive)
              'Доступность по календарю — это не бронирование',
            if (r.hours != null && c.maxHours == null && c.isLive)
              'Длительность не подтверждена',
            if (c.priceImputed)
              'Стартовая цена восстановлена при подготовке данных',
            if (c.cityImputed) 'Город восстановлен при подготовке данных',
            if (equivalent)
              'По указанным условиям нет подтверждённого отличия от соседних вариантов',
          ],
        ),
      );
    }
    return MatchResult(
      outcome,
      recommendations,
      datePolicy.isLive
          ? '$summary Доступность по календарю, не бронирование.'
          : summary,
      evaluations: evaluations,
      catalogVersion: catalogVersion(catalog),
      relaxations: !datePolicy.isLive && eligible.length < 3
          ? _relaxations(catalog, r, evaluations)
          : const [],
      notice: r.preferences.trim().isEmpty
          ? ''
          : 'Пожелания учтены по совпадениям слов; отрицания и смысл фразы требуют проверки.',
    );
  }

  List<(String, double)> _facts(
    Contractor c,
    List<Contractor> top,
    MatchRequest r,
    Map<String, double> f,
  ) {
    final others = top.where((p) => p.id != c.id).toList();
    // Importance here is editorial only; candidate scores and order stay intact.
    return [
      for (final quote in excerpts(c.description, r))
        ('По теме запроса в описании: «$quote»', 1),
      for (final fact in requestedFitFacts(
        c,
        format: r.format,
        language: r.language,
        hours: r.hours,
      ).where((fact) => !fact.startsWith('В профиле есть')))
        (fact, .9),
      if (others.isNotEmpty && others.every((p) => p.price > c.price))
        (
          'Среди этих вариантов самая низкая стартовая цена для формата «${r.format}»',
          .8,
        ),
      ('В профиле есть ваш формат «${r.format}»', .5),
    ];
  }

  List<Relaxation> _relaxations(
    List<Contractor> catalog,
    MatchRequest r,
    List<Evaluation> evaluations,
  ) {
    final original = evaluations
        .where((e) => e.passed)
        .map((e) => e.contractor.id)
        .toSet();
    final suggestions = <Relaxation>[];
    void offer(String field, String label, MatchRequest next) {
      final passed = evaluate(
        catalog,
        next,
      ).where((e) => e.passed).map((e) => e.contractor.id).toSet();
      final added = passed.difference(original).length;
      if (added > 0) {
        suggestions.add(
          Relaxation(
            field,
            '$label — ${passed.length} вариантов (+$added новых)',
            next,
            passed.length,
            added,
          ),
        );
      }
    }

    if (evaluations.isEmpty) {
      for (final city
          in catalog.map((c) => displayValue('city', c.city)).toSet().toList()
            ..sort()) {
        if (city != r.city) {
          offer('city', 'Город: $city', r.copyWith(city: city));
        }
      }
    } else {
      final budgetOnly =
          evaluations
              .where(
                (e) =>
                    e.violations.length == 1 &&
                    e.violations.contains(Violation.budget),
              )
              .map((e) => e.contractor.price)
              .toList()
            ..sort();
      if (budgetOnly.isNotEmpty) {
        final budget = ((budgetOnly.first + 9999) ~/ 10000) * 10000;
        offer('budget', 'Бюджет $budget ₸', r.copyWith(budget: budget));
      }
      if (r.language != null) {
        offer(
          'language',
          'Без ограничения языка',
          r.copyWith(clearLanguage: true),
        );
      }
      final hoursOnly =
          evaluations
              .where(
                (e) =>
                    e.violations.length == 1 &&
                    e.violations.contains(Violation.hours),
              )
              .map((e) => e.contractor.maxHours!)
              .toList()
            ..sort();
      if (hoursOnly.isNotEmpty) {
        offer(
          'hours',
          'Длительность до ${number(hoursOnly.last)} ч',
          r.copyWith(hours: hoursOnly.last),
        );
      }
      for (final format
          in evaluations.expand((e) => e.contractor.formats).toSet().toList()
            ..sort()) {
        if (format != r.format) {
          offer('format', 'Формат: $format', r.copyWith(format: format));
        }
      }
      for (var offset = 1; offset <= 7; offset++) {
        for (final direction in [1, -1]) {
          final date = DateTime(
            r.date.year,
            r.date.month,
            r.date.day + offset * direction,
          );
          if (!date.isBefore(DateTime(2026, 9, 23)) &&
              !date.isAfter(DateTime(2026, 12, 31))) {
            offer('date', 'Дата ${dateKey(date)}', r.copyWith(date: date));
          }
        }
      }
    }
    const costs = {
      'language': 0,
      'format': 1,
      'hours': 2,
      'date': 3,
      'budget': 4,
      'city': 5,
    };
    suggestions.sort((a, b) {
      final count = b.added.compareTo(a.added);
      if (count != 0) return count;
      final cost = costs[a.field]!.compareTo(costs[b.field]!);
      if (cost != 0) return cost;
      if (a.field == 'date') {
        final distance = a.request.date
            .difference(r.date)
            .inDays
            .abs()
            .compareTo(b.request.date.difference(r.date).inDays.abs());
        if (distance != 0) return distance;
      }
      return a.label.compareTo(b.label);
    });
    return suggestions.take(3).toList();
  }
}

bool sameFact(String a, String b) {
  if (a == b) return true;
  if (!a.startsWith('По теме запроса в описании:') ||
      !b.startsWith('По теме запроса в описании:')) {
    return false;
  }
  // Ignore Latin brand names and minor inflections: a changed brand is not a benefit.
  Set<String> tokens(String text) => RegExp(r'[а-яё]{4,}')
      .allMatches(normalize(text))
      .map((m) => m.group(0)!)
      .map((v) => v.length > 6 ? v.substring(0, 6) : v)
      .toSet();
  final left = tokens(a), right = tokens(b);
  final union = left.union(right);
  return union.isNotEmpty &&
      left.intersection(right).length / union.length >= .65;
}

String number(double value) =>
    value.toString().replaceFirst(RegExp(r'\.0$'), '');

Set<String> keywords(MatchRequest r) => {
  ...?formatKeywords[canonical('format', r.format)],
  ...normalize(r.preferences)
      .split(RegExp(r'[^a-zа-яәіңғүұқөһ0-9]+'))
      .where(
        (v) =>
            v.length >= 4 &&
            !const {'хочу', 'чтобы', 'нужен', 'нужна', 'очень'}.contains(v),
      ),
};

List<String> excerpts(String description, MatchRequest r) {
  final formatTerms =
      formatKeywords[canonical('format', r.format)] ?? const <String>[];
  final allTerms = keywords(r);
  return relevantExcerpts(description, [
    ...allTerms.where((term) => !formatTerms.contains(term)),
    ...formatTerms,
  ]);
}
