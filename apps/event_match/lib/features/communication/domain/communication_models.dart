import '../../workspace/domain/workspace_models.dart';

enum CommunicationMode { client, contractor, support, admin }

class Conversation {
  const Conversation({
    required this.id,
    required this.kind,
    required this.participantIds,
    required this.clientId,
    required this.contractorId,
    required this.clientName,
    required this.contractorName,
    required this.eventId,
    required this.eventSnapshot,
    required this.subject,
    required this.status,
    required this.linkedInquiryId,
    required this.assignedAdminId,
    required this.contextTicketId,
    required this.lastMessageId,
    required this.lastSenderId,
    required this.messageCount,
    required this.revision,
    this.createdAt,
    this.updatedAt,
    this.lastMessageAt,
  });

  final String id, kind, clientId, contractorId, clientName, contractorName;
  final String eventId, subject, status, linkedInquiryId, assignedAdminId;
  final String contextTicketId, lastMessageId, lastSenderId;
  final List<String> participantIds;
  final Map<String, dynamic> eventSnapshot;
  final int messageCount, revision;
  final DateTime? createdAt, updatedAt, lastMessageAt;

  bool get isSupport => kind == 'support';
  bool get isTerminal =>
      ['declined', 'cancelled', 'closed', 'resolved'].contains(status);
  String get statusLabel => switch (status) {
    'sent' => 'Отправлена',
    'discussing' => 'Обсуждение',
    'declined' => 'Отклонена',
    'cancelled' => 'Отменена',
    'closed' => 'Закрыта',
    'open' => 'Ожидает поддержки',
    'in_progress' => 'В работе',
    'resolved' => 'Обращение закрыто',
    _ => status,
  };
  bool canSend(String uid, {bool isAdmin = false}) =>
      !isTerminal &&
      (isSupport
          ? uid == clientId || (isAdmin && uid == assignedAdminId)
          : participantIds.contains(uid));

  List<String> transitionsFor(String uid, {bool isAdmin = false}) {
    if (isSupport) {
      return [
        if (status == 'open' && isAdmin && uid != clientId) 'in_progress',
        if (!isTerminal &&
            (uid == clientId || (isAdmin && assignedAdminId == uid)))
          'resolved',
      ];
    }
    return [
      if (status == 'sent' && uid == contractorId) 'discussing',
      if (['sent', 'discussing'].contains(status) && uid == contractorId)
        'declined',
      if (['sent', 'discussing'].contains(status) && uid == clientId)
        'cancelled',
      if (status == 'discussing' && participantIds.contains(uid)) 'closed',
    ];
  }

  factory Conversation.fromMap(String id, Map<String, dynamic> m) =>
      Conversation(
        id: id,
        kind: m['kind'] as String,
        participantIds: List<String>.from(m['participantIds'] as List),
        clientId: m['clientId'] as String,
        contractorId: m['contractorId'] as String,
        clientName: m['clientName'] as String,
        contractorName: m['contractorName'] as String,
        eventId: m['eventId'] as String,
        eventSnapshot: Map<String, dynamic>.from(m['eventSnapshot'] as Map),
        subject: m['subject'] as String,
        status: m['status'] as String,
        linkedInquiryId: m['linkedInquiryId'] as String,
        assignedAdminId: m['assignedAdminId'] as String,
        contextTicketId: m['contextTicketId'] as String,
        lastMessageId: m['lastMessageId'] as String,
        lastSenderId: m['lastSenderId'] as String,
        messageCount: m['messageCount'] as int,
        revision: m['revision'] as int,
        createdAt: m['createdAt'] as DateTime?,
        updatedAt: m['updatedAt'] as DateTime?,
        lastMessageAt: m['lastMessageAt'] as DateTime?,
      );
}

class ConversationMessage {
  const ConversationMessage({
    required this.id,
    required this.senderId,
    required this.text,
    required this.sequence,
    this.createdAt,
  });
  final String id, senderId, text;
  final int sequence;
  final DateTime? createdAt;
  factory ConversationMessage.fromMap(String id, Map<String, dynamic> m) =>
      ConversationMessage(
        id: id,
        senderId: m['senderId'] as String,
        text: m['text'] as String,
        sequence: m['sequence'] as int,
        createdAt: m['createdAt'] as DateTime?,
      );
}

class CommunicationAudit {
  const CommunicationAudit({
    required this.actorId,
    required this.action,
    required this.revision,
    this.createdAt,
  });
  final String actorId, action;
  final int revision;
  final DateTime? createdAt;
}

void validateMessage(String text) {
  if (text.trim().isEmpty || text.trim().length > 4000) {
    throw ArgumentError('Сообщение должно содержать от 1 до 4000 символов');
  }
}

Map<String, dynamic> eventContext(ClientEvent event) => event.toMap();
