import '../../../core/local_api.dart';
import '../domain/assistant_models.dart';
import '../domain/assistant_service.dart';

class ApiAssistantService implements AssistantService {
  ApiAssistantService(this.api);
  final LocalApi api;
  @override
  bool get supportsFreeText => true;
  @override
  Future<AssistantTurn> send({
    required AssistantBrief brief,
    String? message,
    AssistantAction? action,
    List<AssistantMessage> history = const [],
  }) async {
    try {
      return AssistantTurn.fromJson(
        await api.post('/v1/assistant', {
              'brief': brief.toJson(),
              'message': ?message,
              if (action != null) 'action': action.toJson(),
              'history': history
                  .skip(history.length > 4 ? history.length - 4 : 0)
                  .map((m) => m.toJson())
                  .toList(),
            }, envelope: false)
            as Map<String, dynamic>,
      );
    } on LocalApiException catch (e) {
      throw AssistantServiceException(e.message);
    }
  }
}
