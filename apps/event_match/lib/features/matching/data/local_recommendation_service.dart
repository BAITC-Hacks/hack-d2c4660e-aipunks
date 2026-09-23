import '../domain/matching_engine.dart';
import '../domain/models.dart';
import '../domain/recommendation_service.dart';
import 'catalog_repository.dart';

class LocalRecommendationService implements RecommendationService {
  LocalRecommendationService(this.repository);
  final CatalogRepository repository;
  final engine = const MatchingEngine();

  @override
  bool get supportsPreferences => false;

  @override
  Future<MatchResult> recommend(MatchRequest request) async {
    request.validate();
    return engine.match(await repository.load(), request);
  }
}
