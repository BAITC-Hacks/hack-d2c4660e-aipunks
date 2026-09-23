import '../domain/models.dart';

/// Presentation only: never changes candidates, their order or explanations.
class SelectionPresentation {
  const SelectionPresentation({
    required this.outcome,
    required this.count,
    required this.summary,
    this.preliminary = false,
  });

  final MatchOutcome outcome;
  final int count;
  final String summary;
  final bool preliminary;

  String get title => switch (outcome) {
    MatchOutcome.categoryAbsent => 'В этом городе категории пока нет',
    MatchOutcome.noEligible => 'Нет подходящих кандидатов',
    MatchOutcome.matched when preliminary =>
      'Предварительная подборка · $count',
    MatchOutcome.matched when count == 3 =>
      '3 лучших кандидата под ваши условия',
    MatchOutcome.matched when count == 2 => 'Подобрали 2 варианта',
    MatchOutcome.matched => 'Подобрали 1 вариант',
  };

  // Keep the original statistics available in the disclosure, not the headline.
  // Legacy and assistant engines currently return this metadata as prose.
  String get withoutCounts => summary
      .replaceFirst(
        RegExp(
          r'^(?:Предварительно подходят|Проходят по указанным условиям|Подходят)\s+\d+\s+из\s+\d+;\s*показано\s+\d+\.\s*',
        ),
        '',
      )
      .trim();

  String get visibleNote {
    if (outcome != MatchOutcome.matched) return summary;
    if (count < 3) {
      return withoutCounts.isEmpty
          ? 'В этой категории города доступно только $count ${count == 1 ? 'предложение' : 'предложения'} по указанным условиям.'
          : withoutCounts;
    }
    return preliminary
        ? 'Сравните варианты. Не все условия проверены — уточнения указаны ниже.'
        : 'Сравнение уже перед вами. Порядок определён условиями подбора.';
  }

  String presentMessage(String message, {bool comparisonOnPage = false}) {
    if (summary.isEmpty || !message.contains(summary)) return message;
    final note =
        comparisonOnPage &&
            outcome == MatchOutcome.matched &&
            count == 3 &&
            !preliminary
        ? 'Сравнение готово на основной странице.'
        : visibleNote;
    return message.replaceFirst(summary, '$title. $note');
  }
}
