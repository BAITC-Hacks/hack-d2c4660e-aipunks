// Opt-in visual QA; generates local screenshots, never calls GPT or builds web/APK.
import 'dart:io';
import 'dart:ui' as ui;
import 'package:event_match/app/app.dart';
import 'package:event_match/app/communication_scope.dart';
import 'package:event_match/features/auth/presentation/session_controller.dart';
import 'package:event_match/features/matching/presentation/widgets/contractor_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'auth_session_test.dart' show FakeAuthGateway, SessionRepository, alice;
import 'communications_test.dart' show MessagesFake, live;
import 'favorites_test.dart' show FailingRepository;
import 'widget_test.dart' show MemoryCatalog;

void main() {
  for (final size in [const Size(1440, 1000), const Size(375, 812)]) {
    testWidgets(
      'integrated communication preview $size',
      (tester) async {
        final auth = FakeAuthGateway()..identity = alice;
        final workspace = SessionRepository();
        final session = SessionController(auth: auth, repository: workspace);
        final messages = MessagesFake()
          ..rows.addAll([
            {
              'id': 'one',
              'senderId': 'alice',
              'text':
                  'Здравствуйте! Ищем фотографа на свадьбу. Можно обсудить программу и стоимость?',
            },
            {
              'id': 'two',
              'senderId': 'owner',
              'text':
                  'Здравствуйте! Да, напишите дату и сколько часов съёмки планируете.',
            },
          ]);
        addTearDown(session.dispose);
        await tester.runAsync(() async {
          for (final f in {
            'Manrope': 'assets/fonts/Manrope.ttf',
            'NotoSans': 'assets/fonts/NotoSans.ttf',
            'CormorantGaramond': 'assets/fonts/CormorantGaramond-Italic.ttf',
            'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
          }.entries) {
            await (FontLoader(f.key)..addFont(rootBundle.load(f.value))).load();
          }
        });
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final key = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: key,
            child: EventMatchApp(
              repository: MemoryCatalog([live]),
              session: session,
              workspace: workspace,
              messagesRepository: messages,
              favoritesRepository: FailingRepository(),
              initialLocation: '/',
            ),
          ),
        );
        await tester.pumpAndSettle();
        Future<void> capture(String name) async {
          await tester.runAsync(() async {
            final boundary =
                key.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final bitmap = await boundary.toImage(pixelRatio: 1);
            final png = await bitmap.toByteData(format: ui.ImageByteFormat.png);
            final file = File('build/previews/$name-${size.width.toInt()}.png');
            await file.parent.create(recursive: true);
            await file.writeAsBytes(png!.buffer.asUint8List());
            bitmap.dispose();
          });
        }

        final context = tester.element(find.byType(ContractorCard).first);
        CommunicationScope.maybeOf(context)!.openAssistant(context);
        await tester.pumpAndSettle();
        await capture('integrated-assistant');
        await tester.tap(find.byTooltip('Закрыть помощника'));
        await tester.pumpAndSettle();
        CommunicationScope.maybeOf(context)!.openMessages(context, live);
        await tester.pumpAndSettle();
        await capture('integrated-messages');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
      skip: !const bool.fromEnvironment('VISUAL_PREVIEW'),
    );
  }
}
