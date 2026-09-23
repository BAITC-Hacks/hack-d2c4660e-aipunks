import 'package:event_match/app/app.dart';
import 'package:event_match/features/auth/presentation/session_controller.dart';
import 'package:event_match/features/workspace/domain/workspace_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'auth_session_test.dart' show FakeAuthGateway, SessionRepository, alice;
import 'communication_widget_test.dart'
    show CommunicationFake, CommunicationWorkspaceFake, conversation;

class _Workspace extends SessionRepository {
  final data = CommunicationWorkspaceFake();
  @override
  Future<List<ClientEvent>> listEvents(String uid) => data.listEvents(uid);
  @override
  Future<List<PublishedProfile>> listPublished() => data.listPublished();
}

void main() {
  testWidgets('inquiry recipient and event survive the sign-in route', (
    tester,
  ) async {
    final auth = FakeAuthGateway();
    final workspace = _Workspace();
    final communications = CommunicationFake();
    final session = SessionController(auth: auth, repository: workspace);
    addTearDown(session.dispose);
    addTearDown(communications.dispose);
    await tester.pumpWidget(
      EventMatchApp(
        session: session,
        workspace: workspace,
        communications: communications,
        initialLocation:
            '/client/messages?contractor=provider&event=real-event',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('С возвращением'), findsOneWidget);
    expect(workspace.data.eventOwner, isNull);
    auth.emit(alice);
    await tester.pumpAndSettle();
    expect(find.text('Новая заявка'), findsOneWidget);
    expect(find.text('Получатель: Студия света'), findsOneWidget);
    expect(workspace.data.eventOwner, 'alice');
    expect(find.text('Свадьба в саду'), findsWidgets);
    await tester.ensureVisible(find.text('К списку'));
    await tester.tap(find.text('К списку'));
    await tester.pumpAndSettle();
    expect(find.text('Пока нет сообщений'), findsOneWidget);
    expect(communications.conversationRequests, isNot(contains('')));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await auth.changes.close();
    await workspace.accountChanges.close();
    await workspace.roleChanges.close();
  });

  testWidgets('moderator cannot enter administrator support queue', (
    tester,
  ) async {
    final auth = FakeAuthGateway()..identity = alice;
    final workspace = _Workspace()
      ..roles['alice'] = const StaffAccess(role: 'moderator', revision: 1);
    final communications = CommunicationFake()
      ..conversations['ticket'] = conversation(kind: 'support', id: 'ticket');
    final session = SessionController(auth: auth, repository: workspace);
    addTearDown(session.dispose);
    addTearDown(communications.dispose);
    await tester.pumpWidget(
      EventMatchApp(
        session: session,
        workspace: workspace,
        communications: communications,
        initialLocation: '/admin/support',
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Очередь поддержки доступна администратору.'),
      findsOneWidget,
    );
    expect(communications.inboxRequests, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await auth.changes.close();
    await workspace.accountChanges.close();
    await workspace.roleChanges.close();
  });
}
