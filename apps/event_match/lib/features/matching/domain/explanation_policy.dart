import 'models.dart';
import 'normalization.dart';

String hoursText(double value) =>
    value.toString().replaceFirst(RegExp(r'\.0$'), '');

/// Starting prices are an eligibility threshold, never a guaranteed quote.
String priceFit(Contractor c, int? budget) =>
    '${c.priceImputed ? 'Оценочная цена' : 'Цена'} от ${c.price} ₸'
    '${budget == null ? '' : ' при вашем лимите $budget ₸'}; '
    'итоговую стоимость уточните';

/// Only requested, structured fields can be asserted as confirmed matches.
List<String> requestedFitFacts(
  Contractor c, {
  required String format,
  String? language,
  double? hours,
}) => [
  if (hours != null && c.maxHours != null)
    'Для ваших ${hoursText(hours)} ч в профиле указана работа до ${hoursText(c.maxHours!)} ч; состав пакета уточните',
  if (hours != null && c.maxHours == null && !c.isLive)
    'Для формата «$format» работа не привязана к часам присутствия',
  if (language != null)
    'Для формата «$format» указан нужный вам язык «$language»',
  'В профиле есть ваш формат «$format»',
];

/// Keep entire source sentences: a keyword window can lose a preceding negation.
/// Long sentences are omitted, never shortened into a different claim.
List<String> relevantExcerpts(String description, Iterable<String> terms) {
  final result = <String>{};
  final sentences = description
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .split(RegExp(r'(?<=[.!?])\s+'));
  for (final term in terms) {
    for (final sentence in sentences) {
      final quote = sentence.replaceFirst(RegExp(r'[.!?]+$'), '').trim();
      final normalized = normalize(quote);
      if (quote.length >= 12 &&
          quote.length <= 115 &&
          !RegExp(r'[.!?«»<>]').hasMatch(quote) &&
          normalized.contains(term) &&
          !genericPhrases.any(normalized.contains)) {
        result.add(quote);
      }
    }
  }
  return result.toList();
}
