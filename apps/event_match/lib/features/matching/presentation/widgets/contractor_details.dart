import 'package:flutter/material.dart';
import '../../domain/models.dart';
import 'ai_explanation.dart';

Future<void> showContractorDetails(
  BuildContext context, {
  required Contractor contractor,
  String? explanation,
  bool generated = false,
  Recommendation? recommendation,
}) => showDialog<void>(
  context: context,
  barrierLabel: 'Закрыть профиль',
  builder: (context) => Dialog(
    alignment: Alignment.centerRight,
    insetPadding: const EdgeInsets.all(24),
    child: SizedBox(
      width: 640,
      height: MediaQuery.sizeOf(context).height - 48,
      child: ContractorDetails(
        contractor: contractor,
        explanation: explanation,
        generated: generated,
        recommendation: recommendation,
      ),
    ),
  ),
);

class ContractorDetails extends StatelessWidget {
  const ContractorDetails({
    super.key,
    required this.contractor,
    this.explanation,
    this.generated = false,
    this.recommendation,
  });
  final Contractor contractor;
  final String? explanation;
  final bool generated;
  final Recommendation? recommendation;

  @override
  Widget build(BuildContext context) {
    final c = contractor;
    final theme = Theme.of(context);
    Widget section(String title, Widget child) => Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 16, 16),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Профиль подрядчика',
                  style: theme.textTheme.titleLarge,
                ),
              ),
              IconButton(
                autofocus: true,
                tooltip: 'Закрыть профиль',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: Scrollbar(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText(c.name, style: theme.textTheme.headlineMedium),
                  const SizedBox(height: 8),
                  Text('${c.categories.join(' · ')} · ${c.city}'),
                  const SizedBox(height: 24),
                  if (explanation != null)
                    section(
                      'Краткое объяснение',
                      AiExplanation(text: explanation!, generated: generated),
                    ),
                  section(
                    'Условия и услуги',
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Цена от ${c.price.toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]} ')} ₸ · предварительная',
                        ),
                        const SizedBox(height: 8),
                        Text('Языки: ${c.languages.join(', ')}'),
                        const SizedBox(height: 8),
                        Text(
                          c.maxHours == null
                              ? 'Без привязки к часам присутствия'
                              : 'Продолжительность: до ${c.maxHours!.toString().replaceFirst(RegExp(r'\.0$'), '')} ч',
                        ),
                        const SizedBox(height: 8),
                        Text('Все форматы: ${c.formats.join(', ')}'),
                      ],
                    ),
                  ),
                  section(
                    'Полное описание',
                    SelectableText(
                      c.description,
                      style: theme.textTheme.bodyLarge?.copyWith(height: 1.6),
                    ),
                  ),
                  if (recommendation != null)
                    section(
                      'Как рассчитан подбор',
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Оценка соответствия: ${recommendation!.score.toStringAsFixed(3)} (не рейтинг качества)',
                          ),
                          const SizedBox(height: 12),
                          for (final entry in recommendation!.features.entries)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Text(
                                '${const {'budget': 'Бюджет', 'focus': 'Фокус форматов', 'description': 'Совпадения описания', 'language': 'Языки', 'hours': 'Запас часов', 'provenance': 'Множитель происхождения данных'}[entry.key] ?? entry.key}: ${entry.value.toStringAsFixed(3)}',
                              ),
                            ),
                          if (recommendation!.equivalent)
                            const Text(
                              'В данных недостаточно отличий — не считаем этот вариант уникально лучшим.',
                            ),
                        ],
                      ),
                    ),
                  section(
                    'О данных профиля',
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          c.synthetic
                              ? (c.id.startsWith('DEMO-')
                                    ? 'Демонстрационный профиль · добавлен нами'
                                    : 'Синтетический профиль организаторов')
                              : 'Анонимизированный профиль',
                        ),
                        if (c.priceImputed)
                          const Text('Цена заполнена при подготовке датасета'),
                        if (c.cityImputed)
                          const Text('Город заполнен при подготовке датасета'),
                        const SizedBox(height: 8),
                        const Text(
                          'Доступность проверяется при подборе по дате. Бронирование и переписка пока не подключены.',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
