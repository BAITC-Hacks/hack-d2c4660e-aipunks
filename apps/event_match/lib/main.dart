import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'app/app.dart';
import 'features/matching/data/api_catalog_repository.dart';
import 'features/matching/data/api_recommendation_service.dart';

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
  runApp(
    EventMatchApp(
      repository: repository,
      recommendationService: ApiRecommendationService(
        repository,
        baseUrl: url,
        token: token,
      ),
    ),
  );
}
