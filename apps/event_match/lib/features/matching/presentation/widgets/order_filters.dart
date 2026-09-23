import 'package:flutter/material.dart';
import '../../domain/models.dart';

/// Draft lives only inside the dialog. Dismiss/cancel never changes applied filters.
class OrderFilters extends StatefulWidget {
  const OrderFilters({
    super.key,
    required this.catalog,
    required this.supportsPreferences,
    this.initial,
  });
  final List<Contractor> catalog;
  final bool supportsPreferences;
  final MatchRequest? initial;

  @override
  State<OrderFilters> createState() => _OrderFiltersState();
}

class _OrderFiltersState extends State<OrderFilters> {
  final form = GlobalKey<FormState>();
  late String city, category, format, language;
  late DateTime date;
  late final TextEditingController budget, hours, preferences;

  @override
  void initState() {
    super.initState();
    final r = widget.initial;
    city = r?.city ?? 'Алматы';
    category = r?.category ?? 'Ведущий';
    format = r?.format ?? 'свадьба';
    language = r?.language ?? 'Любой';
    date = r?.date ?? DateTime(2026, 10, 10);
    budget = TextEditingController(text: '${r?.budget ?? 1000000}');
    hours = TextEditingController(text: r?.hours?.toString() ?? '');
    preferences = TextEditingController(text: r?.preferences ?? '');
  }

  @override
  void dispose() {
    budget.dispose();
    hours.dispose();
    preferences.dispose();
    super.dispose();
  }

  Widget select(
    String label,
    String value,
    List<String> values,
    ValueChanged<String> update,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: values
          .map((v) => DropdownMenuItem(value: v, child: Text(v)))
          .toList(),
      onChanged: (v) {
        if (v != null) setState(() => update(v));
      },
    ),
  );

  void apply() {
    if (!form.currentState!.validate()) return;
    Navigator.of(context).pop(
      MatchRequest(
        city: city,
        date: date,
        category: category,
        format: format,
        budget: int.parse(budget.text.trim()),
        hours: hours.text.trim().isEmpty
            ? null
            : double.parse(hours.text.trim().replaceAll(',', '.')),
        language: language == 'Любой' ? null : language,
        preferences: preferences.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Условия события',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                tooltip: 'Закрыть без изменений',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Укажите условия — подберём до трёх подходящих подрядчиков.',
                  ),
                  const SizedBox(height: 24),
                  select(
                    'Кого ищем?',
                    category,
                    ({
                      category,
                      ...widget.catalog.expand((c) => c.categories),
                    }.toList()..sort()),
                    (v) => category = v,
                  ),
                  select('Город', city, const [
                    'Алматы',
                    'Астана',
                    'Зарубежье',
                  ], (v) => city = v),
                  select('Формат события', format, const [
                    'свадьба',
                    'той',
                    'корпоратив',
                    'конференция',
                    'юбилей',
                    'день рождения',
                  ], (v) => format = v),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(48, 52),
                    ),
                    icon: const Icon(Icons.calendar_today_outlined),
                    label: Text('Дата: ${date.day}.${date.month}.${date.year}'),
                    onPressed: () async {
                      final value = await showDatePicker(
                        context: context,
                        initialDate: date,
                        firstDate: DateTime(2026, 9, 23),
                        lastDate: DateTime(2026, 12, 31),
                      );
                      if (value != null && mounted) {
                        setState(() => date = value);
                      }
                    },
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    key: const Key('budget-input'),
                    controller: budget,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Бюджет, ₸',
                      helperText: 'На одного подрядчика',
                    ),
                    validator: (v) => (int.tryParse(v?.trim() ?? '') ?? 0) > 0
                        ? null
                        : 'Введите целое число больше нуля',
                  ),
                  const SizedBox(height: 16),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    initiallyExpanded:
                        widget.initial?.hours != null ||
                        widget.initial?.language != null ||
                        (widget.initial?.preferences.isNotEmpty ?? false),
                    title: const Text('Дополнительные пожелания'),
                    children: [
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: hours,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Длительность, ч',
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return null;
                          final n = double.tryParse(
                            v.trim().replaceAll(',', '.'),
                          );
                          return n != null && n.isFinite && n > 0
                              ? null
                              : 'Введите число больше нуля';
                        },
                      ),
                      const SizedBox(height: 20),
                      select('Язык', language, const [
                        'Любой',
                        'русский',
                        'казахский',
                        'английский',
                      ], (v) => language = v),
                      TextFormField(
                        controller: preferences,
                        minLines: 3,
                        maxLines: 6,
                        maxLength: 1000,
                        decoration: const InputDecoration(
                          labelText: 'Что для вас важно?',
                          alignLabelWithHint: true,
                          hintText: 'Камерное событие, спокойное ведение…',
                        ),
                      ),
                      if (!widget.supportsPreferences)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 16),
                          child: Text(
                            'Текстовые пожелания пока не учитываются в подборе.',
                          ),
                        ),
                      if (widget.supportsPreferences)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 16),
                          child: Text(
                            'Пожелания сопоставляются со словами описания; это не проверка всех смысловых требований.',
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Доступны даты с 23 сентября по 31 декабря 2026 года.',
                  ),
                ],
              ),
            ),
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const Key('apply-filters'),
              onPressed: apply,
              icon: const Icon(Icons.check),
              label: const Text('Применить и подобрать'),
            ),
          ),
        ),
      ],
    ),
  );
}
