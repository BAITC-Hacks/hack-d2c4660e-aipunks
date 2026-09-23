import 'dart:convert';
import 'package:http/http.dart' as http;
import '../domain/models.dart';
import '../domain/catalog_version.dart';
import 'catalog_repository.dart';

/// SQLite-backed catalog via local API; bundled snapshot is an offline fallback.
class ApiCatalogRepository implements CatalogRepository {
  ApiCatalogRepository({
    required this.baseUrl,
    this.token = '',
    http.Client? client,
    CatalogRepository? fallback,
  }) : client = client ?? http.Client(),
       fallback = fallback ?? AssetCatalogRepository();
  final String baseUrl, token;
  final http.Client client;
  final CatalogRepository fallback;
  List<Contractor>? _snapshot;
  @override
  Future<List<Contractor>> load() async {
    if (_snapshot != null) return _snapshot!;
    try {
      final response = await client
          .get(
            Uri.parse('$baseUrl/v1/catalog'),
            headers: {if (token.isNotEmpty) 'X-Local-Token': token},
          )
          .timeout(const Duration(seconds: 2));
      if (response.statusCode != 200 || response.body.length > 2000000) {
        throw const FormatException('Catalog unavailable');
      }
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final profiles = (body['profiles'] as List)
          .map((p) => Contractor.fromJson(p as Map<String, dynamic>))
          .toList();
      if (profiles.isEmpty ||
          profiles.length > 1000 ||
          profiles.map((p) => p.id).toSet().length != profiles.length ||
          catalogVersion(profiles) != body['catalog_version']) {
        throw const FormatException('Invalid snapshot');
      }
      _snapshot = List.unmodifiable(profiles);
    } catch (_) {
      _snapshot = List.unmodifiable(await fallback.load());
    }
    return _snapshot!;
  }
}
