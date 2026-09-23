import 'package:flutter/foundation.dart';
import '../data/favorites_repository.dart';
import '../domain/favorites.dart';
import '../domain/models.dart';

class FavoritesController extends ChangeNotifier {
  FavoritesController(this.repository);
  final FavoritesRepository repository;
  List<FavoriteFolder> _folders = const [];
  List<FavoriteFolder> get folders => _folders;
  bool loading = true, saving = false;
  String? loadError;
  bool _disposed = false;
  int _sequence = 0;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> load() async {
    loading = true;
    loadError = null;
    _notify();
    try {
      _folders = List.unmodifiable(await repository.load());
    } catch (_) {
      loadError =
          'Не удалось открыть избранное. Повторите загрузку — сохранённые папки не будут перезаписаны.';
    } finally {
      loading = false;
      _notify();
    }
  }

  bool contains(String contractorId) =>
      _folders.any((f) => f.entries.any((e) => e.contractorId == contractorId));

  Future<void> _commit(List<FavoriteFolder> next) async {
    if (loading || saving || loadError != null) {
      throw StateError('Favorites unavailable');
    }
    saving = true;
    _notify();
    try {
      await repository.save(next);
      _folders = List.unmodifiable(next);
    } finally {
      saving = false;
      _notify();
    }
  }

  String _validName(String value, {String? except}) {
    final name = value.trim();
    if (name.isEmpty || name.length > 80) {
      throw ArgumentError('Название должно содержать от 1 до 80 символов');
    }
    if (_folders.any(
      (f) => f.id != except && f.name.toLowerCase() == name.toLowerCase(),
    )) {
      throw ArgumentError('Папка с таким названием уже есть');
    }
    return name;
  }

  Future<void> createAndSave(
    String name,
    Contractor contractor,
    MatchRequest? request,
  ) async {
    final folder = FavoriteFolder(
      id: '${DateTime.now().microsecondsSinceEpoch}-${_sequence++}',
      name: _validName(name),
      contextKey: folderContext(request),
      entries: [
        FavoriteEntry(
          contractorId: contractor.id,
          name: contractor.name,
          request: request,
        ),
      ],
    );
    await _commit([..._folders, folder]);
  }

  Future<void> add(
    String folderId,
    Contractor contractor,
    MatchRequest? request,
  ) async {
    final folder = _folders.firstWhere((f) => f.id == folderId);
    // Idempotent add; reopening the picker does not overwrite the saved search.
    if (folder.entries.any((e) => e.contractorId == contractor.id)) return;
    await _commit([
      for (final f in _folders)
        f.id == folderId
            ? f.copyWith(
                entries: [
                  ...f.entries,
                  FavoriteEntry(
                    contractorId: contractor.id,
                    name: contractor.name,
                    request: request,
                  ),
                ],
              )
            : f,
    ]);
  }

  Future<void> remove(String folderId, String contractorId) => _commit([
    for (final f in _folders)
      f.id == folderId
          ? f.copyWith(
              entries: f.entries
                  .where((e) => e.contractorId != contractorId)
                  .toList(),
            )
          : f,
  ]);

  Future<void> rename(String folderId, String value) {
    final name = _validName(value, except: folderId);
    return _commit([
      for (final f in _folders) f.id == folderId ? f.copyWith(name: name) : f,
    ]);
  }

  Future<void> delete(String folderId) =>
      _commit(_folders.where((f) => f.id != folderId).toList());

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
