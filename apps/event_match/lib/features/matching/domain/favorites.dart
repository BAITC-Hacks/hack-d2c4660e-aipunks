import 'models.dart';

String contractorCount(int count) {
  final tail = count % 100;
  final word = tail >= 11 && tail <= 14
      ? 'подрядчиков'
      : count % 10 == 1
      ? 'подрядчик'
      : count % 10 >= 2 && count % 10 <= 4
      ? 'подрядчика'
      : 'подрядчиков';
  return '$count $word';
}

const monthNames = [
  'Январь',
  'Февраль',
  'Март',
  'Апрель',
  'Май',
  'Июнь',
  'Июль',
  'Август',
  'Сентябрь',
  'Октябрь',
  'Ноябрь',
  'Декабрь',
];

String suggestedFolderName(MatchRequest? request) {
  if (request == null) return 'Мои подрядчики';
  final r = request.normalized();
  final format = '${r.format[0].toUpperCase()}${r.format.substring(1)}';
  return '$format · ${r.city} · ${monthNames[r.date.month - 1]} ${r.date.year}';
}

String? folderContext(MatchRequest? request) {
  if (request == null) return null;
  final r = request.normalized();
  return '${r.format}|${r.city}|${r.date.year}-${r.date.month}';
}

class FavoriteEntry {
  const FavoriteEntry({
    required this.contractorId,
    required this.name,
    this.request,
  });
  final String contractorId, name;
  // Preserve each contractor's exact search: a folder can contain several categories/dates.
  final MatchRequest? request;

  Map<String, Object?> toJson() => {
    'contractor_id': contractorId,
    'name': name,
    'request': request?.toJson(),
  };

  factory FavoriteEntry.fromJson(Map<String, dynamic> json) {
    final raw = json['request'] as Map<String, dynamic>?;
    final request = raw == null
        ? null
        : MatchRequest(
            city: raw['city'] as String,
            category: raw['category'] as String,
            date: DateTime.parse(raw['date'] as String),
            format: raw['event_format'] as String,
            budget: raw['budget_kzt'] as int,
            hours: (raw['hours'] as num?)?.toDouble(),
            language: raw['language'] as String?,
            preferences: raw['preferences'] as String? ?? '',
          );
    request?.validate();
    return FavoriteEntry(
      contractorId: json['contractor_id'] as String,
      name: json['name'] as String,
      request: request,
    );
  }
}

class FavoriteFolder {
  FavoriteFolder({
    required this.id,
    required this.name,
    this.contextKey,
    List<FavoriteEntry> entries = const [],
  }) : entries = List.unmodifiable(entries);
  final String id, name;
  final String? contextKey;
  final List<FavoriteEntry> entries;

  FavoriteFolder copyWith({String? name, List<FavoriteEntry>? entries}) =>
      FavoriteFolder(
        id: id,
        name: name ?? this.name,
        contextKey: contextKey,
        entries: entries ?? this.entries,
      );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'context': contextKey,
    'entries': entries.map((e) => e.toJson()).toList(),
  };

  factory FavoriteFolder.fromJson(Map<String, dynamic> json) {
    final entries = (json['entries'] as List)
        .map((e) => FavoriteEntry.fromJson(e as Map<String, dynamic>))
        .toList();
    if (entries.map((e) => e.contractorId).toSet().length != entries.length) {
      throw const FormatException('Duplicate favorites');
    }
    return FavoriteFolder(
      id: json['id'] as String,
      name: json['name'] as String,
      contextKey: json['context'] as String?,
      entries: entries,
    );
  }
}
