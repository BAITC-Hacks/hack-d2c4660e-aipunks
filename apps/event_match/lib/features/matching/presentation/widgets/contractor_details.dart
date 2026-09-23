import 'package:event_match/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import '../../domain/models.dart';
import 'ai_explanation.dart';
import 'side_panel.dart';
import '../../../../app/communication_scope.dart';
import 'package:url_launcher/url_launcher.dart';

Future<void> showContractorDetails(
  BuildContext context, {
  required Contractor contractor,
  String? explanation,
  bool generated = false,
  String? source,
  ExplanationKind explanationKind = ExplanationKind.matching,
  List<String> unchecked = const [],
  Recommendation? recommendation,
}) => showSidePanel<void>(
  context,
  barrierLabel: tr(context, 'Закрыть профиль'),
  builder: (context) => ContractorDetails(
    contractor: contractor,
    explanation: explanation,
    generated: generated,
    source: source,
    explanationKind: explanationKind,
    unchecked: unchecked,
    recommendation: recommendation,
  ),
);

class ContractorDetails extends StatelessWidget {
  const ContractorDetails({
    super.key,
    required this.contractor,
    this.explanation,
    this.generated = false,
    this.source,
    this.explanationKind = ExplanationKind.matching,
    this.unchecked = const [],
    this.recommendation,
  });
  final Contractor contractor;
  final String? explanation;
  final bool generated;
  final String? source;
  final ExplanationKind explanationKind;
  final List<String> unchecked;
  final Recommendation? recommendation;

  @override
  Widget build(BuildContext context) {
    final c = contractor;
    final theme = Theme.of(context);
    final text = explanation ?? recommendation?.explanation;
    final limitations = {...unchecked, ...?recommendation?.unchecked}.toList();
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
                tooltip: trNullable(context, 'Закрыть профиль'),
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
                  if (text != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 24),
                      child: AiExplanation(
                        text: text,
                        kind: explanationKind,
                        source: recommendation?.source ?? source,
                        generated: generated,
                      ),
                    ),
                  if (limitations.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 24),
                      child: ExplanationLimitations(items: limitations),
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
                              ? c.isLive
                                    ? 'Длительность не указана'
                                    : 'Без привязки к часам присутствия'
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
                             Text(
                              tr(context, 'В данных недостаточно отличий — не считаем этот вариант уникально лучшим.'),
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
                          c.isLive
                              ? 'Опубликованный профиль подрядчика'
                              : c.synthetic
                              ? (c.id.startsWith('DEMO-')
                                    ? 'Демонстрационный профиль · добавлен нами'
                                    : 'Синтетический профиль организаторов')
                              : 'Анонимизированный профиль',
                        ),
                        if (c.priceImputed)
                           Text(tr(context, 'Цена заполнена при подготовке датасета')),
                        if (c.cityImputed)
                           Text(tr(context, 'Город заполнен при подготовке датасета')),
                        const SizedBox(height: 8),
                        Text(
                          c.isLive
                              ? 'Доступность проверяется по актуальному календарю. Переписка не является бронированием.'
                              : 'Демонстрационная анкета не принадлежит зарегистрированному подрядчику. Переписка и бронирование недоступны.',
                        ),
                      ],
                    ),
                  ),
                  if (c.isLive)
                    section(
                      'Контакты и портфолио',
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SelectableText(c.contact),
                          for (final url in c.portfolioUrls)
                            TextButton.icon(
                              onPressed: () async {
                                final uri = Uri.tryParse(url);
                                if (uri != null && uri.scheme == 'https') {
                                  await launchUrl(uri);
                                }
                              },
                              icon: const Icon(Icons.open_in_new, size: 18),
                              label: Text(url),
                            ),
                          const SizedBox(height: 12),
                          FilledButton.tonalIcon(
                            onPressed:
                                CommunicationScope.maybeOf(context) == null
                                ? null
                                : () => CommunicationScope.maybeOf(
                                    context,
                                  )!.openMessages(context, c),
                            icon: const Icon(Icons.chat_bubble_outline),
                            label:  Text(tr(context, 'Написать подрядчику')),
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
