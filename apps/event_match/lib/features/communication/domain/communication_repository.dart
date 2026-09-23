import 'communication_models.dart';

abstract class CommunicationRepository {
  /// Keep the same id when retrying an uncertain write.
  String newId();
  Stream<List<Conversation>> watchInbox(
    String uid, {
    bool supportQueue = false,
    int limit = 50,
  });
  Stream<Conversation?> watchConversation(String id);
  Stream<List<ConversationMessage>> watchMessages(String id, {int limit = 50});
  Stream<int> watchReadSequence(String id, String uid);
  Stream<List<CommunicationAudit>> watchAudit(String id);
  Future<void> createInquiry({
    required String id,
    required String uid,
    required String contractorId,
    required String eventId,
    required String category,
    required String text,
  });
  Future<void> createSupport({
    required String id,
    required String uid,
    required String subject,
    required String text,
    String linkedInquiryId = '',
  });
  Future<void> sendMessage({
    required String conversationId,
    required String messageId,
    required String uid,
    required String text,
  });
  Future<void> changeStatus({
    required String conversationId,
    required String uid,
    required String status,
    required int expectedRevision,
  });
  Future<void> markRead(String conversationId, String uid, int sequence);
}
