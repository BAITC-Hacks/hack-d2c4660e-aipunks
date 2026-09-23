import 'package:event_match/app/app.dart';
import 'package:event_match/app/app_theme.dart';
import 'package:event_match/app/communication_scope.dart';
import 'package:event_match/features/assistant/presentation/assistant_screen.dart';
import 'package:event_match/features/assistant/presentation/assistant_controller.dart';
import 'package:event_match/features/matching/domain/models.dart';
import 'package:event_match/features/matching/presentation/widgets/contractor_card.dart';
import 'package:event_match/features/messages/messages_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'widget_test.dart' show MemoryCatalog;
import 'favorites_test.dart' show FailingRepository;

const live = Contractor(
  id: 'owner',
  name: 'Анна',
  city: 'Алматы',
  categories: ['Фотограф'],
  price: 150000,
  formats: ['свадьба'],
  languages: ['русский'],
  busyDates: [],
  description: 'Репортажная съёмка.',
  isLive: true,
);

class MessagesFake implements MessagesRepository {
  final rows = <Map<String, dynamic>>[];
  final nonces = <String>[];
  bool fail = false;
  @override
  Future<List<Map<String, dynamic>>> list() async => [
    {'id': 'thread', 'peerName': 'Анна', 'lastMessage': 'Здравствуйте'},
  ];
  @override
  Future<Map<String, dynamic>> open(String id) async => {
    'id': 'thread',
    'peerName': 'Анна',
  };
  @override
  Future<List<Map<String, dynamic>>> read(String id) async => List.of(rows);
  @override
  Future<void> send(String id, String text, String nonce) async {
    nonces.add(nonce);
    if (fail) {
      fail = false;
      throw StateError('offline');
    }
    rows.add({'id': 'message', 'senderId': 'client', 'text': text});
  }
}

void main() {
  for (final size in [
    const Size(1440, 1000),
    const Size(375, 812),
    const Size(844, 390),
  ]) {
    testWidgets('assistant stays in side panel at $size; buttons retain chat', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        EventMatchApp(
          repository: MemoryCatalog([live]),
          favoritesRepository: FailingRepository(),
        ),
      );
      await tester.pumpAndSettle();
      // Access through the shared scope, including the narrow layout's account menu path.
      final context = tester.element(find.byType(ContractorCard).first);
      CommunicationScope.maybeOf(context)!.openAssistant(context);
      await tester.pumpAndSettle();
      expect(find.byType(AssistantScreen), findsOneWidget);
      final rect = tester.getRect(
        find
            .descendant(
              of: find.byType(Dialog),
              matching: find.byType(Scaffold),
            )
            .first,
      );
      expect(rect.right, closeTo(size.width - 24, 1));
      if (size.width > 700) expect(rect.width, 640);
      final screen = tester.widget<AssistantScreen>(
        find.byType(AssistantScreen),
      );
      final AssistantController controller = screen.controller;
      await tester.scrollUntilVisible(
        find.widgetWithText(ActionChip, 'Фотограф'),
        180,
        scrollable: find
            .descendant(
              of: find.byKey(const Key('assistant-conversation')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ActionChip, 'Фотограф').first);
      await tester.pumpAndSettle();
      expect(controller.brief.category, 'Фотограф');
      expect(controller.turn!.actions, isNotEmpty);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Закрыть помощника'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      CommunicationScope.maybeOf(context)!.openAssistant(context);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<AssistantScreen>(find.byType(AssistantScreen))
            .controller
            .brief
            .category,
        'Фотограф',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  testWidgets('card message action is below profile and demo cannot contact', (
    tester,
  ) async {
    Contractor? selected;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: CommunicationScope(
          openAssistant: (_) {},
          openMessages: (_, c) => selected = c,
          child: Scaffold(
            body: SingleChildScrollView(
              child: SizedBox(
                width: 500,
                child: ContractorCard(contractor: live),
              ),
            ),
          ),
        ),
      ),
    );
    final action = find.byKey(const ValueKey('message-owner'));
    await tester.ensureVisible(action);
    await tester.pumpAndSettle();
    expect(
      tester.getRect(action).top,
      greaterThan(
        tester.getRect(find.byKey(const ValueKey('profile-owner'))).bottom,
      ),
    );
    await tester.tap(action);
    expect(selected, live);
  });
  for (final size in [
    const Size(640, 850),
    const Size(327, 700),
    const Size(640, 342),
  ]) {
    testWidgets('message draft and retry survive failure at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = MessagesFake()..fail = true;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: MessagesPanel(
            repository: repo,
            uid: 'client',
            contractor: live,
            onSignIn: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('message-input')),
        'Здравствуйте, обсудим дату?',
      );
      await tester.tap(find.byKey(const Key('send-message')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('message-input')))
            .controller!
            .text,
        isNotEmpty,
      );
      await tester.tap(find.byKey(const Key('send-message')));
      await tester.pumpAndSettle();
      expect(repo.rows.single['text'], 'Здравствуйте, обсудим дату?');
      expect(repo.nonces[0], repo.nonces[1]);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('message-input')))
            .controller!
            .text,
        isEmpty,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
