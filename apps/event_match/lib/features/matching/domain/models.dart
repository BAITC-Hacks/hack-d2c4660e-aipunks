import 'normalization.dart';

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

  Map<String, Object?> toJson() => {
    'id': id,
    'anon_name': name,
    'city': city,
    'categories': categories,
    'price_from_kzt': price,
    'event_formats': formats,
    'languages': languages,
    'busy_dates': busyDates,
    'description': description,
    'max_hours': maxHours == maxHours?.roundToDouble()
        ? maxHours?.toInt()
        : maxHours,
    'synthetic': synthetic,
    'city_imputed': cityImputed,
    'price_imputed': priceImputed,
  };

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

  MatchRequest copyWith({
    String? city,
    DateTime? date,
    String? format,
    String? category,
    int? budget,
    double? hours,
    bool clearLanguage = false,
    String? language,
  }) => MatchRequest(
    city: city ?? this.city,
    date: date ?? this.date,
    format: format ?? this.format,
    category: category ?? this.category,
    budget: budget ?? this.budget,
    hours: hours ?? this.hours,
    language: clearLanguage ? null : language ?? this.language,
    preferences: preferences,
  );

  MatchRequest normalized() => copyWith(
    city: displayValue('city', city),
    format: displayValue('format', format),
    category: displayValue('category', category),
    language: language == null ? null : displayValue('language', language!),
  );

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
  const Recommendation(
    this.contractor,
    this.explanation, {
    this.score = 0,
    this.features = const {},
    this.mainFact = '',
    this.fitFact = '',
    this.source = 'template',
    this.equivalent = false,
  });
  final Contractor contractor;
  final String explanation;
  final double score;
  final Map<String, double> features;
  final String mainFact, fitFact, source;
  final bool equivalent;

  Recommendation withText(String text, String source) => Recommendation(
    contractor,
    text,
    score: score,
    features: features,
    mainFact: mainFact,
    fitFact: fitFact,
    source: source,
    equivalent: equivalent,
  );
}

enum Violation { format, language, hours, busy, budget }

class Evaluation {
  const Evaluation(this.contractor, this.violations);
  final Contractor contractor;
  final Set<Violation> violations;
  bool get passed => violations.isEmpty;
  Violation? get primary =>
      passed ? null : Violation.values.firstWhere(violations.contains);
}

class Relaxation {
  const Relaxation(
    this.field,
    this.label,
    this.request,
    this.count,
    this.added,
  );
  final String field, label;
  final MatchRequest request;
  final int count, added;
}

class MatchResult {
  const MatchResult(
    this.outcome,
    this.recommendations,
    this.summary, {
    this.evaluations = const [],
    this.relaxations = const [],
    this.catalogVersion = '',
    this.algorithmVersion = 'contrast-v2',
    this.notice = '',
  });
  final MatchOutcome outcome;
  final List<Recommendation> recommendations;
  final String summary;
  final List<Evaluation> evaluations;
  final List<Relaxation> relaxations;
  final String catalogVersion, algorithmVersion, notice;

  MatchResult withExplanations(List<Recommendation> cards, String notice) =>
      MatchResult(
        outcome,
        cards,
        summary,
        evaluations: evaluations,
        relaxations: relaxations,
        catalogVersion: catalogVersion,
        algorithmVersion: algorithmVersion,
        notice: notice,
      );
}
