import 'assistant_models.dart';

abstract interface class AssistantService {
  bool get supportsFreeText;
  Future<AssistantTurn> send({
    required AssistantBrief brief,
    String? message,
    AssistantAction? action,
    List<AssistantMessage> history = const [],
  });
}

class AssistantServiceException implements Exception {
  const AssistantServiceException(this.message);
  final String message;
  @override
  String toString() => message;
}
