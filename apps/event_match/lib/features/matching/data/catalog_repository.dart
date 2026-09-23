import 'dart:convert';
import 'package:flutter/services.dart';
import '../domain/models.dart';

abstract interface class CatalogRepository {
  Future<List<Contractor>> load();
}

class AssetCatalogRepository implements CatalogRepository {
  AssetCatalogRepository({this.path = 'assets/data/catalog.jsonl'});
  final String path;
  @override
  Future<List<Contractor>> load() async {
    final text = await rootBundle.loadString(path);
    final rows = const LineSplitter()
        .convert(text)
        .where((line) => line.trim().isNotEmpty);
    final catalog = rows
        .map(
          (line) =>
              Contractor.fromJson(jsonDecode(line) as Map<String, dynamic>),
        )
        .toList(growable: false);
    if (catalog.map((c) => c.id).toSet().length != catalog.length) {
      throw const FormatException('Duplicate contractor IDs');
    }
    return catalog;
  }
}
