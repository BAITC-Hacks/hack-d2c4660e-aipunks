// Opt-in real FlutterFire test. Run against the isolated local fixtures:
// flutter test --platform chrome test/communication_emulator_test.dart \
//   --dart-define=COMMUNICATION_EMULATOR_TEST=true
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:event_match/features/communication/data/firestore_communication_repository.dart';
import 'package:event_match/features/communication/domain/communication_models.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/communication_plugins_stub.dart'
    if (dart.library.js_interop) 'support/communication_plugins_web.dart';

const _enabled = bool.fromEnvironment('COMMUNICATION_EMULATOR_TEST');
const _projectId = 'demo-communication-smoke';

class _Actor {
  _Actor(this.app, this.auth, this.db)
    : repository = FirestoreCommunicationRepository(db: db);

  final FirebaseApp app;
  final FirebaseAuth auth;
  final FirebaseFirestore db;
  final FirestoreCommunicationRepository repository;

  static Future<_Actor> signIn(String uid) async {
    debugPrint('Communication smoke: initialize $uid');
    final app = await Firebase.initializeApp(
      name: 'communication-smoke-$uid',
      options: const FirebaseOptions(
        apiKey: 'local-emulator-only',
        appId: '1:123456789:web:communication-smoke',
        messagingSenderId: '123456789',
        projectId: _projectId,
        authDomain: 'demo-communication-smoke.firebaseapp.com',
      ),
    ).timeout(const Duration(seconds: 30));
    final auth = FirebaseAuth.instanceFor(app: app);
    await auth.useAuthEmulator('127.0.0.1', 9299);
    final db = FirebaseFirestore.instanceFor(app: app);
    db.settings = const Settings(
      host: '127.0.0.1:8280',
      sslEnabled: false,
      persistenceEnabled: false,
    );
    debugPrint('Communication smoke: sign in $uid');
    final credential = await auth
        .signInWithEmailAndPassword(
          email: '$uid@communication.example.com',
          password: 'CommunicationSmoke2026!',
        )
        .timeout(const Duration(seconds: 30));
    expect(credential.user!.uid, uid);
    expect(credential.user!.emailVerified, isTrue);
    return _Actor(app, auth, db);
  }

  Future<Conversation> conversation(
    String id, {
    bool Function(Conversation)? matches,
  }) async => (await repository
      .watchConversation(id)
      .firstWhere((value) => value != null && (matches?.call(value) ?? true))
      .timeout(const Duration(seconds: 15)))!;

  Future<void> dispose() async {
    await db.terminate();
    await auth.signOut();
    await app.delete();
  }
}

Matcher get _denied => isA<FirebaseException>().having(
  (error) => error.code,
  'code',
  'permission-denied',
);

Future<void> _expectDeniedWithoutData<T>(Stream<T> stream) async {
  final received = <T>[];
  final denial = Completer<Object>();
  final subscription = stream.listen(
    received.add,
    onError: (Object error) {
      if (!denial.isCompleted) denial.complete(error);
    },
  );
  try {
    expect(await denial.future.timeout(const Duration(seconds: 15)), _denied);
    expect(
      received,
      isEmpty,
      reason: 'Revoked access must not expose even the first cached snapshot.',
    );
  } finally {
    await subscription.cancel();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  if (_enabled) registerCommunicationPlugins();

  test(
    'real Dart repository delivers inquiry, preserves context, and scopes support',
    () async {
      expect(
        kIsWeb,
        isTrue,
        reason: 'Run this opt-in smoke with --platform chrome.',
      );
      final actors = <_Actor>[];
      addTearDown(() async {
        for (final actor in actors.reversed) {
          await actor.dispose();
        }
      });
      Future<_Actor> login(String uid) async {
        final actor = await _Actor.signIn(uid);
        actors.add(actor);
        return actor;
      }

      final client = await login('client');
      final vendor = await login('vendor');
      final admin = await login('admin');
      final other = await login('other');
      final inquiryId = client.repository.newId();
      debugPrint('Communication smoke: create inquiry');

      Future<void> create() => client.repository.createInquiry(
        id: inquiryId,
        uid: 'client',
        contractorId: 'vendor',
        eventId: 'wedding',
        category: 'Ведущий',
        text: '  Здравствуйте! Свободна ли дата?  ',
      );
      await create();
      await create(); // Same action id must not duplicate the opening message.
      final opened = await vendor.conversation(inquiryId);
      expect(opened.messageCount, 1);
      expect(opened.status, 'sent');
      expect(opened.eventSnapshot['date'], '2026-11-14');
      expect(opened.contractorId, 'vendor');
      expect(opened.createdAt, isNotNull);
      final initial = await vendor.repository.watchMessages(inquiryId).first;
      expect(initial, hasLength(1));
      expect(initial.single.text, 'Здравствуйте! Свободна ли дата?');
      expect(initial.single.createdAt, isNotNull);

      final inbox = await vendor.repository.watchInbox('vendor').first;
      expect(inbox.map((item) => item.id), contains(inquiryId));
      await expectLater(
        other.db
            .doc('conversations/$inquiryId')
            .get(const GetOptions(source: Source.server)),
        throwsA(_denied),
      );
      await expectLater(
        admin.db
            .doc('conversations/$inquiryId')
            .get(const GetOptions(source: Source.server)),
        throwsA(_denied),
      );

      final replyId = vendor.repository.newId();
      debugPrint('Communication smoke: reply and mark read');
      Future<void> reply() => vendor.repository.sendMessage(
        conversationId: inquiryId,
        messageId: replyId,
        uid: 'vendor',
        text: 'Да, давайте обсудим программу.',
      );
      await reply();
      await reply(); // Retrying a successful message must retain sequence 2.
      var current = await client.conversation(
        inquiryId,
        matches: (value) => value.messageCount == 2,
      );
      expect(current.messageCount, 2);
      final messages = await client.repository.watchMessages(inquiryId).first;
      expect(messages.map((message) => message.sequence), [1, 2]);
      expect(messages.last.senderId, 'vendor');
      await client.repository.markRead(inquiryId, 'client', 2);
      expect(
        await client.repository.watchReadSequence(inquiryId, 'client').first,
        2,
      );

      await vendor.repository.changeStatus(
        conversationId: inquiryId,
        uid: 'vendor',
        status: 'discussing',
        expectedRevision: current.revision,
      );
      current = await client.conversation(
        inquiryId,
        matches: (value) => value.status == 'discussing',
      );
      expect(current.status, 'discussing');
      final savedName = current.eventSnapshot['name'];
      await client.db.doc('accounts/client/events/wedding').update({
        'name': 'Изменённое мероприятие после отправки заявки',
        'updatedAt': FieldValue.serverTimestamp(),
      });
      expect(
        (await client.conversation(inquiryId)).eventSnapshot['name'],
        savedName,
      );

      final ticketId = client.repository.newId();
      debugPrint('Communication smoke: create support and grant context');
      await client.repository.createSupport(
        id: ticketId,
        uid: 'client',
        subject: 'Помогите уточнить условия',
        text: 'Нужна помощь по этой заявке.',
        linkedInquiryId: inquiryId,
      );
      final ticket = await admin.conversation(ticketId);
      expect(ticket.status, 'open');
      final supportInbox = await admin.repository
          .watchInbox('admin', supportQueue: true)
          .first;
      expect(supportInbox.map((item) => item.id), contains(ticketId));
      await admin.repository.changeStatus(
        conversationId: ticketId,
        uid: 'admin',
        status: 'in_progress',
        expectedRevision: ticket.revision,
      );
      expect((await admin.conversation(inquiryId)).id, inquiryId);
      expect(
        await admin.repository.watchMessages(inquiryId).first,
        hasLength(2),
      );
      final adminReplyId = admin.repository.newId();
      await admin.repository.sendMessage(
        conversationId: ticketId,
        messageId: adminReplyId,
        uid: 'admin',
        text: 'Уточните, пожалуйста, вопрос.',
      );
      final supportMessages = await client.repository
          .watchMessages(ticketId)
          .firstWhere((messages) => messages.length == 2);
      expect(supportMessages.last.senderId, 'admin');
      expect(supportMessages.last.text, 'Уточните, пожалуйста, вопрос.');

      final activeTicket = await admin.conversation(
        ticketId,
        matches: (value) =>
            value.messageCount == 2 && value.status == 'in_progress',
      );
      debugPrint('Communication smoke: resolve and verify revoked context');
      await admin.repository.changeStatus(
        conversationId: ticketId,
        uid: 'admin',
        status: 'resolved',
        expectedRevision: activeTicket.revision,
      );
      expect(
        (await client.conversation(
          ticketId,
          matches: (value) => value.status == 'resolved',
        )).status,
        'resolved',
      );
      final audit = await admin.repository
          .watchAudit(ticketId)
          .firstWhere((entries) => entries.length == 3);
      expect(
        audit.map((entry) => entry.action),
        containsAll(['opened', 'claimed', 'resolved']),
      );
      await expectLater(
        admin.db
            .doc('conversations/$inquiryId')
            .get(const GetOptions(source: Source.server)),
        throwsA(_denied),
      );
      debugPrint(
        'Communication smoke: revoked support streams expose no cache',
      );
      await _expectDeniedWithoutData(
        admin.repository.watchConversation(inquiryId),
      );
      await _expectDeniedWithoutData(admin.repository.watchMessages(inquiryId));
      await expectLater(
        client.repository.sendMessage(
          conversationId: ticketId,
          messageId: client.repository.newId(),
          uid: 'client',
          text: 'Сообщение после закрытия',
        ),
        throwsA(anything),
      );
      current = await client.conversation(
        inquiryId,
        matches: (value) => value.contextTicketId == ticketId,
      );
      await client.repository.changeStatus(
        conversationId: inquiryId,
        uid: 'client',
        status: 'closed',
        expectedRevision: current.revision,
      );
      expect(
        (await vendor.conversation(
          inquiryId,
          matches: (value) => value.status == 'closed',
        )).status,
        'closed',
      );

      debugPrint('Communication smoke: same Firestore instance account switch');
      // Preserve this app/Firestore instance and its in-memory cache. Separate
      // named apps above intentionally cannot exercise account-switch leakage.
      expect(
        await client.repository.watchMessages(inquiryId).first,
        hasLength(2),
      );
      await client.auth.signOut();
      final switched = await client.auth.signInWithEmailAndPassword(
        email: 'other@communication.example.com',
        password: 'CommunicationSmoke2026!',
      );
      expect(switched.user!.uid, 'other');
      await _expectDeniedWithoutData(
        client.repository.watchConversation(inquiryId),
      );
      await _expectDeniedWithoutData(
        client.repository.watchMessages(inquiryId),
      );
    },
    skip: !_enabled,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
