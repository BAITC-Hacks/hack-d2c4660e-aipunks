import 'package:flutter/foundation.dart';
import '../data/catalog_repository.dart';
import '../data/local_recommendation_service.dart';
import '../domain/models.dart';
import '../domain/recommendation_service.dart';
import '../domain/alternative_dates.dart';

enum SearchStatus { idle, searching, success, failure }

class MatchingController extends ChangeNotifier {
  MatchingController(
    this.repository, {
    RecommendationService? service,
    this.datePolicy = const MatchDatePolicy.demo(),
  }) : service = service ?? LocalRecommendationService(repository);
  final CatalogRepository repository;
  final RecommendationService service;
  final MatchDatePolicy datePolicy;
  List<Contractor> catalog = [];
  MatchResult? result;
  MatchRequest? lastRequest;
  List<AlternativeDate> dateOptions = const [];
  SearchStatus status = SearchStatus.idle;
  bool loading = false;
  String? error;
  String? searchError;
  bool _disposed = false;
  int _generation = 0;

  Future<void> load() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      catalog = await repository.load();
    } catch (_) {
      error =
          'Не удалось прочитать каталог. Проверьте JSONL и повторите загрузку.';
    } finally {
      loading = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> search(MatchRequest request) async {
    final generation = ++_generation;
    lastRequest = request.normalized();
    status = SearchStatus.searching;
    searchError = null;
    result = null;
    dateOptions = const [];
    notifyListeners();
    try {
      request.validate(datePolicy: datePolicy);
      dateOptions = datePolicy.isLive
          ? const []
          : alternativeDates(catalog, request);
      notifyListeners();
      final response = await service
          .recommend(request)
          .timeout(const Duration(seconds: 10));
      if (_disposed || generation != _generation) return;
      result = response;
      status = SearchStatus.success;
    } catch (_) {
      if (_disposed || generation != _generation) return;
      searchError =
          'Не удалось выполнить подбор. Проверьте условия и попробуйте ещё раз.';
      status = SearchStatus.failure;
    }
    if (!_disposed && generation == _generation) notifyListeners();
  }

  void clearResult() {
    if (status == SearchStatus.idle) return;
    ++_generation; // A late response must not overwrite edited order parameters.
    result = null;
    lastRequest = null;
    dateOptions = const [];
    searchError = null;
    status = SearchStatus.idle;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    super.dispose();
  }
}
