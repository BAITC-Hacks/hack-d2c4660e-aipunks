import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:event_match/features/matching/data/favorites_repository.dart';
import 'package:event_match/features/matching/domain/favorites.dart';
import 'package:event_match/features/matching/domain/models.dart';
import 'package:event_match/features/matching/presentation/favorites_controller.dart';

const contractor = Contractor(
  id: 'one',
  name: 'Первый',
  city: 'Алматы',
  categories: ['Ведущий'],
  price: 100000,
  formats: ['свадьба'],
  languages: ['русский'],
  busyDates: [],
  description: 'Камерные свадьбы',
);
final request = MatchRequest(
  city: 'Алматы',
  date: DateTime(2026, 10, 10),
  format: 'свадьба',
  category: 'Ведущий',
  budget: 500000,
  language: 'русский',
  hours: 5,
  preferences: 'камерная свадьба',
);

class FailingRepository implements FavoritesRepository {
  bool failWrite = false;
  List<FavoriteFolder> stored = [];
  @override
  Future<List<FavoriteFolder>> load() async => stored;
  @override
  Future<void> save(List<FavoriteFolder> folders) async {
    if (failWrite) throw StateError('Disk unavailable');
    stored = folders;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'folders survive reload, preserve exact searches and do not duplicate contractors',
    () async {
      final controller = FavoritesController(LocalFavoritesRepository());
      await controller.load();
      expect(suggestedFolderName(request), 'Свадьба · Алматы · Октябрь 2026');
      expect(
        folderContext(request.copyWith(category: 'Фотограф')),
        folderContext(request),
      );
      await controller.createAndSave(
        suggestedFolderName(request),
        contractor,
        request,
      );
      final id = controller.folders.single.id;
      await controller.add(id, contractor, request.copyWith(budget: 1));
      expect(controller.folders.single.entries, hasLength(1));
      expect(controller.folders.single.entries.single.request!.budget, 500000);
      await controller.rename(id, 'Наша свадьба');
      final reloaded = FavoritesController(LocalFavoritesRepository());
      await reloaded.load();
      expect(reloaded.folders.single.name, 'Наша свадьба');
      expect(
        reloaded.folders.single.entries.single.request!.toJson(),
        request.toJson(),
      );
      await reloaded.remove(id, contractor.id);
      expect(reloaded.folders.single.entries, isEmpty);
      await reloaded.delete(id);
      expect(await LocalFavoritesRepository().load(), isEmpty);
      controller.dispose();
      reloaded.dispose();
    },
  );

  test(
    'removing from one folder keeps another; catalog saves have no invented search',
    () async {
      final controller = FavoritesController(LocalFavoritesRepository());
      await controller.load();
      await controller.createAndSave('Свадьба', contractor, request);
      await controller.createAndSave('На будущее', contractor, null);
      await controller.remove(controller.folders.first.id, contractor.id);
      expect(controller.contains(contractor.id), isTrue);
      expect(controller.folders.last.entries.single.request, isNull);
      await expectLater(
        controller.createAndSave(' на будущее ', contractor, null),
        throwsArgumentError,
      );
      expect(controller.folders, hasLength(2));
      controller.dispose();
    },
  );

  test(
    'failed write leaves displayed and stored favorites unchanged',
    () async {
      final repository = FailingRepository();
      final controller = FavoritesController(repository);
      await controller.load();
      await controller.createAndSave('Свадьба', contractor, request);
      repository.failWrite = true;
      await expectLater(
        controller.remove(controller.folders.single.id, contractor.id),
        throwsStateError,
      );
      expect(controller.contains(contractor.id), isTrue);
      expect(repository.stored.single.entries, hasLength(1));
      expect(controller.saving, isFalse);
      controller.dispose();
    },
  );

  test('invalid persisted data is not silently overwritten', () async {
    SharedPreferences.setMockInitialValues({
      LocalFavoritesRepository.storageKey: '{broken',
    });
    final controller = FavoritesController(LocalFavoritesRepository());
    await controller.load();
    expect(controller.loadError, isNotNull);
    await expectLater(
      controller.createAndSave('Новая', contractor, null),
      throwsStateError,
    );
    expect(
      (await SharedPreferences.getInstance()).getString(
        LocalFavoritesRepository.storageKey,
      ),
      '{broken',
    );
    controller.dispose();
  });
}
