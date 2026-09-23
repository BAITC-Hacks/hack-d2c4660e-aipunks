import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../domain/favorites.dart';

abstract interface class FavoritesRepository {
  Future<List<FavoriteFolder>> load();
  Future<void> save(List<FavoriteFolder> folders);
}

class LocalFavoritesRepository implements FavoritesRepository {
  static const storageKey = 'event_match.favorites.v1';
  @override
  Future<List<FavoriteFolder>> load() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final raw = prefs.getString(storageKey);
    if (raw == null) return [];
    final json = jsonDecode(raw) as Map<String, dynamic>;
    if (json['version'] != 1) {
      throw const FormatException('Unknown favorites version');
    }
    final folders = (json['folders'] as List)
        .map((e) => FavoriteFolder.fromJson(e as Map<String, dynamic>))
        .toList();
    if (folders.map((f) => f.id).toSet().length != folders.length) {
      throw const FormatException('Duplicate folder IDs');
    }
    return folders;
  }

  @override
  Future<void> save(List<FavoriteFolder> folders) async {
    final prefs = await SharedPreferences.getInstance();
    final success = await prefs.setString(
      storageKey,
      jsonEncode({
        'version': 1,
        'folders': folders.map((f) => f.toJson()).toList(),
      }),
    );
    if (!success) throw StateError('Favorites could not be saved');
  }
}
