import 'package:event_match/features/planning/domain/event_plan.dart';
import 'package:event_match/features/planning/domain/event_plan_draft_store.dart';
import 'package:event_match/features/workspace/domain/workspace_models.dart';
import 'package:flutter_test/flutter_test.dart';

ClientEvent event({
  String id = 'event-1',
  String city = 'Алматы',
  DateTime? date,
  String format = 'свадьба',
  String preferences = '',
}) => ClientEvent(
  id: id,
  name: 'Наш праздник',
  city: city,
  date: date ?? DateTime(2026, 11, 14),
  format: format,
  preferences: preferences,
);

EventPlanDraft draft({String eventId = 'event-1', String notes = 'Заметки'}) =>
    EventPlanDraft(
      event: event(id: eventId),
      plan: EventPlan(eventId: eventId, revision: 3),
      budgetText: '0',
      notesText: notes,
    );

void main() {
  test('drafts and navigation selection are isolated by account and event', () {
    final store = EventPlanDraftStore();
    final first = draft();
    final second = draft(eventId: 'event-2');
    store.write('one', first);
    store.write('one', second);
    store.write('two', draft(notes: 'Другой клиент'));
    expect(store.read('one', 'event-1'), same(first));
    expect(store.read('one', 'event-2'), same(second));
    expect(store.read('two', 'event-1')!.notesText, 'Другой клиент');
    expect(store.read('two', 'event-2'), isNull);
    expect(store.selectedEvent('one'), 'event-2');
    expect(store.selectedEvent('two'), 'event-1');
    store.clear();
    expect(store.read('one', 'event-1'), isNull);
    expect(store.read('two', 'event-1'), isNull);
    expect(store.selectedEvent('one'), isNull);
    expect(store.selectedEvent('two'), isNull);
  });

  test('restoration requires same event facts and base remote revision', () {
    final local = draft();
    const remote = EventPlan(eventId: 'event-1', revision: 3);
    expect(local.matches(event(), remote), isTrue);
    expect(
      local.matches(event(preferences: 'Другие пожелания'), remote),
      isTrue,
    );
    for (final changed in [
      event(id: 'other'),
      event(city: 'Астана'),
      event(date: DateTime(2026, 11, 15)),
      event(format: 'корпоратив'),
    ]) {
      expect(local.matches(changed, remote), isFalse);
    }
    expect(local.matches(event(), remote.copyWith(revision: 4)), isFalse);
    expect(
      local.matches(event(), const EventPlan(eventId: 'other', revision: 3)),
      isFalse,
    );
  });

  test('late save removes only the draft that was submitted', () {
    final store = EventPlanDraftStore();
    final submitted = draft();
    final newer = draft(notes: 'Новые правки');
    store.write('one', submitted);
    store.write('one', newer);
    store.remove('one', 'event-1', ifUnchanged: submitted);
    expect(store.read('one', 'event-1'), same(newer));
    store.remove('one', 'event-1', ifUnchanged: newer);
    expect(store.read('one', 'event-1'), isNull);
  });
}
