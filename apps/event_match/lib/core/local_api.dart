import 'dart:convert';
import 'package:http/http.dart' as http;

class LocalApiException implements Exception {
  const LocalApiException(this.message, this.status, this.details);
  final String message;
  final int status;
  final Map<String, dynamic> details;
  @override
  String toString() => message;
}

/// Session credentials stay in memory, not in URLs, logs, assets or preferences.
class LocalApi {
  LocalApi({required this.baseUrl, this.localToken = '', http.Client? client})
    : client = client ?? http.Client();
  final String baseUrl, localToken;
  final http.Client client;
  String? sessionToken;
  Future<dynamic> post(
    String path,
    Map<String, dynamic> body, {
    bool envelope = true,
  }) async {
    final response = await client
        .post(
          Uri.parse('$baseUrl$path'),
          headers: {
            'Content-Type': 'application/json',
            if (localToken.isNotEmpty) 'X-Local-Token': localToken,
            if (sessionToken != null) 'Authorization': 'Bearer $sessionToken',
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 10));
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200) {
      final error = data['error'] as String?;
      throw LocalApiException(
        error != null && RegExp('[А-Яа-я]').hasMatch(error)
            ? error
            : response.statusCode == 429
            ? 'Слишком много запросов. Подождите минуту.'
            : 'Сервис сейчас недоступен. Повторите позже.',
        response.statusCode,
        data,
      );
    }
    return envelope ? data['data'] : data;
  }

  Future<dynamic> workspace(
    String op, [
    Map<String, dynamic> data = const {},
  ]) => post('/v1/workspace', {'op': op, ...data});
  void dispose() => client.close();
}
