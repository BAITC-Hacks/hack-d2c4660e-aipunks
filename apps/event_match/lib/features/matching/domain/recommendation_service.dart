import 'models.dart';

/// UI consumes this boundary, not a concrete ranking engine or LLM SDK.
abstract interface class RecommendationService {
  bool get supportsPreferences;
  Future<MatchResult> recommend(MatchRequest request);
}
