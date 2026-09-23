import '../../matching/data/catalog_repository.dart';
import '../../matching/domain/models.dart';
import '../../matching/domain/matching_engine.dart';
import '../../matching/domain/recommendation_service.dart';
import '../domain/workspace_repository.dart';

class WorkspaceCatalogRepository implements CatalogRepository {
  WorkspaceCatalogRepository(this.workspace);
  final WorkspaceRepository workspace;
  @override
  Future<List<Contractor>> load() async => (await workspace.listPublished())
      .map((p) => p.content.toContractor(p.ownerId))
      .toList();
}

class LiveRecommendationService implements RecommendationService {
  LiveRecommendationService(this.workspace, {DateTime Function()? clock})
    : clock = clock ?? DateTime.now;
  final WorkspaceRepository workspace;
  final DateTime Function() clock;
  @override
  bool get supportsPreferences => false;
  @override
  Future<MatchResult> recommend(MatchRequest request) async {
    final now = clock();
    final policy = MatchDatePolicy.live(now);
    request.validate(datePolicy: policy);
    final catalog = await WorkspaceCatalogRepository(workspace).load();
    final candidates = catalog.where(
      (c) => c.city == request.city && c.categories.contains(request.category),
    );
    final availability = <String, AvailabilityStatus>{};
    await Future.wait(
      candidates.map((c) async {
        final calendar = await workspace.getCalendar(c.id, request.date);
        availability[c.id] =
            calendar?.availabilityOn(request.date, now) ??
            AvailabilityStatus.unconfirmed;
      }),
    );
    return const MatchingEngine().match(
      catalog,
      request,
      datePolicy: policy,
      availability: availability,
    );
  }
}
