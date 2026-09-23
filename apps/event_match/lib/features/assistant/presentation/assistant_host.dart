import 'dart:async';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../matching/data/catalog_repository.dart';
import '../../matching/domain/models.dart';
import '../data/basic_assistant_service.dart';
import '../data/firebase_assistant_service.dart';
import '../domain/assistant_service.dart';
import 'assistant_controller.dart';
import 'assistant_screen.dart';

/// Route content for the demo assistant; never mixes anonymous fixtures into live catalog.
class AssistantHost extends StatefulWidget {
  const AssistantHost({
    super.key,
    required this.repository,
    this.initialRequest,
    this.service,
    this.session,
    this.onOpenCatalog,
    this.showHeading = true,
    this.resultsOnPage = false,
  });
  final CatalogRepository repository;
  final MatchRequest? initialRequest;
  final AssistantService? service;
  final AssistantSession? session;
  final VoidCallback? onOpenCatalog;
  final bool showHeading;
  final bool resultsOnPage;
  @override
  State<AssistantHost> createState() => _AssistantHostState();
}

class _AssistantHostState extends State<AssistantHost> {
  late final AssistantSession session;

  @override
  void initState() {
    super.initState();
    session =
        widget.session ??
        AssistantSession(
          repository: widget.repository,
          service: widget.service,
        );
    if (widget.initialRequest != null) {
      session.controller.seedFromRequest(widget.initialRequest!);
    }
  }

  @override
  void didUpdateWidget(covariant AssistantHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialRequest != null &&
        widget.initialRequest != oldWidget.initialRequest) {
      session.controller.seedFromRequest(widget.initialRequest!);
    }
  }

  @override
  void dispose() {
    if (widget.session == null) session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AssistantScreen(
    controller: session.controller,
    onOpenCatalog: widget.onOpenCatalog,
    showHeading: widget.showHeading,
    resultsOnPage: widget.resultsOnPage,
  );
}

/// Keep at app level to preserve the chat between navigation destinations.
/// Account changes clear it even when the assistant route is not visible.
class AssistantSession {
  late final AssistantController controller;
  StreamSubscription<User?>? _authSubscription;
  String? _uid;
  AssistantSession({
    required CatalogRepository repository,
    AssistantService? service,
  }) {
    final basic = BasicAssistantService(repository);
    AssistantService active = service ?? basic;
    const emulator = bool.fromEnvironment('USE_FIREBASE_EMULATORS');
    const enabled = bool.fromEnvironment('ASSISTANT_BACKEND_ENABLED');
    if (service == null && Firebase.apps.isNotEmpty && (emulator || enabled)) {
      final functions = FirebaseFunctions.instanceFor(
        region: const String.fromEnvironment(
          'ASSISTANT_FUNCTIONS_REGION',
          defaultValue: 'us-central1',
        ),
      );
      if (emulator) {
        const configuredHost = String.fromEnvironment('FIREBASE_EMULATOR_HOST');
        final host = configuredHost.isNotEmpty
            ? configuredHost
            : !kIsWeb && defaultTargetPlatform == TargetPlatform.android
            ? '10.0.2.2'
            : '127.0.0.1';
        functions.useFunctionsEmulator(host, 5001);
      }
      active = FirebaseAssistantService(AssistantBackend(functions: functions));
    }
    controller = AssistantController(
      service: active,
      basicService: basic,
      repository: repository,
    );
    unawaited(controller.loadCatalog());
    if (Firebase.apps.isNotEmpty) {
      _uid = FirebaseAuth.instance.currentUser?.uid;
      _authSubscription = FirebaseAuth.instance.authStateChanges().listen((
        user,
      ) {
        if (_uid != null && _uid != user?.uid) controller.reset();
        _uid = user?.uid;
      });
    }
  }

  void dispose() {
    unawaited(_authSubscription?.cancel());
    controller.dispose();
  }
}
