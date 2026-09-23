import 'matching_engine.dart';
import 'models.dart';

class AlternativeDate {
  const AlternativeDate(this.date, this.count);
  final DateTime date;
  final int count;
}

List<AlternativeDate> alternativeDates(
  List<Contractor> catalog,
  MatchRequest request,
) {
  final first = DateTime(2026, 9, 23), last = DateTime(2026, 12, 31);
  var start = DateTime(
    request.date.year,
    request.date.month,
    request.date.day - 3,
  );
  if (start.isBefore(first)) start = first;
  if (start.add(const Duration(days: 6)).isAfter(last)) {
    start = last.subtract(const Duration(days: 6));
  }
  const engine = MatchingEngine();
  return List.generate(7, (i) {
    final day = DateTime(start.year, start.month, start.day + i);
    return AlternativeDate(
      day,
      engine
          .evaluate(catalog, request.copyWith(date: day))
          .where((e) => e.passed)
          .length,
    );
  });
}
