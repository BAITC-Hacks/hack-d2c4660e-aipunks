import 'package:event_match/features/communication/domain/communication_models.dart';
import 'package:event_match/features/workspace/domain/workspace_models.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> conversationData({
  String kind = 'inquiry',
  String status = 'sent',
  String assignedAdminId = '',
}) => {
  'kind': kind,
  'participantIds': kind == 'support' ? ['client'] : ['client', 'contractor'],
  'clientId': 'client',
  'contractorId': kind == 'support' ? '' : 'contractor',
  'clientName': 'Заказчик',
  'contractorName': kind == 'support' ? '' : 'Подрядчик',
  'eventId': kind == 'support' ? '' : 'wedding',
  'eventSnapshot': kind == 'support'
      ? <String, dynamic>{}
      : {
          'name': 'Свадьба',
          'city': 'Алматы',
          'date': '2026-11-14',
          'format': 'свадьба',
          'preferences': '50 гостей',
        },
  'subject': 'Обсудить мероприятие',
  'status': status,
  'linkedInquiryId': '',
  'assignedAdminId': assignedAdminId,
  'contextTicketId': '',
  'lastMessageId': 'message-1',
  'lastSenderId': 'client',
  'messageCount': 1,
  'revision': 1,
};

Conversation inquiry(String status) =>
    Conversation.fromMap('inquiry-1', conversationData(status: status));

Conversation support(String status, {String assignedAdminId = ''}) =>
    Conversation.fromMap(
      'support-1',
      conversationData(
        kind: 'support',
        status: status,
        assignedAdminId: assignedAdminId,
      ),
    );

void main() {
  group('inquiry permissions', () {
    test(
      'new request permits its participants to discuss and roles to act',
      () {
        final conversation = inquiry('sent');
        expect(conversation.canSend('client'), isTrue);
        expect(conversation.canSend('contractor'), isTrue);
        expect(conversation.transitionsFor('client'), ['cancelled']);
        expect(conversation.transitionsFor('contractor'), [
          'discussing',
          'declined',
        ]);
      },
    );

    test('either participant can close an active discussion', () {
      final conversation = inquiry('discussing');
      expect(conversation.transitionsFor('client'), ['cancelled', 'closed']);
      expect(conversation.transitionsFor('contractor'), ['declined', 'closed']);
    });

    test(
      'staff privileges alone do not allow writing or changing an inquiry',
      () {
        for (final status in ['sent', 'discussing']) {
          final conversation = inquiry(status);
          for (final admin in [false, true]) {
            expect(conversation.canSend('outsider', isAdmin: admin), isFalse);
            expect(
              conversation.transitionsFor('outsider', isAdmin: admin),
              isEmpty,
            );
          }
        }
      },
    );

    for (final status in ['declined', 'cancelled', 'closed']) {
      test('$status is final for both participants', () {
        final conversation = inquiry(status);
        expect(conversation.isTerminal, isTrue);
        for (final uid in ['client', 'contractor', 'admin']) {
          expect(conversation.canSend(uid, isAdmin: true), isFalse);
          expect(conversation.transitionsFor(uid, isAdmin: true), isEmpty);
        }
      });
    }
  });

  group('support permissions', () {
    test('requester can add detail before assignment and close own ticket', () {
      final conversation = support('open');
      expect(conversation.canSend('client'), isTrue);
      expect(conversation.transitionsFor('client'), ['resolved']);
      expect(conversation.canSend('admin', isAdmin: true), isFalse);
      expect(conversation.transitionsFor('admin', isAdmin: true), [
        'in_progress',
      ]);
    });

    test('moderator or unprivileged user cannot claim support', () {
      final conversation = support('open');
      for (final uid in ['moderator', 'contractor', 'outsider']) {
        expect(conversation.canSend(uid), isFalse);
        expect(conversation.transitionsFor(uid), isEmpty);
      }
    });

    test('an admin cannot claim their own support ticket', () {
      final conversation = support('open');
      expect(conversation.transitionsFor('client', isAdmin: true), [
        'resolved',
      ]);
    });

    test('only current assigned admin can reply or resolve for support', () {
      final conversation = support('in_progress', assignedAdminId: 'admin');
      expect(conversation.canSend('admin', isAdmin: true), isTrue);
      expect(conversation.transitionsFor('admin', isAdmin: true), ['resolved']);
      expect(conversation.canSend('other-admin', isAdmin: true), isFalse);
      expect(
        conversation.transitionsFor('other-admin', isAdmin: true),
        isEmpty,
      );
      expect(conversation.canSend('client'), isTrue);
      expect(conversation.transitionsFor('client'), ['resolved']);
    });

    test('revoking admin role removes assigned support permission', () {
      final conversation = support('in_progress', assignedAdminId: 'admin');
      expect(conversation.canSend('admin'), isFalse);
      expect(conversation.transitionsFor('admin'), isEmpty);
    });

    test('resolved ticket cannot be reopened or receive more messages', () {
      final conversation = support('resolved', assignedAdminId: 'admin');
      expect(conversation.isTerminal, isTrue);
      for (final uid in ['client', 'admin', 'other-admin']) {
        expect(conversation.canSend(uid, isAdmin: true), isFalse);
        expect(conversation.transitionsFor(uid, isAdmin: true), isEmpty);
      }
    });
  });

  group('message validation', () {
    test('rejects empty and whitespace-only messages', () {
      for (final text in ['', ' ', '\n\t\r ']) {
        expect(() => validateMessage(text), throwsArgumentError);
      }
    });

    test('limits trimmed text at 4000 characters', () {
      expect(() => validateMessage('  Привет!\n'), returnsNormally);
      expect(() => validateMessage(' ${'я' * 4000}\n'), returnsNormally);
      expect(() => validateMessage('я' * 4001), throwsArgumentError);
    });
  });

  group('saved conversation context', () {
    test('captures calendar date and brief without mutable source aliases', () {
      final event = ClientEvent(
        id: 'wedding',
        name: 'Свадьба',
        city: 'Алматы',
        date: DateTime(2026, 11, 14, 18, 30),
        format: 'свадьба',
        preferences: '50 гостей',
      );
      final snapshot = eventContext(event);
      expect(snapshot, {
        'name': 'Свадьба',
        'city': 'Алматы',
        'date': '2026-11-14',
        'format': 'свадьба',
        'preferences': '50 гостей',
      });
      final separateSnapshot = eventContext(event);
      separateSnapshot['name'] = 'Новая версия';
      expect(snapshot['name'], 'Свадьба');
      expect(event.name, 'Свадьба');
    });

    test(
      'reading detaches participants and event from the source document',
      () {
        final data = conversationData();
        final conversation = Conversation.fromMap('inquiry-1', data);
        (data['participantIds'] as List<String>).add('outsider');
        (data['eventSnapshot'] as Map<String, dynamic>)['city'] = 'Астана';
        expect(conversation.participantIds, ['client', 'contractor']);
        expect(conversation.canSend('outsider'), isFalse);
        expect(conversation.eventSnapshot['city'], 'Алматы');
      },
    );

    test('absent timestamps remain unknown until acknowledged by server', () {
      final conversation = Conversation.fromMap(
        'inquiry-1',
        conversationData(),
      );
      final message = ConversationMessage.fromMap('message-1', {
        'senderId': 'client',
        'text': 'Здравствуйте',
        'sequence': 1,
      });
      expect(conversation.createdAt, isNull);
      expect(conversation.updatedAt, isNull);
      expect(conversation.lastMessageAt, isNull);
      expect(message.createdAt, isNull);
      expect(message.sequence, 1);
    });
  });
}
