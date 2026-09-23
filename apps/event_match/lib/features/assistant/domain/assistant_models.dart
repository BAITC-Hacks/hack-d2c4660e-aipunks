import '../../matching/domain/models.dart';

Map<String, dynamic> jsonMap(Object? value) =>
    Map<String, dynamic>.from(value as Map);

class AssistantPreference {
  const AssistantPreference({
    required this.text,
    this.featureId,
    this.importance = 'preferred',
    this.polarity = 'positive',
  });
  final String text;
  final String? featureId;
  final String importance, polarity;
  factory AssistantPreference.fromJson(Map<String, dynamic> j) =>
      AssistantPreference(
        text: j['text'] as String,
        featureId: j['feature_id'] as String?,
        importance: j['importance'] as String? ?? 'preferred',
        polarity: j['polarity'] as String? ?? 'positive',
      );
  Map<String, Object?> toJson() => {
    'text': text,
    'feature_id': featureId,
    'importance': importance,
    'polarity': polarity,
  };
}

class AssistantBrief {
  const AssistantBrief({
    this.city,
    this.category,
    this.eventFormat,
    this.date,
    this.budgetKzt,
    this.hours,
    this.language,
    this.preferences = const [],
    this.skippedFields = const [],
    this.excludedIds = const [],
    this.budgetScope = 'contractor',
  });
  final String? city, category, eventFormat, date, language;
  final int? budgetKzt;
  final double? hours;
  final List<AssistantPreference> preferences;
  final List<String> skippedFields, excludedIds;
  final String budgetScope;
  bool get canRecommend =>
      city != null && category != null && eventFormat != null;
  bool get dateInCalendar => dateInPolicy(const MatchDatePolicy.demo());

  bool dateInPolicy(MatchDatePolicy policy) {
    final parsed = date == null ? null : DateTime.tryParse(date!);
    return parsed != null && dateKey(parsed) == date && policy.contains(parsed);
  }

  factory AssistantBrief.fromRequest(MatchRequest r) => AssistantBrief(
    city: r.city,
    category: r.category,
    eventFormat: r.format,
    date: dateKey(r.date),
    budgetKzt: r.budget,
    hours: r.hours,
    language: r.language,
    preferences: r.preferences.isEmpty
        ? const []
        : [AssistantPreference(text: r.preferences)],
  );
  factory AssistantBrief.fromJson(Map<String, dynamic> j) => AssistantBrief(
    city: j['city'] as String?,
    category: j['category'] as String?,
    eventFormat: j['event_format'] as String?,
    date: j['date'] as String?,
    budgetKzt: (j['budget_kzt'] as num?)?.toInt(),
    hours: (j['hours'] as num?)?.toDouble(),
    language: j['language'] as String?,
    preferences: [
      for (final p in j['preferences'] as List? ?? [])
        AssistantPreference.fromJson(jsonMap(p)),
    ],
    skippedFields: List<String>.from(j['skipped_fields'] as List? ?? []),
    excludedIds: List<String>.from(j['excluded_ids'] as List? ?? []),
    budgetScope: j['budget_scope'] as String? ?? 'contractor',
  );
  Map<String, Object?> toJson() => {
    'city': city,
    'category': category,
    'event_format': eventFormat,
    'date': date,
    'budget_kzt': budgetKzt,
    'hours': hours,
    'language': language,
    'preferences': preferences.map((p) => p.toJson()).toList(),
    'skipped_fields': skippedFields,
    'excluded_ids': excludedIds,
    'budget_scope': budgetScope,
  };
  AssistantBrief withField(String field, Object? value) =>
      AssistantBrief.fromJson({...toJson(), field: value});

  MatchRequest toMatchRequest({
    MatchDatePolicy datePolicy = const MatchDatePolicy.demo(),
  }) {
    if (!canRecommend ||
        !dateInPolicy(datePolicy) ||
        budgetKzt == null ||
        budgetScope != 'contractor') {
      throw StateError(
        'Для окончательного подбора нужны дата и бюджет подрядчика.',
      );
    }
    final r = MatchRequest(
      city: city!,
      date: DateTime.parse(date!),
      format: eventFormat!,
      category: category!,
      budget: budgetKzt!,
      hours: hours,
      language: language,
      preferences: preferences.map((p) => p.text).join('; '),
    );
    r.validate(datePolicy: datePolicy);
    return r;
  }
}

class AssistantAction {
  const AssistantAction({
    required this.id,
    required this.label,
    required this.type,
    this.field,
    this.value,
  });
  final String id, label, type;
  final String? field;
  final Object? value;
  factory AssistantAction.fromJson(Map<String, dynamic> j) => AssistantAction(
    id: j['id'] as String,
    label: j['label'] as String,
    type: j['type'] as String,
    field: j['field'] as String?,
    value: j['value'],
  );
  Map<String, Object?> toJson() => {
    'id': id,
    'label': label,
    'type': type,
    if (field != null) 'field': field,
    if (value != null) 'value': value,
  };
}

class AssistantEvidence {
  const AssistantEvidence({
    required this.featureId,
    required this.quote,
    required this.status,
  });
  final String featureId, quote, status;
  factory AssistantEvidence.fromJson(Map<String, dynamic> j) =>
      AssistantEvidence(
        featureId: j['feature_id'] as String,
        quote: j['quote'] as String,
        status: j['status'] as String,
      );
}

class AssistantRecommendation {
  const AssistantRecommendation({
    required this.contractor,
    required this.explanation,
    this.unchecked = const [],
    this.evidence = const [],
  });
  final Contractor contractor;
  final String explanation;
  final List<String> unchecked;
  final List<AssistantEvidence> evidence;
  factory AssistantRecommendation.fromJson(Map<String, dynamic> j) =>
      AssistantRecommendation(
        contractor: Contractor.fromJson(jsonMap(j['contractor'])),
        explanation: j['explanation'] as String,
        unchecked: List<String>.from(j['unchecked'] as List? ?? []),
        evidence: [
          for (final e in j['evidence'] as List? ?? [])
            AssistantEvidence.fromJson(jsonMap(e)),
        ],
      );
}

class AssistantResult {
  const AssistantResult({
    required this.outcome,
    required this.recommendations,
    required this.summary,
    this.preliminary = false,
    this.unchecked = const [],
  });
  final MatchOutcome outcome;
  final List<AssistantRecommendation> recommendations;
  final String summary;
  final bool preliminary;
  final List<String> unchecked;
  factory AssistantResult.fromJson(Map<String, dynamic> j) => AssistantResult(
    outcome: switch (j['outcome']) {
      'matched' => MatchOutcome.matched,
      'category_absent' => MatchOutcome.categoryAbsent,
      'no_eligible' => MatchOutcome.noEligible,
      _ => throw const FormatException('Unknown recommendation outcome'),
    },
    recommendations: [
      for (final r in j['recommendations'] as List)
        AssistantRecommendation.fromJson(jsonMap(r)),
    ],
    summary: j['summary'] as String,
    preliminary: j['preliminary'] as bool? ?? false,
    unchecked: List<String>.from(j['unchecked'] as List? ?? []),
  );
  MatchResult toMatchResult() => MatchResult(outcome, [
    for (final r in recommendations)
      Recommendation(r.contractor, r.explanation),
  ], summary);
}

class AssistantTurn {
  const AssistantTurn({
    required this.brief,
    required this.message,
    this.actions = const [],
    this.questionField,
    this.result,
    this.mode = 'ai',
    this.warnings = const [],
    this.datasetVersion = '',
    this.algorithmVersion = '',
  });
  final AssistantBrief brief;
  final String message;
  final List<AssistantAction> actions;
  final String? questionField;
  final AssistantResult? result;
  final String mode;
  final List<String> warnings;
  final String datasetVersion, algorithmVersion;
  factory AssistantTurn.fromJson(Map<String, dynamic> j) => AssistantTurn(
    brief: AssistantBrief.fromJson(jsonMap(j['brief'])),
    message: j['message'] as String,
    actions: [
      for (final a in j['actions'] as List? ?? [])
        AssistantAction.fromJson(jsonMap(a)),
    ],
    questionField: j['question_field'] as String?,
    result: j['result'] == null
        ? null
        : AssistantResult.fromJson(jsonMap(j['result'])),
    mode: j['mode'] as String? ?? 'ai',
    warnings: List<String>.from(j['warnings'] as List? ?? []),
    datasetVersion: j['dataset_version'] as String? ?? '',
    algorithmVersion: j['algorithm_version'] as String? ?? '',
  );
}

class AssistantMessage {
  const AssistantMessage({required this.role, required this.text, this.turn});
  final String role, text;
  final AssistantTurn? turn;
  Map<String, String> toJson() => {'role': role, 'text': text};
}
