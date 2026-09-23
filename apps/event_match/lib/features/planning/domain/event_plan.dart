import '../../workspace/domain/workspace_models.dart' show contractorCategories;

/// Personal planning reminders. Completing one is not supplier confirmation.
const planningTasks = <String, String>{
  'confirm_scope': 'Уточнить состав услуг',
  'confirm_final_price': 'Уточнить итоговую стоимость',
  'confirm_terms': 'Обсудить условия и договор',
};

const _unchangedBudget = Object();

class PlanChoice {
  const PlanChoice({required this.selectionId, required this.contractorId});

  final String selectionId, contractorId;

  Map<String, dynamic> toMap() => {
    'selectionId': selectionId,
    'contractorId': contractorId,
  };

  factory PlanChoice.fromMap(Map<String, dynamic> map) => PlanChoice(
    selectionId: map['selectionId'] as String,
    contractorId: map['contractorId'] as String,
  );
}

/// A private event plan stores references, never publication or booking claims.
class EventPlan {
  const EventPlan({
    required this.eventId,
    this.totalBudgetKzt,
    this.choices = const {},
    this.completedTaskIds = const {},
    this.notes = '',
    this.revision = 0,
  });

  final String eventId;
  final int? totalBudgetKzt;
  final Map<String, PlanChoice> choices;
  final Set<String> completedTaskIds;
  final String notes;
  final int revision;

  void validate() {
    bool validReference(String value) =>
        value.trim().isNotEmpty &&
        value.length <= 160 &&
        !value.contains('/') &&
        value != '.' &&
        value != '..';
    if (!validReference(eventId)) {
      throw ArgumentError('Необходимо существующее мероприятие');
    }
    if (totalBudgetKzt != null &&
        (totalBudgetKzt! < 1 || totalBudgetKzt! > 1000000000)) {
      throw ArgumentError('Бюджет должен быть от 1 до 1 000 000 000 ₸');
    }
    if (notes.length > 2000) {
      throw ArgumentError('Заметка не должна превышать 2000 символов');
    }
    if (revision < 0) throw ArgumentError('Некорректная версия плана');
    if (choices.length > 10 ||
        choices.keys.any(
          (category) => !contractorCategories.contains(category),
        )) {
      throw ArgumentError('Выберите существующие категории подрядчиков');
    }
    if (choices.values.any(
      (choice) =>
          !validReference(choice.selectionId) ||
          !validReference(choice.contractorId),
    )) {
      throw ArgumentError('Некорректная ссылка на подборку или подрядчика');
    }
    if (choices.values.map((choice) => choice.contractorId).toSet().length !=
        choices.length) {
      throw ArgumentError('Подрядчик уже выбран в другой категории');
    }
    if (completedTaskIds.any((id) => !planningTasks.containsKey(id))) {
      throw ArgumentError('Неизвестный пункт подготовки');
    }
  }

  /// Pass `totalBudgetKzt: null` to explicitly clear the event budget.
  EventPlan copyWith({
    Object? totalBudgetKzt = _unchangedBudget,
    Map<String, PlanChoice>? choices,
    Set<String>? completedTaskIds,
    String? notes,
    int? revision,
  }) => EventPlan(
    eventId: eventId,
    totalBudgetKzt: identical(totalBudgetKzt, _unchangedBudget)
        ? this.totalBudgetKzt
        : totalBudgetKzt as int?,
    choices: Map.unmodifiable(choices ?? this.choices),
    completedTaskIds: Set.unmodifiable(
      completedTaskIds ?? this.completedTaskIds,
    ),
    notes: notes ?? this.notes,
    revision: revision ?? this.revision,
  );

  EventPlan choose(String category, PlanChoice choice) {
    final next = copyWith(choices: {...choices, category: choice});
    next.validate();
    return next;
  }

  EventPlan remove(String category) {
    final next = Map<String, PlanChoice>.of(choices)..remove(category);
    return copyWith(choices: next);
  }

  Map<String, dynamic> toMap() {
    validate();
    return {
      'schemaVersion': 1,
      'revision': revision,
      'totalBudgetKzt': totalBudgetKzt,
      'choices': {
        for (final entry in choices.entries) entry.key: entry.value.toMap(),
      },
      'completedTaskIds': completedTaskIds.toList()..sort(),
      'notes': notes,
    };
  }

  factory EventPlan.fromMap(String eventId, Map<String, dynamic> map) {
    if (map['schemaVersion'] != 1) {
      throw const FormatException('Unsupported event plan schema');
    }
    final plan = EventPlan(
      eventId: eventId,
      totalBudgetKzt: map['totalBudgetKzt'] as int?,
      choices: Map.unmodifiable({
        for (final entry in (map['choices'] as Map).entries)
          entry.key as String: PlanChoice.fromMap(
            Map<String, dynamic>.from(entry.value as Map),
          ),
      }),
      completedTaskIds: Set.unmodifiable(
        Set<String>.from(map['completedTaskIds'] as List),
      ),
      notes: map['notes'] as String,
      revision: map['revision'] as int,
    );
    plan.validate();
    return plan;
  }
}
