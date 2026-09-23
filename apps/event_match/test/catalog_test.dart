import 'package:flutter_test/flutter_test.dart';
import 'package:event_match/features/matching/data/catalog_repository.dart';
import 'package:event_match/features/matching/domain/matching_engine.dart';
import 'package:event_match/features/matching/domain/models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'organizer catalog preserves 66 profiles and 13 synthetic flags',
    () async {
      final catalog = await AssetCatalogRepository().load();
      expect(catalog.length, 66);
      expect(catalog.where((c) => c.synthetic).length, 13);
      expect(catalog.map((c) => c.id).toSet().length, 66);
      final florist = catalog.singleWhere((c) => c.id == 'HK-39372');
      expect(florist.maxHours, isNull);
      expect(florist.priceImputed, isTrue);
      expect(florist.busyDates, contains('2026-11-14'));
      final result = const MatchingEngine().match(
        catalog,
        MatchRequest(
          city: 'Алматы',
          date: DateTime(2026, 10, 10),
          format: 'свадьба',
          category: 'Ведущий',
          budget: 1000000,
        ),
      );
      expect(result.recommendations.map((c) => c.contractor.id), [
        'HK-27222',
        'HK-77838',
      ]);
    },
  );
}
