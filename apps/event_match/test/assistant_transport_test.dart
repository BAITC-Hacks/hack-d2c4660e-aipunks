import 'package:flutter_test/flutter_test.dart';
import 'package:event_match/features/assistant/data/firebase_assistant_service.dart';
import 'package:event_match/features/assistant/domain/assistant_models.dart';
import 'package:event_match/features/matching/domain/models.dart';

class _Transport implements AssistantTransport {
  _Transport(this.response);
  final Map<String, dynamic> response;
  String? name;
  Map<String, Object?>? input;
  @override
  Future<Map<String, dynamic>> call(
    String name,
    Map<String, Object?> input,
  ) async {
    this.name = name;
    this.input = input;
    return response;
  }
}

Map<String, dynamic> resultJson() => {
  'outcome': 'matched',
  'summary': 'Подходит один профиль.',
  'preliminary': true,
  'unchecked': ['Дата не проверена'],
  'recommendations': [
    {
      'contractor': {
        'id': 'fixture-1',
        'anon_name': 'Тестовый фотограф',
        'city': 'Астана',
        'categories': ['Фотограф'],
        'price_from_kzt': 250000,
        'event_formats': ['свадьба'],
        'languages': ['русский'],
        'busy_dates': [],
        'max_hours': 8,
        'description': 'Помогает парам перед камерой.',
        'synthetic': true,
        'city_imputed': false,
        'price_imputed': true,
      },
      'explanation': 'В профиле: «Помогает парам перед камерой.»',
      'unchecked': ['Нужно уточнить срок выдачи фото'],
      'evidence': [
        {
          'feature_id': 'posing_help',
          'quote': 'Помогает парам перед камерой.',
          'status': 'supported',
        },
      ],
    },
  ],
};

void main() {
  test(
    'callable DTO preserves partial state, typed action and evidence',
    () async {
      const brief = AssistantBrief(
        city: 'Астана',
        category: 'Фотограф',
        eventFormat: 'свадьба',
        budgetKzt: 300000,
      );
      final transport = _Transport({
        'brief': brief.toJson(),
        'message': 'На какую дату?',
        'actions': [
          {
            'id': 'date',
            'label': 'Выбрать дату',
            'type': 'pick_date',
            'field': 'date',
          },
        ],
        'question_field': 'date',
        'result': resultJson(),
        'mode': 'ai',
        'warnings': [],
        'dataset_version': 'test-v1',
        'algorithm_version': 'test-rank-v1',
      });
      final response = await FirebaseAssistantService(transport).send(
        brief: brief,
        action: const AssistantAction(
          id: 'manual:show',
          label: 'Показать',
          type: 'show_results',
        ),
        history: [
          for (var i = 0; i < 15; i++)
            AssistantMessage(role: 'user', text: 'Сообщение $i'),
        ],
      );
      expect(transport.name, 'assistantTurn');
      expect(transport.input!['source'], 'demo');
      expect(transport.input!.containsKey('message'), false);
      expect((transport.input!['history'] as List).length, 12);
      expect((transport.input!['brief'] as Map)['date'], isNull);
      expect(response.brief.budgetKzt, 300000);
      expect(response.result!.preliminary, true);
      expect(
        response.result!.recommendations.single.contractor.priceImputed,
        true,
      );
      expect(
        response.result!.recommendations.single.evidence.single.quote,
        'Помогает парам перед камерой.',
      );
      expect(response.actions.single.field, 'date');
    },
  );

  test(
    'live callable explicitly selects live data and allows 25 seconds',
    () async {
      final transport = _Transport({
        'brief': const AssistantBrief().toJson(),
        'message': 'Кого ищете?',
      });
      final service = FirebaseAssistantService(transport, source: 'live');
      await service.send(brief: const AssistantBrief(), message: 'Фотограф');
      expect(transport.input!['source'], 'live');
      expect(service.timeout, const Duration(seconds: 25));
    },
  );

  test(
    'legacy adapter carries unchecked conditions into visible copy',
    () async {
      final transport = _Transport(resultJson());
      final response = await FirebaseRecommendationService(transport).recommend(
        MatchRequest(
          city: 'Астана',
          category: 'Фотограф',
          format: 'свадьба',
          date: DateTime(2026, 11, 14),
          budget: 300000,
        ),
      );
      expect(transport.name, 'recommendContractors');
      expect(response.summary, contains('Предварительная подборка'));
      expect(
        response.recommendations.single.explanation,
        contains('Нужно уточнить срок выдачи фото'),
      );
    },
  );
}
