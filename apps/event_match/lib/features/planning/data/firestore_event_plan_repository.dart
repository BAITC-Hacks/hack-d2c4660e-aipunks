import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/event_plan.dart';
import '../domain/event_plan_repository.dart';

class FirestoreEventPlanRepository implements EventPlanRepository {
  FirestoreEventPlanRepository([FirebaseFirestore? db])
    : db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore db;

  DocumentReference<Map<String, dynamic>> _account(String uid) {
    _validateDocumentId(uid);
    return db.collection('accounts').doc(uid);
  }

  DocumentReference<Map<String, dynamic>> _plan(String uid, String eventId) {
    _validateDocumentId(eventId);
    return _account(uid).collection('eventPlans').doc(eventId);
  }

  void _validateDocumentId(String value) {
    if (value.isEmpty || value.length > 160 || value.contains('/')) {
      throw ArgumentError('Некорректный идентификатор документа');
    }
  }

  @override
  Future<EventPlan> getPlan(String uid, String eventId) async {
    final snapshot = await _plan(
      uid,
      eventId,
    ).get(const GetOptions(source: Source.server));
    final data = snapshot.data();
    return data == null
        ? EventPlan(eventId: eventId)
        : EventPlan.fromMap(eventId, data);
  }

  @override
  Future<EventPlan> savePlan(String uid, EventPlan plan) async {
    plan.validate();
    final planRef = _plan(uid, plan.eventId);
    final eventRef = _account(uid).collection('events').doc(plan.eventId);
    return db.runTransaction<EventPlan>((transaction) async {
      final event = await transaction.get(eventRef);
      if (!event.exists) {
        throw StateError(
          'Мероприятие удалено. Создайте новое перед сохранением.',
        );
      }
      final snapshot = await transaction.get(planRef);
      final current = snapshot.data();
      final actualRevision = current == null
          ? 0
          : EventPlan.fromMap(plan.eventId, current).revision;
      if (actualRevision != plan.revision) {
        throw EventPlanConflict(
          expectedRevision: plan.revision,
          actualRevision: actualRevision,
        );
      }
      final saved = plan.copyWith(revision: actualRevision + 1);
      transaction.set(planRef, {
        ...saved.toMap(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return saved;
    });
  }
}
