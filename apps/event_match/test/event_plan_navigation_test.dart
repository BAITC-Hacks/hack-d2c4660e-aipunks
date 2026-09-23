import 'package:event_match/app/app.dart';
import 'package:event_match/features/auth/presentation/session_controller.dart';
import 'package:event_match/features/matching/domain/models.dart';
import 'package:event_match/features/planning/domain/event_plan.dart';
import 'package:event_match/features/planning/domain/event_plan_repository.dart';
import 'package:event_match/features/workspace/domain/workspace_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'auth_session_test.dart' show FakeAuthGateway, SessionRepository, alice;

class _Workspace extends SessionRepository {
  @override
  Future<List<ClientEvent>> listEvents(String uid) async => [
    for (final id in ['first', 'second'])
      ClientEvent(
        id: id,
        name: id == 'first' ? 'Первое событие' : 'Второе событие',
        city: 'Алматы',
        date: eventToday().add(const Duration(days: 30)),
        format: 'корпоратив',
      ),
  ];

  @override
  Future<List<SavedSelection>> listSelections(String uid) async => [];

  @override
  Future<List<PublishedProfile>> listPublished() async => [];
}

class _Plans implements EventPlanRepository {
  final requests = <String>[];

  @override
  Future<EventPlan> getPlan(String uid, String eventId) async {
    requests.add('$uid/$eventId');
    return EventPlan(eventId: eventId);
  }

  @override
  Future<EventPlan> savePlan(String uid, EventPlan plan) async =>
      plan.copyWith(revision: plan.revision + 1);
}

void main() {
  testWidgets('planner deep link keeps event selection through sign in', (
    tester,
  ) async {
    final auth = FakeAuthGateway();
    final workspace = _Workspace();
    final plans = _Plans();
    final session = SessionController(auth: auth, repository: workspace);
    addTearDown(session.dispose);
    await tester.pumpWidget(
      EventMatchApp(
        session: session,
        workspace: workspace,
        plans: plans,
        initialLocation: '/client/planner?event=second',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('С возвращением'), findsOneWidget);
    expect(plans.requests, isEmpty);

    auth.emit(alice);
    await tester.pumpAndSettle();
    expect(find.text('План мероприятия'), findsOneWidget);
    expect(plans.requests, ['alice/second']);
    expect(find.text('Второе событие'), findsWidgets);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
    await auth.changes.close();
    await workspace.accountChanges.close();
    await workspace.roleChanges.close();
  });
}
