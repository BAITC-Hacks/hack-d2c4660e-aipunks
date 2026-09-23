import '../../matching/domain/models.dart' show dateKey;
import '../../workspace/domain/workspace_models.dart';
import 'event_plan.dart';

/// A session-only draft. Raw field values also survive validation errors.
class EventPlanDraft {
  EventPlanDraft({
    required ClientEvent event,
    required EventPlan plan,
    required this.budgetText,
    required this.notesText,
  }) : eventId = event.id,
       city = event.city,
       date = dateKey(event.date),
       format = event.format,
       plan = plan.copyWith() {
    if (event.id != plan.eventId) {
      throw ArgumentError('Черновик относится к другому мероприятию');
    }
  }

  final String eventId, city, date, format, budgetText, notesText;
  final EventPlan plan;

  /// Wishes can differ per contractor category; only event facts invalidate it.
  bool matches(ClientEvent event, EventPlan remote) =>
      eventId == event.id &&
      eventId == remote.eventId &&
      city == event.city &&
      date == dateKey(event.date) &&
      format == event.format &&
      plan.revision == remote.revision;
}

/// Owned by the app session and cleared when the authenticated user changes.
/// It does not persist personal notes to disk or upload unsaved edits.
class EventPlanDraftStore {
  final _drafts = <(String, String), EventPlanDraft>{};
  final _selectedEvents = <String, String>{};

  EventPlanDraft? read(String uid, String eventId) => _drafts[(uid, eventId)];

  void write(String uid, EventPlanDraft draft) {
    _drafts[(uid, draft.eventId)] = draft;
    selectEvent(uid, draft.eventId);
  }

  void selectEvent(String uid, String eventId) =>
      _selectedEvents[uid] = eventId;

  String? selectedEvent(String uid) => _selectedEvents[uid];

  /// A late successful save must not erase a newer draft in another page.
  void remove(String uid, String eventId, {EventPlanDraft? ifUnchanged}) {
    final key = (uid, eventId);
    if (ifUnchanged == null || identical(_drafts[key], ifUnchanged)) {
      _drafts.remove(key);
    }
  }

  void clear() {
    _drafts.clear();
    _selectedEvents.clear();
  }
}
