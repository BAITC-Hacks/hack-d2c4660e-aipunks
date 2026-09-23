import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../matching/domain/models.dart';
import '../../matching/domain/recommendation_service.dart';
import '../domain/assistant_models.dart';
import '../domain/assistant_service.dart';

abstract interface class AssistantTransport {
  Future<Map<String, dynamic>> call(String name, Map<String, Object?> input);
}

/// Firebase owns transport and authentication. No LLM secret enters Flutter.
class AssistantBackend implements AssistantTransport {
  AssistantBackend({
    FirebaseFunctions? functions,
    FirebaseAuth? auth,
    this.timeout = const Duration(seconds: 25),
  }) : functions =
           functions ??
           FirebaseFunctions.instanceFor(
             region: const String.fromEnvironment(
               'ASSISTANT_FUNCTIONS_REGION',
               defaultValue: 'us-central1',
             ),
           ),
       auth = auth ?? FirebaseAuth.instance;
  final FirebaseFunctions functions;
  final FirebaseAuth auth;
  final Duration timeout;

  @override
  Future<Map<String, dynamic>> call(
    String name,
    Map<String, Object?> input,
  ) async {
    try {
      if (auth.currentUser == null) await auth.signInAnonymously();
      final result = await functions
          .httpsCallable(name, options: HttpsCallableOptions(timeout: timeout))
          .call<Map<String, dynamic>>(input);
      return jsonMap(result.data);
    } on FirebaseAuthException catch (_) {
      throw const AssistantServiceException(
        'Не удалось подключить помощника. Проверьте доступность входа и повторите; можно продолжить подбор кнопками.',
      );
    } on FirebaseFunctionsException catch (e) {
      throw AssistantServiceException(switch (e.code) {
        'failed-precondition' =>
          'AI-сервис ещё не настроен. Условия сохранены — продолжите кнопками или повторите позже.',
        'resource-exhausted' =>
          'Достигнут лимит запросов. Подождите минуту или продолжите кнопками.',
        'permission-denied' =>
          'Доступ к помощнику для этого аккаунта ограничен.',
        'unauthenticated' =>
          'Не удалось подтвердить сеанс. Повторите подключение.',
        'invalid-argument' =>
          'Не удалось применить условие. Проверьте дату, сумму и выбранные варианты.',
        _ =>
          'AI-сервис сейчас недоступен. Условия сохранены — повторите или продолжите кнопками.',
      });
    }
  }
}

class FirebaseAssistantService implements AssistantService {
  FirebaseAssistantService(
    this.backend, {
    this.source = 'demo',
    this.timeout = const Duration(seconds: 25),
  });
  final AssistantTransport backend;
  final String source;
  final Duration timeout;
  @override
  bool get supportsFreeText => true;
  @override
  Future<AssistantTurn> send({
    required AssistantBrief brief,
    String? message,
    AssistantAction? action,
    List<AssistantMessage> history = const [],
  }) async {
    final response = await backend
        .call('assistantTurn', {
          'source': source,
          'brief': brief.toJson(),
          'message': ?message,
          if (action != null) 'action': action.toJson(),
          'history': history
              .skip(history.length > 12 ? history.length - 12 : 0)
              .map((m) => m.toJson())
              .toList(),
        })
        .timeout(timeout);
    return AssistantTurn.fromJson(response);
  }
}

/// Optional adapter for the existing confirmed demo request form.
class FirebaseRecommendationService implements RecommendationService {
  FirebaseRecommendationService(this.backend);
  final AssistantTransport backend;
  @override
  bool get supportsPreferences => true;
  @override
  Future<MatchResult> recommend(MatchRequest request) async {
    request.validate();
    final response = await backend.call(
      'recommendContractors',
      request.toJson(),
    );
    final result = AssistantResult.fromJson(response);
    return MatchResult(
      result.outcome,
      [
        for (final r in result.recommendations)
          Recommendation(
            r.contractor,
            '${r.explanation}${r.unchecked.isEmpty ? '' : ' Нужно уточнить: ${r.unchecked.join('; ')}.'}',
          ),
      ],
      '${result.summary}${result.preliminary ? ' Предварительная подборка: ${result.unchecked.join('; ')}.' : ''}',
    );
  }
}
