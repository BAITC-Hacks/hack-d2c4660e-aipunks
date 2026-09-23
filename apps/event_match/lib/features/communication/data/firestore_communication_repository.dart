import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../workspace/domain/workspace_models.dart';
import '../domain/communication_models.dart';
import '../domain/communication_repository.dart';

/// All writes await online transactions and remain subject to Firestore Rules.
/// A stable operation id makes retrying an uncertain response safe.
class FirestoreCommunicationRepository extends CommunicationRepository {
  FirestoreCommunicationRepository({FirebaseFirestore? db})
    : db = db ?? FirebaseFirestore.instance;
  final FirebaseFirestore db;

  DocumentReference<Map<String, dynamic>> _conversation(String id) =>
      db.collection('conversations').doc(id);
  DocumentReference<Map<String, dynamic>> _message(String id, String message) =>
      _conversation(id).collection('messages').doc(message);
  dynamic _normalize(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is Map) {
      return value.map((k, v) => MapEntry(k.toString(), _normalize(v)));
    }
    if (value is List) return value.map(_normalize).toList();
    return value;
  }

  Map<String, dynamic> _map(Map<String, dynamic> value) =>
      _normalize(value) as Map<String, dynamic>;

  /// Memory cache is shared across identities even with persistence disabled.
  /// Every private subscription waits for fresh server authorization. Timeout
  /// covers only initial connection, never a healthy but idle conversation.
  Stream<T> _confirmed<S, T>(
    Stream<S> source,
    SnapshotMetadata Function(S) metadata,
    T Function(S) parse,
  ) => Stream<T>.multi((sink) {
    final timer = Timer(const Duration(seconds: 20), () {
      sink.addError(
        TimeoutException('Не удалось подтвердить доступ к переписке'),
      );
    });
    final subscription = source.listen(
      (snapshot) {
        final state = metadata(snapshot);
        if (state.isFromCache || state.hasPendingWrites) return;
        timer.cancel();
        try {
          sink.add(parse(snapshot));
        } catch (error, stack) {
          sink.addError(error, stack);
        }
      },
      onError: (Object error, StackTrace stack) {
        timer.cancel();
        sink.addError(error, stack);
      },
      onDone: () {
        timer.cancel();
        sink.close();
      },
    );
    sink.onCancel = () async {
      timer.cancel();
      await subscription.cancel();
    };
  });

  @override
  String newId() => db.collection('conversations').doc().id;

  @override
  Stream<List<Conversation>> watchInbox(
    String uid, {
    bool supportQueue = false,
    int limit = 50,
  }) {
    final query = supportQueue
        ? db.collection('conversations').where('kind', isEqualTo: 'support')
        : db
              .collection('conversations')
              .where('participantIds', arrayContains: uid);
    return _confirmed(
      query
          .orderBy('updatedAt', descending: true)
          .limit(limit)
          .snapshots(includeMetadataChanges: true),
      (snapshot) => snapshot.metadata,
      (snapshot) => snapshot.docs
          .map((d) => Conversation.fromMap(d.id, _map(d.data())))
          .toList(),
    );
  }

  @override
  Stream<Conversation?> watchConversation(String id) => _confirmed(
    _conversation(id).snapshots(includeMetadataChanges: true),
    (snapshot) => snapshot.metadata,
    (d) => d.exists ? Conversation.fromMap(d.id, _map(d.data()!)) : null,
  );

  @override
  Stream<List<ConversationMessage>> watchMessages(
    String id, {
    int limit = 50,
  }) => _confirmed(
    _conversation(id)
        .collection('messages')
        .orderBy('sequence', descending: true)
        .limit(limit)
        .snapshots(includeMetadataChanges: true),
    (snapshot) => snapshot.metadata,
    (s) => s.docs.reversed
        .map((d) => ConversationMessage.fromMap(d.id, _map(d.data())))
        .toList(),
  );

  @override
  Stream<int> watchReadSequence(String id, String uid) => _confirmed(
    _conversation(
      id,
    ).collection('readStates').doc(uid).snapshots(includeMetadataChanges: true),
    (snapshot) => snapshot.metadata,
    (d) => d.data()?['lastReadSequence'] as int? ?? 0,
  );

  @override
  Stream<List<CommunicationAudit>> watchAudit(String id) => _confirmed(
    db
        .collection('communicationAudit')
        .where('conversationId', isEqualTo: id)
        .snapshots(includeMetadataChanges: true),
    (snapshot) => snapshot.metadata,
    (snapshot) {
      final entries = snapshot.docs.map((d) {
        final m = _map(d.data());
        return CommunicationAudit(
          actorId: m['actorId'] as String,
          action: m['action'] as String,
          revision: m['revision'] as int,
          createdAt: m['createdAt'] as DateTime?,
        );
      }).toList();
      entries.sort((a, b) => a.revision.compareTo(b.revision));
      return entries;
    },
  );

  Map<String, dynamic> _initial({
    required String uid,
    required String name,
    required String subject,
    required bool support,
    String contractorId = '',
    String contractorName = '',
    String eventId = '',
    Map<String, dynamic> eventSnapshot = const {},
    String linkedInquiryId = '',
  }) => {
    'kind': support ? 'support' : 'inquiry',
    'participantIds': support ? [uid] : [uid, contractorId],
    'clientId': uid,
    'contractorId': contractorId,
    'clientName': name,
    'contractorName': contractorName,
    'eventId': eventId,
    'eventSnapshot': eventSnapshot,
    'subject': subject,
    'status': support ? 'open' : 'sent',
    'linkedInquiryId': linkedInquiryId,
    'assignedAdminId': '',
    'contextTicketId': '',
    'createdAt': FieldValue.serverTimestamp(),
    'updatedAt': FieldValue.serverTimestamp(),
    'lastMessageAt': FieldValue.serverTimestamp(),
    'lastMessageId': 'first',
    'lastSenderId': uid,
    'messageCount': 1,
    'revision': 1,
  };

  Map<String, dynamic> _messageData(String uid, String text, int sequence) => {
    'senderId': uid,
    'text': text.trim(),
    'createdAt': FieldValue.serverTimestamp(),
    'sequence': sequence,
  };

  void _audit(
    Transaction tx,
    String id,
    String uid,
    int revision,
    String action,
  ) {
    tx.set(db.doc('communicationAudit/${id}_$revision'), {
      'conversationId': id,
      'actorId': uid,
      'action': action,
      'revision': revision,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _verifyRetry(
    Transaction tx,
    String id,
    String uid,
    String text,
  ) async {
    final message = (await tx.get(_message(id, 'first'))).data();
    if (message == null ||
        message['senderId'] != uid ||
        message['text'] != text.trim()) {
      throw StateError(
        'Эта заявка уже отправлена с другим текстом. Откройте переписку.',
      );
    }
  }

  @override
  Future<void> createInquiry({
    required String id,
    required String uid,
    required String contractorId,
    required String eventId,
    required String category,
    required String text,
  }) async {
    validateMessage(text);
    if (uid == contractorId || contractorId.isEmpty || eventId.isEmpty) {
      throw ArgumentError('Выберите мероприятие и другого подрядчика');
    }
    await db.runTransaction((tx) async {
      final ref = _conversation(id);
      final existing = (await tx.get(ref)).data();
      if (existing != null) {
        if (existing['kind'] != 'inquiry' ||
            existing['clientId'] != uid ||
            existing['contractorId'] != contractorId ||
            existing['eventId'] != eventId ||
            existing['subject'] != category) {
          throw StateError('Заявка уже существует с другими условиями');
        }
        await _verifyRetry(tx, id, uid, text);
        return;
      }
      final account = (await tx.get(db.doc('accounts/$uid'))).data();
      final event = (await tx.get(
        db.doc('accounts/$uid/events/$eventId'),
      )).data();
      final publication = (await tx.get(
        db.doc('publishedProfiles/$contractorId'),
      )).data();
      if (account == null ||
          event == null ||
          publication == null ||
          publication['published'] != true ||
          publication['ownerId'] != contractorId) {
        throw StateError('Мероприятие или опубликованный подрядчик недоступны');
      }
      final profile = ProfileContent.fromMap(
        Map<String, dynamic>.from(publication['content'] as Map),
      );
      if (!profile.categories.contains(category)) {
        throw ArgumentError('Услуга больше не доступна у этого подрядчика');
      }
      tx.set(
        ref,
        _initial(
          uid: uid,
          name: account['name'] as String,
          subject: category,
          support: false,
          contractorId: contractorId,
          contractorName: profile.name,
          eventId: eventId,
          eventSnapshot: eventContext(ClientEvent.fromMap(eventId, event)),
        ),
      );
      tx.set(_message(id, 'first'), _messageData(uid, text, 1));
    });
  }

  @override
  Future<void> createSupport({
    required String id,
    required String uid,
    required String subject,
    required String text,
    String linkedInquiryId = '',
  }) async {
    validateMessage(text);
    if (subject.trim().isEmpty || subject.trim().length > 120) {
      throw ArgumentError('Укажите тему до 120 символов');
    }
    await db.runTransaction((tx) async {
      final ref = _conversation(id);
      final existing = (await tx.get(ref)).data();
      if (existing != null) {
        if (existing['kind'] != 'support' ||
            existing['clientId'] != uid ||
            existing['linkedInquiryId'] != linkedInquiryId ||
            existing['subject'] != subject.trim()) {
          throw StateError('Обращение уже существует с другими условиями');
        }
        await _verifyRetry(tx, id, uid, text);
        return;
      }
      final account = (await tx.get(db.doc('accounts/$uid'))).data();
      final inquiry = linkedInquiryId.isEmpty
          ? null
          : (await tx.get(_conversation(linkedInquiryId))).data();
      if (account == null) throw StateError('Аккаунт недоступен');
      if (linkedInquiryId.isNotEmpty &&
          (inquiry == null ||
              inquiry['kind'] != 'inquiry' ||
              !(inquiry['participantIds'] as List).contains(uid))) {
        throw StateError('Можно передать поддержке только свою переписку');
      }
      tx.set(
        ref,
        _initial(
          uid: uid,
          name: account['name'] as String,
          subject: subject.trim(),
          support: true,
          linkedInquiryId: linkedInquiryId,
        ),
      );
      tx.set(_message(id, 'first'), _messageData(uid, text, 1));
      _audit(tx, id, uid, 1, 'opened');
      if (inquiry != null) {
        tx.update(_conversation(linkedInquiryId), {
          'contextTicketId': id,
          'revision': (inquiry['revision'] as int) + 1,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    });
  }

  @override
  Future<void> sendMessage({
    required String conversationId,
    required String messageId,
    required String uid,
    required String text,
  }) async {
    validateMessage(text);
    await db.runTransaction((tx) async {
      final ref = _conversation(conversationId);
      final data = (await tx.get(ref)).data();
      final messageRef = _message(conversationId, messageId);
      final existing = (await tx.get(messageRef)).data();
      if (existing != null) {
        if (existing['senderId'] != uid || existing['text'] != text.trim()) {
          throw StateError('Сообщение уже отправлено с другим текстом');
        }
        return;
      }
      if (data == null) throw StateError('Переписка недоступна');
      final conversation = Conversation.fromMap(conversationId, _map(data));
      if (conversation.isTerminal) throw StateError('Переписка закрыта');
      final sequence = conversation.messageCount + 1;
      tx.set(messageRef, _messageData(uid, text, sequence));
      tx.update(ref, {
        'messageCount': sequence,
        'lastMessageId': messageId,
        'lastSenderId': uid,
        'lastMessageAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'revision': conversation.revision + 1,
      });
    });
  }

  @override
  Future<void> changeStatus({
    required String conversationId,
    required String uid,
    required String status,
    required int expectedRevision,
  }) => db.runTransaction((tx) async {
    final ref = _conversation(conversationId);
    final data = (await tx.get(ref)).data();
    if (data == null) throw StateError('Переписка недоступна');
    final conversation = Conversation.fromMap(conversationId, _map(data));
    if (conversation.status == status &&
        (status != 'in_progress' || conversation.assignedAdminId == uid)) {
      return;
    }
    if (conversation.revision != expectedRevision) {
      throw StateError(
        'Заявка изменилась. Обновите данные и повторите действие.',
      );
    }
    final staff = conversation.isSupport && uid != conversation.clientId
        ? (await tx.get(db.doc('staffAccess/$uid'))).data()
        : null;
    if (!conversation
        .transitionsFor(uid, isAdmin: staff?['role'] == 'admin')
        .contains(status)) {
      throw StateError('Этот переход статуса недоступен');
    }
    final revision = conversation.revision + 1;
    tx.update(ref, {
      'status': status,
      if (conversation.isSupport && status == 'in_progress')
        'assignedAdminId': uid,
      'revision': revision,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    if (conversation.isSupport) {
      _audit(
        tx,
        conversationId,
        uid,
        revision,
        status == 'in_progress' ? 'claimed' : 'resolved',
      );
    }
  });

  @override
  Future<void> markRead(String conversationId, String uid, int sequence) =>
      db.runTransaction((tx) async {
        final ref = _conversation(
          conversationId,
        ).collection('readStates').doc(uid);
        final receipt = (await tx.get(ref)).data();
        if ((receipt?['lastReadSequence'] as int? ?? 0) >= sequence) return;
        tx.set(ref, {
          'lastReadSequence': sequence,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });
}
