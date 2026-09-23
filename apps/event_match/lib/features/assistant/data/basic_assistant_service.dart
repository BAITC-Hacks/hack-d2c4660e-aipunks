import '../../matching/data/catalog_repository.dart';
import '../../matching/domain/models.dart';
import '../../matching/domain/catalog_version.dart';
import '../domain/assistant_models.dart';
import '../domain/assistant_service.dart';

/// Explicit manual mode. Never pretends to understand free text or preferences.
class BasicAssistantService implements AssistantService {
  BasicAssistantService(this.repository);
  final CatalogRepository repository;
  @override
  bool get supportsFreeText => false;

  @override
  Future<AssistantTurn> send({
    required AssistantBrief brief,
    String? message,
    AssistantAction? action,
    List<AssistantMessage> history = const [],
  }) async {
    if (message != null) {
      throw const AssistantServiceException(
        'Свободный текст доступен после подключения AI-сервера. Сейчас можно задать условия кнопками.',
      );
    }
    final catalog = await repository.load();
    var b = _apply(brief, action);
    _validate(b);
    final result = b.canRecommend ? _match(catalog, b) : null;
    String? field;
    String question;
    final actions = <AssistantAction>[];
    if (b.city == null) {
      field = 'city';
      question = 'В каком городе проходит событие?';
      actions.addAll(
        _options('city', catalog.map((c) => c.city).toSet().toList()..sort()),
      );
    } else if (b.category == null) {
      field = 'category';
      question = 'Кого подбираем для вашего события?';
      actions.addAll(
        _options('category', const ['Ведущий', 'Фотограф', 'Банкетный зал']),
      );
      actions.add(
        const AssistantAction(
          id: 'manual:categories',
          label: 'Все категории',
          type: 'pick_field',
          field: 'category',
        ),
      );
    } else if (b.eventFormat == null) {
      field = 'event_format';
      question = 'Какое мероприятие планируете?';
      actions.addAll(
        _options('event_format', const [
          'свадьба',
          'корпоратив',
          'день рождения',
        ]),
      );
      actions.add(
        const AssistantAction(
          id: 'manual:formats',
          label: 'Другой формат',
          type: 'pick_field',
          field: 'event_format',
        ),
      );
    } else if (result!.outcome != MatchOutcome.matched) {
      question = result.summary;
      for (final (key, label) in [
        ('date', 'Изменить дату'),
        ('budget_kzt', 'Изменить бюджет'),
        ('city', 'Другой город'),
        ('category', 'Другая категория'),
      ]) {
        actions.add(
          AssistantAction(
            id: 'manual:edit:$key',
            label: label,
            type: key == 'date'
                ? 'pick_date'
                : key == 'budget_kzt'
                ? 'pick_budget'
                : 'pick_field',
            field: key,
          ),
        );
      }
    } else if (b.date == null && !b.skippedFields.contains('date')) {
      field = 'date';
      question = 'На какую дату проверить доступность?';
      actions.addAll(const [
        AssistantAction(
          id: 'manual:date',
          label: 'Выбрать дату',
          type: 'pick_date',
          field: 'date',
        ),
        AssistantAction(
          id: 'manual:skip_date',
          label: 'Пока не знаю',
          type: 'skip_field',
          field: 'date',
        ),
      ]);
    } else if ((b.budgetKzt == null || b.budgetScope == 'event') &&
        !b.skippedFields.contains('budget_kzt')) {
      field = 'budget_kzt';
      question = b.budgetScope == 'event'
          ? 'Какую часть общего бюджета выделить этому подрядчику?'
          : 'Какой бюджет на этого подрядчика?';
      final prices =
          catalog
              .where(
                (c) =>
                    c.city == b.city &&
                    c.categories.contains(b.category) &&
                    c.formats.contains(b.eventFormat),
              )
              .map((c) => c.price)
              .toSet()
              .toList()
            ..sort();
      if (prices.isNotEmpty) {
        for (final price in {prices.first, prices[prices.length ~/ 2]}) {
          actions.add(
            AssistantAction(
              id: 'manual:budget:$price',
              label: 'До $price ₸',
              type: 'set_field',
              field: 'budget_kzt',
              value: price,
            ),
          );
        }
      }
      actions.addAll(const [
        AssistantAction(
          id: 'manual:budget',
          label: 'Своя сумма',
          type: 'pick_budget',
          field: 'budget_kzt',
        ),
        AssistantAction(
          id: 'manual:skip_budget',
          label: 'Пока не знаю',
          type: 'skip_field',
          field: 'budget_kzt',
        ),
      ]);
    } else {
      question = result.summary;
      actions.addAll(const [
        AssistantAction(
          id: 'manual:date',
          label: 'Изменить дату',
          type: 'pick_date',
          field: 'date',
        ),
        AssistantAction(
          id: 'manual:budget',
          label: 'Изменить бюджет',
          type: 'pick_budget',
          field: 'budget_kzt',
        ),
        AssistantAction(
          id: 'manual:next',
          label: 'Следующий специалист',
          type: 'next_category',
        ),
      ]);
    }
    return AssistantTurn(
      brief: b,
      message: question,
      actions: actions,
      questionField: field,
      result: result,
      mode: 'basic',
      warnings: [
        'Подбор кнопками: проверяем условия, пожелания по стилю не анализируются.',
      ],
      datasetVersion: catalogVersion(catalog),
      algorithmVersion: 'basic-1',
    );
  }

  List<AssistantAction> _options(String field, List<String> values) => [
    for (final value in values)
      AssistantAction(
        id: 'manual:$field:$value',
        label: value,
        type: 'set_field',
        field: field,
        value: value,
      ),
  ];

  AssistantBrief _apply(AssistantBrief b, AssistantAction? a) {
    if (a == null || a.type == 'show_results') return b;
    final j = b.toJson();
    switch (a.type) {
      case 'set_field':
      case 'clear_field':
        if (!const [
          'city',
          'category',
          'event_format',
          'date',
          'budget_kzt',
          'hours',
          'language',
        ].contains(a.field)) {
          throw const AssistantServiceException(
            'Это условие нельзя изменить таким действием.',
          );
        }
        j[a.field!] = a.type == 'clear_field' ? null : a.value;
        j['skipped_fields'] = b.skippedFields
            .where((s) => s != a.field)
            .toList();
        if (a.field == 'budget_kzt') j['budget_scope'] = 'contractor';
      // Field edits correct one condition; next_category starts a fresh specialist.
      case 'skip_field':
        if (!const ['date', 'budget_kzt'].contains(a.field)) {
          throw const AssistantServiceException('Это условие нужно выбрать.');
        }
        j[a.field!] = null;
        j['skipped_fields'] = {...b.skippedFields, a.field!}.toList();
      case 'next_category':
        return AssistantBrief(
          city: b.city,
          date: b.date,
          eventFormat: b.eventFormat,
          category: a.value as String?,
        );
      case 'reject':
        final value = jsonMap(a.value);
        j['excluded_ids'] = {
          ...b.excludedIds,
          value['contractor_id'] as String,
        }.toList();
      case 'add_preference':
        j['preferences'] = [...b.preferences.map((p) => p.toJson()), a.value];
      case 'remove_preference':
        final index = (a.value as num).toInt();
        j['preferences'] = [
          for (var i = 0; i < b.preferences.length; i++)
            if (i != index) b.preferences[i].toJson(),
        ];
      case 'reset':
        return const AssistantBrief();
      default:
        throw const AssistantServiceException(
          'Выберите значение для этого условия.',
        );
    }
    return AssistantBrief.fromJson(j);
  }

  void _validate(AssistantBrief b) {
    for (final value in [b.city, b.category, b.eventFormat, b.language]) {
      if (value != null && (value.trim().isEmpty || value.length > 120)) {
        throw const AssistantServiceException(
          'Укажите короткое название условия.',
        );
      }
    }
    if ((b.budgetKzt != null &&
            (b.budgetKzt! <= 0 || b.budgetKzt! > 1000000000000)) ||
        (b.hours != null &&
            (!b.hours!.isFinite || b.hours! <= 0 || b.hours! > 168))) {
      throw const AssistantServiceException(
        'Проверьте бюджет и длительность: нужны положительные значения в допустимых пределах.',
      );
    }
    if (b.date != null) {
      final date = DateTime.tryParse(b.date!);
      if (date == null || dateKey(date) != b.date) {
        throw const AssistantServiceException('Введите существующую дату.');
      }
    }
  }

  AssistantResult _match(List<Contractor> catalog, AssistantBrief b) {
    final pool = catalog
        .where((c) => c.city == b.city && c.categories.contains(b.category))
        .toList();
    final unchecked = <String>[
      if (b.date == null)
        'Дата не проверена'
      else if (!b.dateInCalendar)
        'Дата за пределами календаря 23.09–31.12.2026',
      if (b.budgetKzt == null || b.budgetScope == 'event')
        'Бюджет подрядчика не задан',
      if (b.preferences.isNotEmpty)
        'Пожелания по описаниям не проверены в базовом режиме',
    ];
    final rejected = <String, int>{};
    final eligible = <Contractor>[];
    for (final c in pool) {
      final reason = b.dateInCalendar && c.busyDates.contains(b.date)
          ? 'заняты на дату'
          : b.budgetKzt != null &&
                b.budgetScope == 'contractor' &&
                c.price > b.budgetKzt!
          ? 'выше бюджета'
          : !c.formats.contains(b.eventFormat)
          ? 'не берут этот формат'
          : b.language != null && !c.languages.contains(b.language)
          ? 'не работают на выбранном языке'
          : b.hours != null && c.maxHours != null && c.maxHours! < b.hours!
          ? 'не подходят по длительности'
          : b.excludedIds.contains(c.id)
          ? 'вы исключили из подборки'
          : null;
      if (reason == null) {
        eligible.add(c);
      } else {
        rejected.update(reason, (n) => n + 1, ifAbsent: () => 1);
      }
    }
    eligible.sort((a, b) {
      final price = a.price.compareTo(b.price);
      return price == 0 ? a.id.compareTo(b.id) : price;
    });
    final reasons = rejected.entries
        .map((e) => '${e.value} — ${e.key}')
        .join('; ');
    final summary = pool.isEmpty
        ? 'В этом городе такой категории пока нет в каталоге.'
        : eligible.isEmpty
        ? 'Кандидаты есть, но никто не проходит по условиям. $reasons.'
        : 'Подходят ${eligible.length} из ${pool.length}; показано ${eligible.take(3).length}.'
              '${reasons.isEmpty ? '' : ' Исключены: $reasons.'}'
              '${eligible.length < 3 && reasons.isEmpty ? ' В этой категории города всего ${pool.length} профилей.' : ''}';
    return AssistantResult(
      outcome: pool.isEmpty
          ? MatchOutcome.categoryAbsent
          : eligible.isEmpty
          ? MatchOutcome.noEligible
          : MatchOutcome.matched,
      summary: summary,
      preliminary:
          unchecked.isNotEmpty ||
          (b.hours != null && eligible.take(3).any((c) => c.maxHours == null)),
      unchecked: unchecked,
      recommendations: [
        for (final c in eligible.take(3))
          AssistantRecommendation(
            contractor: c,
            unchecked: [
              ...unchecked,
              if (b.hours != null && c.maxHours == null)
                'Длительность не подтверждена',
            ],
            explanation:
                '${b.dateInCalendar ? 'Свободен по календарю ${b.date}; ' : ''}берёт формат «${b.eventFormat}», цена от ${c.price} ₸${b.budgetKzt != null && b.budgetScope == 'contractor' ? ' при бюджете ${b.budgetKzt} ₸' : ''}. В профиле: «${_excerpt(c.description)}».',
          ),
      ],
    );
  }

  String _excerpt(String text) {
    final clean = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (clean.length <= 180) return clean;
    final cut = clean.lastIndexOf(' ', 180);
    return '${clean.substring(0, cut > 0 ? cut : 180)}…';
  }
}
