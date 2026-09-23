import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:event_match/features/matching/data/catalog_repository.dart';
import 'package:event_match/features/matching/domain/models.dart';
import 'package:event_match/features/matching/domain/recommendation_service.dart';
import 'package:event_match/features/matching/presentation/matching_controller.dart';

class EmptyCatalog implements CatalogRepository {
  @override
  Future<List<Contractor>> load() async => [];
}

class ControlledService implements RecommendationService {
  final requests = <Completer<MatchResult>>[];
  @override
  bool get supportsPreferences => true;
  @override
  Future<MatchResult> recommend(MatchRequest request) {
    final pending = Completer<MatchResult>();
    requests.add(pending);
    return pending.future;
  }
}

void main() {
  final request = MatchRequest(
    city: 'Алматы',
    date: DateTime(2026, 10, 10),
    format: 'свадьба',
    category: 'Ведущий',
    budget: 1000000,
    preferences: '  Без шумных конкурсов  ',
  );
  const result = MatchResult(MatchOutcome.categoryAbsent, [], 'Нет категории');

  test('edited request invalidates a pending response', () async {
    final service = ControlledService();
    final controller = MatchingController(EmptyCatalog(), service: service);
    final pending = controller.search(request);
    expect(controller.status, SearchStatus.searching);
    controller.clearResult();
    service.requests.single.complete(result);
    await pending;
    expect(controller.status, SearchStatus.idle);
    expect(controller.result, isNull);
    controller.dispose();
  });

  test('failure can be retried and newest result wins', () async {
    final service = ControlledService();
    final controller = MatchingController(EmptyCatalog(), service: service);
    final first = controller.search(request);
    service.requests.first.completeError(StateError('offline'));
    await first;
    expect(controller.status, SearchStatus.failure);
    final second = controller.search(request);
    service.requests.last.complete(result);
    await second;
    expect(controller.status, SearchStatus.success);
    expect(controller.searchError, isNull);
    controller.dispose();
  });

  test('completion after disposal is ignored', () async {
    final service = ControlledService();
    final controller = MatchingController(EmptyCatalog(), service: service);
    final pending = controller.search(request);
    controller.dispose();
    service.requests.single.complete(result);
    await pending;
    expect(controller.result, isNull);
  });

  test('API request preserves typed constraints and trims wishes', () {
    expect(request.toJson()['preferences'], 'Без шумных конкурсов');
    expect(request.toJson()['date'], '2026-10-10');
    expect(request.toJson()['budget_kzt'], 1000000);
    expect(
      () => MatchRequest(
        city: 'Алматы',
        date: DateTime(2027),
        format: 'свадьба',
        category: 'Ведущий',
        budget: 1,
      ).validate(),
      throwsArgumentError,
    );
  });
}
