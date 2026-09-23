import 'package:flutter_test/flutter_test.dart';
import 'package:event_match/features/matching/data/catalog_repository.dart';
import 'package:event_match/features/matching/domain/matching_engine.dart';
import 'package:event_match/features/matching/domain/models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'expanded catalog keeps 66 organizer profiles and adds 434 demo profiles',
    () async {
      final catalog = await AssetCatalogRepository().load();
      expect(catalog.length, 500);
      expect(catalog.where((c) => c.synthetic).length, 447);
      expect(catalog.map((c) => c.id).toSet().length, 500);
      final original = catalog.where((c) => !c.id.startsWith('DEMO-')).toList();
      expect(original.length, 66);
      expect(original.where((c) => c.synthetic).length, 13);
      final florist = catalog.singleWhere((c) => c.id == 'HK-39372');
      expect(florist.maxHours, isNull);
      expect(florist.priceImputed, isTrue);
      expect(florist.busyDates, contains('2026-11-14'));
      final result = const MatchingEngine().match(
        original,
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
