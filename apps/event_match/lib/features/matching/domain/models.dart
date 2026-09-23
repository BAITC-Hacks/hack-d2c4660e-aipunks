String dateKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

class Contractor {
  const Contractor({
    required this.id,
    required this.name,
    required this.city,
    required this.categories,
    required this.price,
    required this.formats,
    required this.languages,
    required this.busyDates,
    required this.description,
    this.maxHours,
    this.synthetic = false,
    this.cityImputed = false,
    this.priceImputed = false,
  });
  final String id, name, city, description;
  final List<String> categories, formats, languages, busyDates;
  final int price;
  final double? maxHours;
  final bool synthetic, cityImputed, priceImputed;

  factory Contractor.fromJson(Map<String, dynamic> j) => Contractor(
    id: j['id'].toString(),
    name: j['anon_name'] as String,
    city: j['city'] as String,
    categories: List<String>.from(j['categories'] as List),
    price: (j['price_from_kzt'] as num).toInt(),
    formats: List<String>.from(j['event_formats'] as List),
    languages: List<String>.from(j['languages'] as List),
    busyDates: List<String>.from(j['busy_dates'] as List),
    description: j['description'] as String,
    maxHours: (j['max_hours'] as num?)?.toDouble(),
    synthetic: j['synthetic'] as bool? ?? false,
    cityImputed: j['city_imputed'] as bool? ?? false,
    priceImputed: j['price_imputed'] as bool? ?? false,
  );
}

class MatchRequest {
  const MatchRequest({
    required this.city,
    required this.date,
    required this.format,
    required this.category,
    required this.budget,
    this.hours,
    this.language,
    this.preferences = '',
  });
  final String city, format, category;
  final DateTime date;
  final int budget;
  final double? hours;
  final String? language;
  final String preferences;

  /// Shared boundary for forms, future natural-language input and API clients.
  Map<String, Object?> toJson() => {
    'city': city,
    'date': dateKey(date),
    'event_format': format,
    'category': category,
    'budget_kzt': budget,
    'hours': hours,
    'language': language,
    'preferences': preferences.trim(),
  };

  void validate() {
    if (city.trim().isEmpty ||
        category.trim().isEmpty ||
        format.trim().isEmpty) {
      throw ArgumentError('Required order fields are empty');
    }
    if (budget <= 0 || (hours != null && (!hours!.isFinite || hours! <= 0))) {
      throw ArgumentError('Budget and duration must be positive');
    }
    final calendarDate = DateTime(date.year, date.month, date.day);
    if (calendarDate.isBefore(DateTime(2026, 9, 23)) ||
        calendarDate.isAfter(DateTime(2026, 12, 31))) {
      throw ArgumentError('Date is outside the dataset calendar');
    }
    if (preferences.trim().length > 1000) {
      throw ArgumentError('Preferences exceed 1000 characters');
    }
  }
}

enum MatchOutcome { matched, categoryAbsent, noEligible }

class Recommendation {
  const Recommendation(this.contractor, this.explanation);
  final Contractor contractor;
  final String explanation;
}

class MatchResult {
  const MatchResult(this.outcome, this.recommendations, this.summary);
  final MatchOutcome outcome;
  final List<Recommendation> recommendations;
  final String summary;
}
