import 'event_plan.dart';

abstract class EventPlanRepository {
  /// Returns an empty plan with revision zero when none has been saved yet.
  Future<EventPlan> getPlan(String uid, String eventId);

  /// Saves only when [plan]'s revision is still current, returning the next one.
  Future<EventPlan> savePlan(String uid, EventPlan plan);
}

/// The caller must reload before applying changes to a newer saved plan.
class EventPlanConflict implements Exception {
  const EventPlanConflict({
    required this.expectedRevision,
    required this.actualRevision,
  });

  final int expectedRevision;
  final int actualRevision;

  @override
  String toString() =>
      'План изменился в другом окне. Обновите его перед сохранением.';
}
