import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'app/app.dart';
import 'features/matching/data/api_catalog_repository.dart';
import 'features/matching/data/api_recommendation_service.dart';
import 'core/local_api.dart';
import 'features/auth/data/local_auth_gateway.dart';
import 'features/auth/presentation/session_controller.dart';
import 'features/workspace/data/local_workspace_repository.dart';
import 'features/assistant/data/api_assistant_service.dart';
import 'features/messages/messages_panel.dart';
export 'app/firebase_bootstrap.dart'
    show FirebaseBootstrap, firebaseOptionsForEnvironment;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final defaultUrl = !kIsWeb && defaultTargetPlatform == TargetPlatform.android
      ? 'http://10.0.2.2:8787'
      : 'http://127.0.0.1:8787';
  final url = const String.fromEnvironment('API_BASE_URL').isEmpty
      ? defaultUrl
      : const String.fromEnvironment('API_BASE_URL');
  const token = String.fromEnvironment('LOCAL_API_TOKEN');
  final repository = ApiCatalogRepository(baseUrl: url, token: token);
  final api = LocalApi(baseUrl: url, localToken: token);
  final workspace = LocalWorkspaceRepository(api);
  final session = SessionController(
    auth: LocalAuthGateway(api),
    repository: workspace,
    requireEmailVerification: false,
  );
  runApp(
    EventMatchApp(
      repository: repository,
      session: session,
      workspace: workspace,
      plans: workspace,
      assistantService: ApiAssistantService(api),
      messagesRepository: ApiMessagesRepository(api),
      recommendationService: ApiRecommendationService(
        repository,
        baseUrl: url,
        token: token,
      ),
    ),
  );
}
