import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:event_match/app/app_theme.dart';
import 'package:event_match/app/design_tokens.dart';
import 'package:event_match/features/communication/domain/communication_models.dart';
import 'package:event_match/features/communication/domain/communication_repository.dart';
import 'package:event_match/features/communication/presentation/communication_page.dart';
import 'package:event_match/features/workspace/domain/workspace_models.dart';
import 'package:event_match/features/workspace/domain/workspace_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Conversation conversation({
  String id = 'inquiry',
  String kind = 'inquiry',
  String status = 'sent',
  String assignedAdminId = '',
  String linkedInquiryId = '',
  int revision = 1,
  int count = 1,
}) => Conversation(
  id: id,
  kind: kind,
  participantIds: [
    'client',
    if (kind == 'inquiry') 'provider',
    if (assignedAdminId.isNotEmpty) assignedAdminId,
  ],
  clientId: 'client',
  contractorId: kind == 'inquiry' ? 'provider' : '',
  clientName: 'Алия',
  contractorName: kind == 'inquiry' ? 'Студия света' : '',
  eventId: kind == 'inquiry' ? 'real-event' : '',
  eventSnapshot: kind == 'inquiry'
      ? {
          'name': 'Свадьба в саду',
          'city': 'Алматы',
          'date': '2027-05-20',
          'format': 'свадьба',
          'preferences': 'Естественный свет',
        }
      : {},
  subject: kind == 'inquiry' ? 'Фотограф · Свадьба в саду' : 'Нужна помощь',
  status: status,
  linkedInquiryId: linkedInquiryId,
  assignedAdminId: assignedAdminId,
  contextTicketId: '',
  lastMessageId: 'first',
  lastSenderId: 'provider',
  messageCount: count,
  revision: revision,
);

class CommunicationFake implements CommunicationRepository {
  final conversations = <String, Conversation>{};
  final messages = <String, List<ConversationMessage>>{};
  final changes = StreamController<void>.broadcast();
  final messageErrors = StreamController<Object>.broadcast();
  final conversationErrors = StreamController<Object>.broadcast();
  final sends = <({String id, String text, String uid})>[];
  final creates = <Map<String, String>>[];
  final reads = <int>[];
  final messageLimits = <int>[];
  final conversationRequests = <String>[];
  final deniedConversationIds = <String>{};
  final statuses = <({String status, String uid, int revision})>[];
  final inboxRequests = <({String uid, bool queue})>[];
  int idCounter = 0;
  int read = 0;
  bool failSend = false, failCreate = false;

  Stream<T> stream<T>(T Function() value, {Stream<Object>? errors}) =>
      Stream<T>.multi((sink) {
        sink.add(value());
        final sub = changes.stream.listen((_) => sink.add(value()));
        final err = errors?.listen(sink.addError);
        sink.onCancel = () async {
          await sub.cancel();
          await err?.cancel();
        };
      });
  @override
  String newId() => 'generated-${++idCounter}';
  @override
  Stream<List<Conversation>> watchInbox(
    String uid, {
    bool supportQueue = false,
    int limit = 50,
  }) {
    inboxRequests.add((uid: uid, queue: supportQueue));
    return stream(() => conversations.values.toList());
  }

  @override
  Stream<Conversation?> watchConversation(String id) {
    conversationRequests.add(id);
    if (deniedConversationIds.contains(id)) {
      return Stream.error(Exception('permission-denied'));
    }
    return stream(() => conversations[id], errors: conversationErrors.stream);
  }

  @override
  Stream<List<ConversationMessage>> watchMessages(String id, {int limit = 50}) {
    messageLimits.add(limit);
    return stream(
      () => (messages[id] ?? [])
          .skip(((messages[id]?.length ?? 0) - limit).clamp(0, 100000))
          .toList(),
      errors: messageErrors.stream,
    );
  }

  @override
  Stream<int> watchReadSequence(String id, String uid) => stream(() => read);
  @override
  Stream<List<CommunicationAudit>> watchAudit(String id) => stream(
    () => [
      const CommunicationAudit(
        actorId: 'client',
        action: 'opened',
        revision: 1,
      ),
    ],
  );
  @override
  Future<void> markRead(String conversationId, String uid, int sequence) async {
    reads.add(sequence);
  }

  @override
  Future<void> sendMessage({
    required String conversationId,
    required String messageId,
    required String uid,
    required String text,
  }) async {
    sends.add((id: messageId, text: text, uid: uid));
    if (failSend) throw Exception('secret firestore path permission-denied');
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
    creates.add({
      'id': id,
      'uid': uid,
      'contractorId': contractorId,
      'eventId': eventId,
      'category': category,
      'text': text,
    });
    if (failCreate) throw Exception('secret error');
    conversations[id] = conversation(id: id);
    changes.add(null);
  }

  @override
  Future<void> createSupport({
    required String id,
    required String uid,
    required String subject,
    required String text,
    String linkedInquiryId = '',
  }) async {
    creates.add({
      'id': id,
      'uid': uid,
      'subject': subject,
      'text': text,
      'linkedInquiryId': linkedInquiryId,
    });
    if (failCreate) throw Exception('secret error');
    conversations[id] = conversation(
      id: id,
      kind: 'support',
      status: 'open',
      linkedInquiryId: linkedInquiryId,
    );
    changes.add(null);
  }

  @override
  Future<void> changeStatus({
    required String conversationId,
    required String uid,
    required String status,
    required int expectedRevision,
  }) async {
    statuses.add((status: status, uid: uid, revision: expectedRevision));
    final c = conversations[conversationId]!;
    conversations[conversationId] = conversation(
      id: c.id,
      kind: c.kind,
      status: status,
      assignedAdminId: status == 'in_progress' ? uid : c.assignedAdminId,
      linkedInquiryId: c.linkedInquiryId,
      revision: c.revision + 1,
    );
    changes.add(null);
  }

  Future<void> dispose() async {
    await changes.close();
    await messageErrors.close();
    await conversationErrors.close();
  }
}

class CommunicationWorkspaceFake implements WorkspaceRepository {
  List<String> categories = ['Фотограф', 'Фото и видеобудки'];
  List<ClientEvent> events = [
    ClientEvent(
      id: 'real-event',
      name: 'Свадьба в саду',
      city: 'Алматы',
      date: DateTime(2027, 5, 20),
      format: 'свадьба',
      preferences: 'Естественный свет',
    ),
  ];
  String? eventOwner;
  @override
  Future<List<ClientEvent>> listEvents(String uid) async {
    eventOwner = uid;
    return events;
  }

  @override
  Future<List<PublishedProfile>> listPublished() async => [
    for (final (id, name, published) in [
      ('provider', 'Студия света', true),
      ('client', 'Собственная карточка', true),
      ('hidden', 'Снятая карточка', false),
    ])
      PublishedProfile(
        ownerId: id,
        content: ProfileContent(name: name, categories: categories),
        revision: 1,
        profileRevision: 1,
        published: published,
      ),
  ];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget page(
  CommunicationFake repository, {
  String uid = 'client',
  CommunicationMode mode = CommunicationMode.client,
  bool admin = false,
  String? selected,
  String? provider,
  CommunicationWorkspaceFake? workspace,
}) => CommunicationPage(
  repository: repository,
  workspace: workspace ?? CommunicationWorkspaceFake(),
  uid: uid,
  mode: mode,
  isAdmin: admin,
  initialConversationId: selected,
  initialContractorId: provider,
);

Future<void> mount(
  WidgetTester tester,
  Widget child, {
  double width = 375,
  double scale = 1,
}) async {
  tester.view.physicalSize = Size(width, 1100);
  tester.view.devicePixelRatio = 1;
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
              disableAnimations: true,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: child,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'communication visual previews',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final font = File('/System/Library/Fonts/Supplemental/Arial.ttf');
      if (!font.existsSync()) return;
      await tester.runAsync(() async {
        await (FontLoader('Roboto')..addFont(
              Future.value(ByteData.sublistView(await font.readAsBytes())),
            ))
            .load();
        await (FontLoader(
          'MaterialIcons',
        )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      });
      final repo = CommunicationFake()
        ..conversations['inquiry'] = conversation()
        ..messages['inquiry'] = [
          const ConversationMessage(
            id: '1',
            senderId: 'client',
            text:
                'Добрый день! Нужна съёмка камерной свадьбы в саду. Будете свободны 20 мая?',
            sequence: 1,
          ),
          const ConversationMessage(
            id: '2',
            senderId: 'provider',
            text:
                'Здравствуйте, Алия! Да, дата пока свободна. Расскажите, сколько гостей планируете?',
            sequence: 2,
          ),
        ];
      addTearDown(repo.dispose);
      for (final width in [375.0, 1440.0]) {
        for (final entry in {
          'inbox': page(repo),
          'chat': page(repo, selected: 'inquiry'),
          'form': page(repo, provider: 'provider'),
        }.entries) {
          final key = GlobalKey();
          await mount(
            tester,
            RepaintBoundary(
              key: key,
              child: ColoredBox(color: AppColors.canvas, child: entry.value),
            ),
            width: width,
          );
          expect(tester.takeException(), isNull);
          await tester.runAsync(() async {
            final boundary =
                key.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final picture = await boundary.toImage(pixelRatio: 1);
            final bytes = await picture.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final file = File(
              'build/previews/communication-${entry.key}-${width.toInt()}.png',
            );
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes!.buffer.asUint8List());
            picture.dispose();
          });
        }
      }
    },
    skip: !const bool.fromEnvironment('COMMUNICATION_VISUAL_PREVIEW'),
  );

  testWidgets('inquiry uses real selected ids and retries the same creation', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = CommunicationFake()..failCreate = true;
    addTearDown(repo.dispose);
    final workspace = CommunicationWorkspaceFake();
    await mount(tester, page(repo, provider: 'provider', workspace: workspace));
    expect(workspace.eventOwner, 'client');
    expect(find.text('Получатель: Студия света'), findsOneWidget);
    expect(find.text('Дата: 20.05.2027'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('conversation-first-message')),
      'Добрый день! Обсудим съёмку?',
    );
    await tap(tester, find.byKey(const Key('conversation-submit')));
    expect(repo.creates.single['eventId'], 'real-event');
    expect(repo.creates.single['contractorId'], 'provider');
    expect(repo.creates.single['category'], 'Фотограф');
    expect(find.textContaining('Отправка не подтверждена'), findsOneWidget);
    repo.failCreate = false;
    await tap(tester, find.byKey(const Key('conversation-submit')));
    expect(repo.creates.length, 2);
    expect(repo.creates[0], repo.creates[1]);
    expect(find.text('Переписка'), findsOneWidget);
  });

  testWidgets('duplicate provider categories produce unique service choices', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = CommunicationFake();
    addTearDown(repo.dispose);
    final workspace = CommunicationWorkspaceFake()
      ..categories = ['Фотограф', 'Фотограф', 'Фото и видеобудки'];
    await mount(tester, page(repo, provider: 'provider', workspace: workspace));
    expect(tester.takeException(), isNull);
    final dropdown = tester.widget<DropdownButton<String>>(
      find.descendant(
        of: find.byKey(const ValueKey('inquiry-category:provider')),
        matching: find.byType(DropdownButton<String>),
      ),
    );
    expect(dropdown.items!.map((item) => item.value), [
      'Фотограф',
      'Фото и видеобудки',
    ]);
    await tester.enterText(
      find.byKey(const Key('conversation-first-message')),
      'Обсудим съёмку',
    );
    await tap(tester, find.byKey(const Key('conversation-submit')));
    expect(repo.creates.single['category'], 'Фотограф');
  });

  testWidgets('failed send preserves exact text and id until confirmed', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = CommunicationFake()..conversations['inquiry'] = conversation();
    addTearDown(repo.dispose);
    repo.failSend = true;
    await mount(tester, page(repo, selected: 'inquiry'));
    await tester.enterText(
      find.byKey(const Key('message-draft')),
      'Есть ли свободная дата?',
    );
    await tap(tester, find.byKey(const Key('message-send')));
    expect(find.textContaining('Доставка не подтверждена'), findsOneWidget);
    expect(find.textContaining('secret firestore'), findsNothing);
    final field = tester.widget<TextFormField>(
      find.byKey(const Key('message-draft')),
    );
    expect(field.controller!.text, 'Есть ли свободная дата?');
    expect(
      tester
          .widget<EditableText>(
            find.descendant(
              of: find.byKey(const Key('message-draft')),
              matching: find.byType(EditableText),
            ),
          )
          .readOnly,
      isTrue,
    );
    repo.failSend = false;
    await tap(tester, find.byKey(const Key('message-send')));
    expect(repo.sends.length, 2);
    expect(repo.sends[0], repo.sends[1]);
    expect(field.controller!.text, isEmpty);
  });

  testWidgets('linked support requires consent and opens from inquiry mode', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = CommunicationFake()..conversations['inquiry'] = conversation();
    addTearDown(repo.dispose);
    await mount(tester, page(repo, selected: 'inquiry'));
    await tap(tester, find.text('Обратиться в поддержку'));
    expect(
      find.textContaining('Новое обращение заменит доступ по предыдущему'),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const Key('support-subject')),
      'Вопрос по условиям',
    );
    await tester.enterText(
      find.byKey(const Key('conversation-first-message')),
      'Помогите разобраться',
    );
    await tap(tester, find.byKey(const Key('conversation-submit')));
    expect(repo.creates, isEmpty);
    expect(
      find.text('Для передачи переписки нужно ваше согласие.'),
      findsOneWidget,
    );
    await tap(tester, find.byKey(const Key('support-consent')));
    await tap(tester, find.byKey(const Key('conversation-submit')));
    expect(repo.creates.single['linkedInquiryId'], 'inquiry');
    expect(find.text('Ожидает поддержки'), findsOneWidget);
    expect(find.byKey(const Key('message-draft')), findsOneWidget);
  });

  testWidgets('contractor transition and terminal composer permissions', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = CommunicationFake()..conversations['inquiry'] = conversation();
    addTearDown(repo.dispose);
    await mount(
      tester,
      page(
        repo,
        uid: 'provider',
        mode: CommunicationMode.contractor,
        selected: 'inquiry',
      ),
    );
    expect(find.text('Отменить заявку'), findsNothing);
    await tap(tester, find.text('Принять к обсуждению'));
    expect(repo.statuses.single, (
      status: 'discussing',
      uid: 'provider',
      revision: 1,
    ));
    await tap(tester, find.text('Закрыть заявку'));
    expect(repo.statuses.last.revision, 2);
    expect(find.byKey(const Key('message-draft')), findsNothing);
    expect(
      find.text('Переписка закрыта. История сообщений сохранена.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'admin claims support before replying or reading linked context',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = CommunicationFake()
        ..conversations['ticket'] = conversation(
          id: 'ticket',
          kind: 'support',
          status: 'open',
          linkedInquiryId: 'inquiry',
        )
        ..conversations['inquiry'] = conversation();
      addTearDown(repo.dispose);
      await mount(
        tester,
        page(
          repo,
          uid: 'admin',
          mode: CommunicationMode.admin,
          admin: true,
          selected: 'ticket',
        ),
      );
      expect(find.byKey(const Key('message-draft')), findsNothing);
      expect(find.text('Открыть контекст'), findsNothing);
      await tap(tester, find.text('Взять в работу'));
      expect(find.byKey(const Key('message-draft')), findsOneWidget);
      await tap(tester, find.text('Открыть контекст'));
      expect(find.text('Свадьба в саду'), findsOneWidget);
      expect(find.byKey(const Key('message-draft')), findsNothing);
      await tap(tester, find.text('К обращению'));
      await tap(tester, find.text('Завершить обращение'));
      expect(find.text('Открыть контекст'), findsNothing);
      expect(find.byKey(const Key('message-draft')), findsNothing);
    },
  );

  testWidgets(
    'replaced support context explains denied access and allows returning to ticket',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = CommunicationFake()
        ..conversations['ticket'] = conversation(
          id: 'ticket',
          kind: 'support',
          status: 'in_progress',
          linkedInquiryId: 'inquiry',
          assignedAdminId: 'admin',
        )
        ..conversations['inquiry'] = conversation()
        ..deniedConversationIds.add('inquiry');
      addTearDown(repo.dispose);
      await mount(
        tester,
        page(
          repo,
          uid: 'admin',
          mode: CommunicationMode.admin,
          admin: true,
          selected: 'ticket',
        ),
      );
      expect(
        find.textContaining('создании нового обращения по той же заявке'),
        findsOneWidget,
      );
      await tap(tester, find.text('Открыть контекст'));
      expect(find.text('Контекст недоступен'), findsOneWidget);
      expect(
        find.textContaining('заменено новым обращением по этой заявке'),
        findsOneWidget,
      );
      expect(find.text('Свадьба в саду'), findsNothing);
      expect(find.byKey(const Key('message-draft')), findsNothing);
      await tap(tester, find.text('К обращению'));
      expect(find.text('Нужна помощь'), findsOneWidget);
      expect(find.byKey(const Key('message-draft')), findsOneWidget);
    },
  );

  testWidgets(
    'unread inbox never marks messages and revoked stream hides old text',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = CommunicationFake()
        ..conversations['inquiry'] = conversation(count: 100)
        ..messages['inquiry'] = [
          const ConversationMessage(
            id: 'm1',
            senderId: 'provider',
            text: 'Конфиденциальный ответ',
            sequence: 1,
          ),
        ];
      addTearDown(repo.dispose);
      await mount(tester, page(repo));
      expect(find.byKey(const ValueKey('unread:inquiry')), findsOneWidget);
      expect(repo.reads, isEmpty);
      await tap(tester, find.byKey(const ValueKey('open:inquiry')));
      expect(find.text('Конфиденциальный ответ'), findsOneWidget);
      expect(repo.reads.every((s) => s <= 1), isTrue);
      repo.messageErrors.add(Exception('permission-denied'));
      await tester.pumpAndSettle();
      expect(find.text('Конфиденциальный ответ'), findsNothing);
      expect(find.text('Не удалось загрузить данные'), findsOneWidget);
      repo.conversationErrors.add(Exception('permission-denied'));
      await tester.pumpAndSettle();
      expect(find.text('Свадьба в саду'), findsNothing);
      expect(find.byKey(const Key('message-draft')), findsNothing);
    },
  );

  testWidgets('read receipt does not mark rendered messages below viewport', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = CommunicationFake()
      ..conversations['inquiry'] = conversation(count: 50)
      ..messages['inquiry'] = [
        for (var n = 1; n <= 50; n++)
          ConversationMessage(
            id: '$n',
            senderId: 'provider',
            text: 'Сообщение номер $n',
            sequence: n,
          ),
      ];
    addTearDown(repo.dispose);
    await mount(tester, page(repo, selected: 'inquiry'));
    expect(repo.reads, isNotEmpty);
    expect(repo.reads.last, lessThan(50));
    await tester.ensureVisible(find.text('Сообщение номер 50'));
    await tester.pumpAndSettle();
    expect(repo.reads.last, 50);
  });

  testWidgets(
    'history pagination requests older messages in chronological order',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = CommunicationFake()
        ..conversations['inquiry'] = conversation(count: 51)
        ..messages['inquiry'] = [
          for (var n = 1; n <= 51; n++)
            ConversationMessage(
              id: '$n',
              senderId: 'provider',
              text: 'История $n',
              sequence: n,
            ),
        ];
      addTearDown(repo.dispose);
      await mount(tester, page(repo, selected: 'inquiry'));
      expect(find.text('История 1'), findsNothing);
      await tap(tester, find.text('Загрузить предыдущие сообщения'));
      expect(repo.messageLimits, contains(100));
      expect(find.text('История 1'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('История 1')).dy,
        lessThan(tester.getTopLeft(find.text('История 51')).dy),
      );
    },
  );

  testWidgets(
    'session uid change discards selected private conversation and draft',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = CommunicationFake()
        ..conversations['inquiry'] = conversation();
      addTearDown(repo.dispose);
      final workspace = CommunicationWorkspaceFake();
      await mount(
        tester,
        page(repo, selected: 'inquiry', workspace: workspace),
      );
      await tester.enterText(
        find.byKey(const Key('message-draft')),
        'Личный черновик',
      );
      await mount(
        tester,
        page(repo, uid: 'someone-else', workspace: workspace),
      );
      expect(find.text('Личный черновик'), findsNothing);
      expect(find.text('Свадьба в саду'), findsNothing);
      expect(find.text('Пока нет сообщений'), findsOneWidget);
    },
  );

  testWidgets('empty query props open inbox without an empty document read', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = CommunicationFake();
    addTearDown(repo.dispose);
    await mount(tester, page(repo, selected: '', provider: '  '));
    expect(find.text('Пока нет сообщений'), findsOneWidget);
    expect(repo.conversationRequests, isEmpty);
    expect(find.byKey(const Key('conversation-first-message')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'starting a new message after failed delivery requires explicit choice and a new id',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = CommunicationFake()
        ..failSend = true
        ..conversations['inquiry'] = conversation();
      addTearDown(repo.dispose);
      await mount(tester, page(repo, selected: 'inquiry'), scale: 2);
      await tester.enterText(
        find.byKey(const Key('message-draft')),
        'Первый текст',
      );
      await tap(tester, find.byKey(const Key('message-send')));
      await tap(tester, find.text('Начать новое сообщение'));
      expect(find.textContaining('оно могло быть получено'), findsOneWidget);
      await tap(tester, find.text('Начать новое'));
      await tester.enterText(
        find.byKey(const Key('message-draft')),
        'Другой текст',
      );
      repo.failSend = false;
      await tap(tester, find.byKey(const Key('message-send')));
      expect(repo.sends.length, 2);
      expect(repo.sends.first.id, isNot(repo.sends.last.id));
      expect(repo.sends.last.text, 'Другой текст');
      expect(tester.takeException(), isNull);
    },
  );

  for (final width in [375.0, 768.0, 1024.0, 1440.0]) {
    testWidgets('communication inbox form and detail fit $width and 2x text', (
      tester,
    ) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = CommunicationFake()
        ..conversations['inquiry'] = conversation()
        ..messages['inquiry'] = [
          const ConversationMessage(
            id: '1',
            senderId: 'provider',
            text: 'Давайте обсудим все пожелания к вашему мероприятию.',
            sequence: 1,
          ),
        ];
      addTearDown(repo.dispose);
      for (final scale in [1.0, 2.0]) {
        for (final screen in [
          page(repo),
          page(repo, selected: 'inquiry'),
          page(repo, provider: 'provider'),
        ]) {
          await mount(tester, screen, width: width, scale: scale);
          expect(tester.takeException(), isNull);
        }
      }
    });
  }
}
