import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../matching/data/catalog_repository.dart';
import '../../matching/domain/models.dart';
import '../domain/assistant_models.dart';
import '../domain/assistant_service.dart';

class AssistantController extends ChangeNotifier {
  AssistantController({
    required this.service,
    required this.basicService,
    required this.repository,
    this.timeout = const Duration(seconds: 25),
  }) : _initialService = service;
  final AssistantService _initialService;
  AssistantService service;
  final AssistantService basicService;
  final CatalogRepository repository;
  final Duration timeout;
  AssistantBrief brief = const AssistantBrief();
  AssistantTurn? turn;
  final List<AssistantMessage> messages = [];
  List<Contractor> catalog = [];
  bool busy = false;
  String? error;
  bool _disposed = false;
  int _generation = 0;
  String? _contextKey;
  String? get contextKey => _contextKey;
  int _contextRevision = 0;
  int get contextRevision => _contextRevision;
  _PendingTurn? _pending;
  final Stopwatch _session = Stopwatch()..start();
  bool _firstResult = false;
  final Map<String, int> _clarificationCounts = {};
  final List<Map<String, Object?>> events = [];

  void track(String event, [Map<String, Object?> details = const {}]) {
    // Session-only measurements, never persist conversation text or account data.
    events.add({
      'event': event,
      'elapsed_ms': _session.elapsedMilliseconds,
      ...details,
    });
  }

  Future<void> loadCatalog() async {
    try {
      final loaded = await repository.load();
      if (_disposed) return;
      catalog = loaded;
    } catch (_) {
      if (_disposed) return;
      error = 'Не удалось загрузить варианты. Повторите открытие помощника.';
    }
    notifyListeners();
  }

  void seedFromRequest(MatchRequest request) {
    replaceContext(
      AssistantBrief.fromRequest(request),
      'request:${jsonEncode(request.toJson())}',
    );
    track('applied_catalog_conditions_imported');
  }

  /// Stable route keys preserve refinements; changed external context invalidates
  /// pending turns and old recommendations before another request can run.
  /// Use [force] for explicit edits while preserving the originating route key.
  void replaceContext(AssistantBrief next, String key, {bool force = false}) {
    if (_disposed || (!force && _contextKey == key)) return;
    ++_generation;
    ++_contextRevision;
    _contextKey = key;
    brief = next;
    turn = null;
    messages.clear();
    busy = false;
    error = null;
    _pending = null;
    _firstResult = false;
    _clarificationCounts.clear();
    events.clear();
    _session.reset();
    track('context_replaced');
    notifyListeners();
  }

  Future<void> sendMessage(String text) async {
    final clean = text.trim();
    if (clean.isEmpty || _disposed) return;
    if (clean.length > 2000) {
      error = 'Сократите сообщение до 2000 символов.';
      notifyListeners();
      return;
    }
    await _submit(message: clean);
  }

  Future<void> act(AssistantAction action) async {
    if (action.type == 'reset') {
      reset();
      return;
    }
    track(
      action.type == 'reject' ? 'recommendation_rejected' : 'action_selected',
      {
        'type': action.type,
        'field': action.field,
        if (action.type == 'reject' && action.value is Map)
          'reason': (action.value as Map)['reason'],
      },
    );
    await _submit(action: action);
  }

  Future<void> _submit({String? message, AssistantAction? action}) async {
    if (_disposed) return;
    final history = messages
        .skip(messages.length > 12 ? messages.length - 12 : 0)
        .toList();
    _pending = _PendingTurn(brief, message, action, history);
    messages.add(
      AssistantMessage(role: 'user', text: message ?? action!.label),
    );
    await _run(_pending!);
  }

  Future<void> retry() async {
    final pending = _pending;
    if (pending != null && !_disposed) await _run(pending);
  }

  Future<void> _run(_PendingTurn pending) async {
    final generation = ++_generation;
    busy = true;
    error = null;
    notifyListeners();
    try {
      final response = await service
          .send(
            brief: pending.brief,
            message: pending.message,
            action: pending.action,
            history: pending.history,
          )
          .timeout(timeout);
      if (_disposed || generation != _generation) return;
      brief = response.brief;
      turn = response;
      messages.add(
        AssistantMessage(
          role: 'assistant',
          text: response.message,
          turn: response,
        ),
      );
      if (response.questionField != null) {
        final field = response.questionField!;
        final count = (_clarificationCounts[field] ?? 0) + 1;
        _clarificationCounts[field] = count;
        track('clarification_shown', {
          'field': field,
          'occurrence': count,
          'repeated': count > 1,
        });
      }
      if (response.result != null) {
        track(_firstResult ? 'results_updated' : 'first_result', {
          'count': response.result!.recommendations.length,
          'preliminary': response.result!.preliminary,
          'mode': response.mode,
        });
        _firstResult = true;
      }
      _pending = null;
    } on AssistantServiceException catch (e) {
      if (_disposed || generation != _generation) return;
      error = e.message;
    } on TimeoutException {
      if (_disposed || generation != _generation) return;
      error =
          'Ответ занимает дольше обычного. Условия сохранены — повторите или выберите подбор кнопками.';
    } catch (_) {
      if (_disposed || generation != _generation) return;
      error =
          'Помощник сейчас недоступен. Условия сохранены. Повторите или продолжите кнопками.';
    }
    if (_disposed || generation != _generation) return;
    busy = false;
    notifyListeners();
  }

  Future<void> useBasicMode() async {
    final pending = _pending;
    ++_generation;
    service = basicService;
    busy = false;
    error = null;
    _pending = null;
    track('basic_mode_selected');
    if (pending?.action != null) {
      // Apply the user's pending edit locally; a network failure must not drop it.
      _pending = pending;
      await _run(pending!);
      return;
    }
    await act(
      const AssistantAction(
        id: 'manual:show',
        label: 'Продолжить подбор кнопками',
        type: 'show_results',
      ),
    );
  }

  void reset() {
    ++_generation;
    ++_contextRevision;
    _contextKey = null;
    service = _initialService;
    brief = const AssistantBrief();
    turn = null;
    messages.clear();
    busy = false;
    error = null;
    _pending = null;
    _firstResult = false;
    _clarificationCounts.clear();
    events.clear();
    _session.reset();
    track('session_reset');
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    _session.stop();
    super.dispose();
  }
}

class _PendingTurn {
  const _PendingTurn(this.brief, this.message, this.action, this.history);
  final AssistantBrief brief;
  final String? message;
  final AssistantAction? action;
  final List<AssistantMessage> history;
}
