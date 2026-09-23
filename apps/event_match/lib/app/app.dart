import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import '../features/matching/data/catalog_repository.dart';
import '../features/matching/presentation/matching_screen.dart';
import '../features/matching/domain/recommendation_service.dart';
import '../features/matching/data/favorites_repository.dart';
import 'app_theme.dart';

class EventMatchApp extends StatelessWidget {
  const EventMatchApp({
    super.key,
    this.repository,
    this.recommendationService,
    this.favoritesRepository,
  });
  final CatalogRepository? repository;
  final RecommendationService? recommendationService;
  final FavoritesRepository? favoritesRepository;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Event Match',
    debugShowCheckedModeBanner: false,
    locale: const Locale('ru'),
    supportedLocales: const [Locale('ru')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: AppTheme.light,
    home: MatchingScreen(
      repository: repository ?? AssetCatalogRepository(),
      service: recommendationService,
      favoritesRepository: favoritesRepository,
    ),
  );
}
