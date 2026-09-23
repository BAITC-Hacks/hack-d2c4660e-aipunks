import 'package:flutter/material.dart';
import '../../../../app/design_tokens.dart';
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
      itemHeight: null,
      borderRadius: BorderRadius.circular(16),
      icon: const Icon(Icons.keyboard_arrow_down_rounded),
      decoration: InputDecoration(labelText: label),
      selectedItemBuilder: (context) => values
          .map((v) => Text(v, maxLines: 1, overflow: TextOverflow.ellipsis))
          .toList(),
      items: values
          .map(
            (v) => DropdownMenuItem(
              value: v,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(v),
              ),
            ),
          )
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

  Widget sectionTitle(String number, String title) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$number /  ',
            style: const TextStyle(color: AppColors.primary),
          ),
          TextSpan(text: title),
        ],
      ),
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w700,
        height: 1.4,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => SafeArea(
    child: LayoutBuilder(
      builder: (context, constraints) {
        final inset = constraints.maxWidth < 400 ? 20.0 : 28.0;
        final compactHeight = constraints.maxHeight < 500;
        final textTheme = Theme.of(context).textTheme;
        return Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(inset, 16, 12, 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!compactHeight) ...[
                          Text(
                            'ПЕРСОНАЛЬНЫЙ ПОДБОР',
                            style: textTheme.labelSmall?.copyWith(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                        Text('Условия события', style: textTheme.titleLarge),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    tooltip: 'Закрыть без изменений',
                    style: IconButton.styleFrom(
                      backgroundColor: AppColors.canvas,
                      foregroundColor: AppColors.ink,
                      minimumSize: const Size(48, 48),
                    ),
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(inset, 24, inset, 28),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                child: Form(
                  key: form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: AppColors.lavender,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          'Расскажите о событии. Подберём до трёх подрядчиков '
                          'по вашей дате, бюджету и формату.',
                          style: textTheme.bodyMedium?.copyWith(
                            color: AppColors.ink,
                          ),
                        ),
                      ),
                      const SizedBox(height: 28),
                      sectionTitle('01', 'Ваше событие'),
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
                          minimumSize: const Size(48, 56),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 16,
                          ),
                          alignment: Alignment.centerLeft,
                          foregroundColor: AppColors.ink,
                          backgroundColor: AppColors.canvas,
                        ),
                        icon: const Icon(
                          Icons.calendar_today_outlined,
                          size: 20,
                        ),
                        label: Text(
                          'Дата: ${date.day}.${date.month}.${date.year}',
                        ),
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
                      const SizedBox(height: 12),
                      Text(
                        'Доступны даты с 23 сентября по 31 декабря 2026 года.',
                        style: textTheme.bodySmall,
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 28),
                        child: Divider(height: 1),
                      ),
                      sectionTitle('02', 'Бюджет и детали'),
                      TextFormField(
                        key: const Key('budget-input'),
                        controller: budget,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Бюджет, ₸',
                          helperText: 'На одного подрядчика',
                          helperMaxLines: 2,
                          errorMaxLines: 3,
                        ),
                        validator: (v) =>
                            (int.tryParse(v?.trim() ?? '') ?? 0) > 0
                            ? null
                            : 'Введите целое число больше нуля',
                      ),
                      const SizedBox(height: 20),
                      ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        childrenPadding: EdgeInsets.zero,
                        shape: const Border(),
                        collapsedShape: const Border(),
                        initiallyExpanded:
                            widget.initial?.hours != null ||
                            widget.initial?.language != null ||
                            (widget.initial?.preferences.isNotEmpty ?? false),
                        title: Text(
                          'Дополнительные пожелания',
                          style: textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        subtitle: Text(
                          'Язык, длительность и атмосфера',
                          style: textTheme.bodySmall,
                        ),
                        children: [
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: hours,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Длительность, ч',
                              errorMaxLines: 3,
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
                            Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: Text(
                                'Текстовые пожелания пока не учитываются в подборе.',
                                style: textTheme.bodySmall,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(horizontal: inset, vertical: 16),
              decoration: BoxDecoration(
                color: AppColors.white,
                border: const Border(top: BorderSide(color: AppColors.border)),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.ink.withValues(alpha: 0.04),
                    blurRadius: 20,
                    offset: const Offset(0, -6),
                  ),
                ],
              ),
              child: FilledButton(
                key: const Key('apply-filters'),
                onPressed: apply,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(48, 56),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 18,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        'Применить и подобрать',
                        textAlign: TextAlign.center,
                        style: textTheme.labelLarge?.copyWith(
                          color: AppColors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Icon(Icons.arrow_forward_rounded, size: 20),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    ),
  );
}
