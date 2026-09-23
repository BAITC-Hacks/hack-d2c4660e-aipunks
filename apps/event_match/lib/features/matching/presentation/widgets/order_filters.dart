import 'package:event_match/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import '../../../../app/design_tokens.dart';
import '../../domain/models.dart';

/// A private draft. Closing without applying never changes the current search.
class OrderFilters extends StatefulWidget {
  const OrderFilters({
    super.key,
    required this.catalog,
    this.initial,
    this.embedded = false,
    this.onApply,
    this.onCancel,
    this.supportsPreferences = false,
    this.datePolicy = const MatchDatePolicy.demo(),
    this.lockEventDetails = false,
  });
  final List<Contractor> catalog;
  final bool embedded;
  final bool supportsPreferences, lockEventDetails;
  final MatchDatePolicy datePolicy;
  final MatchRequest? initial;
  final ValueChanged<MatchRequest>? onApply;
  final VoidCallback? onCancel;

  @override
  State<OrderFilters> createState() => _OrderFiltersState();
}

class _OrderFiltersState extends State<OrderFilters> {
  final form = GlobalKey<FormState>();
  late String city, category, format, language;
  late DateTime date;
  late final TextEditingController budget, hours;

  @override
  void initState() {
    super.initState();
    final r = widget.initial;
    city = r?.city ?? 'Алматы';
    category = r?.category ?? 'Ведущий';
    format = r?.format ?? 'свадьба';
    language = r?.language ?? 'Любой';
    date =
        r?.date ??
        (widget.datePolicy.isLive
            ? widget.datePolicy.firstDate
            : DateTime(2026, 10, 10));
    if (!widget.datePolicy.contains(date)) date = widget.datePolicy.firstDate;
    budget = TextEditingController(text: '${r?.budget ?? 1000000}');
    hours = TextEditingController(text: r?.hours?.toString() ?? '');
  }

  @override
  void dispose() {
    budget.dispose();
    hours.dispose();
    super.dispose();
  }

  void cancel() {
    if (widget.onCancel != null) {
      widget.onCancel!();
    } else {
      Navigator.pop(context);
    }
  }

  void apply() {
    if (!form.currentState!.validate()) return;
    final request = MatchRequest(
      city: city,
      date: date,
      category: category,
      format: format,
      budget: int.parse(budget.text.trim()),
      hours: hours.text.trim().isEmpty
          ? null
          : double.parse(hours.text.trim().replaceAll(',', '.')),
      language: language == 'Любой' ? null : language,
      preferences: widget.initial?.preferences ?? '',
    );
    if (widget.onApply != null) {
      widget.onApply!(request);
    } else {
      Navigator.pop(context, request);
    }
  }

  Widget select(
    String label,
    String value,
    List<String> values,
    ValueChanged<String> update, {
    Key? key,
    bool capitalize = false,
  }) => DropdownButtonFormField<String>(
    key: key,
    initialValue: value,
    isExpanded: true,
    itemHeight: null,
    borderRadius: BorderRadius.circular(16),
    decoration: InputDecoration(labelText: trNullable(context, label)),
    icon: const Icon(Icons.keyboard_arrow_down_rounded),
    selectedItemBuilder: (_) => values
        .map(
          (v) => Text(
            capitalize ? v[0].toUpperCase() + v.substring(1) : v,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        )
        .toList(),
    items: values
        .map(
          (v) => DropdownMenuItem(
            value: v,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(capitalize ? v[0].toUpperCase() + v.substring(1) : v),
            ),
          ),
        )
        .toList(),
    onChanged:
        widget.lockEventDetails &&
            (label == 'Город' || label == 'Формат события')
        ? null
        : (value) {
            if (value != null) setState(() => update(value));
          },
  );

  Widget fields() => LayoutBuilder(
    builder: (context, constraints) {
      final largeText = MediaQuery.textScalerOf(context).scale(16) > 24;
      final columns = largeText
          ? 1
          : constraints.maxWidth >= 1100
          ? 3
          : constraints.maxWidth >= 680
          ? 2
          : 1;
      final width = (constraints.maxWidth - 20 * (columns - 1)) / columns;
      final controls = <Widget>[
        select(
          'Кого ищем?',
          category,
          ({category, ...widget.catalog.expand((c) => c.categories)}.toList()
            ..sort()),
          (v) => category = v,
          key: const Key('category-select'),
        ),
        select(
          'Город',
          city,
          ({city, ...widget.catalog.map((c) => c.city)}.toList()..sort()),
          (v) => city = v,
          key: const Key('city-select'),
        ),
        select(
          'Формат события',
          format,
          const [
            'свадьба',
            'той',
            'корпоратив',
            'конференция',
            'юбилей',
            'день рождения',
          ],
          (v) => format = v,
          key: const Key('format-select'),
          capitalize: true,
        ),
        OutlinedButton.icon(
          key: const Key('date-input'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(48, 60),
            alignment: Alignment.centerLeft,
            foregroundColor: AppColors.ink,
          ),
          icon: const Icon(Icons.calendar_today_outlined, size: 20),
          label: Text('Дата: ${date.day}.${date.month}.${date.year}'),
          onPressed: widget.lockEventDetails
              ? null
              : () async {
                  final value = await showDatePicker(
                    context: context,
                    initialDate: date,
                    firstDate: widget.datePolicy.firstDate,
                    lastDate: widget.datePolicy.lastDate,
                  );
                  if (value != null && mounted) setState(() => date = value);
                },
        ),
        TextFormField(
          key: const Key('budget-input'),
          controller: budget,
          keyboardType: TextInputType.number,
          decoration:  InputDecoration(
            labelText: trNullable(context, 'Бюджет, ₸'),
            helperText: trNullable(context, 'На одного подрядчика'),
            errorMaxLines: 3,
          ),
          validator: localizeValidator(context, (v) {
            final value = int.tryParse(v?.trim() ?? '') ?? 0;
            if (value <= 0) return 'Введите целое число больше нуля';
            if (widget.datePolicy.isLive && value > 1000000000) {
              return 'Максимальный бюджет — 1 000 000 000 ₸';
            }
            return null;
          }),
        ),
        select(
          'Язык',
          language,
          const ['Любой', 'русский', 'казахский', 'английский'],
          (v) => language = v,
          key: const Key('language-select'),
        ),
        TextFormField(
          key: const Key('hours-input'),
          controller: hours,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration:  InputDecoration(
            labelText: trNullable(context, 'Длительность, ч'),
            helperText: trNullable(context, 'Необязательно'),
            errorMaxLines: 3,
          ),
          validator: localizeValidator(context, (v) {
            if (v == null || v.trim().isEmpty) return null;
            final n = double.tryParse(v.trim().replaceAll(',', '.'));
            if (widget.datePolicy.isLive && n != null && n > 48) {
              return 'Максимальная длительность — 48 часов';
            }
            return n != null && n.isFinite && n > 0
                ? null
                : 'Введите число больше нуля';
          }),
        ),
      ];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Условия события',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
           Text(
            tr(context, 'Уточните условия — подберём до трёх подрядчиков. Изменения применяются только по кнопке.'),
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 20,
            runSpacing: 24,
            children: [
              for (final field in controls)
                SizedBox(width: width, child: field),
            ],
          ),
          const SizedBox(height: 12),
          Flex(
            direction: columns > 1 ? Axis.horizontal : Axis.vertical,
            crossAxisAlignment: columns > 1
                ? CrossAxisAlignment.center
                : CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                fit: columns > 1 ? FlexFit.tight : FlexFit.loose,
                child: Text(
                  widget.datePolicy.isLive
                      ? 'Даты на ближайшие 365 дней. Доступность не означает бронирование.'
                      : 'Доступны даты с 23 сентября по 31 декабря 2026 года.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              if (widget.embedded) ...[
                SizedBox(
                  width: columns > 1 ? 20 : 0,
                  height: columns > 1 ? 0 : 12,
                ),
                actions(),
              ],
            ],
          ),
        ],
      );
    },
  );

  Widget actions() => Wrap(
    alignment: WrapAlignment.end,
    spacing: 12,
    runSpacing: 12,
    children: [
      FilledButton.icon(
        key: const Key('apply-filters'),
        onPressed: apply,
        icon: const Icon(Icons.check, size: 18),
        label:  Text(tr(context, 'Применить и подобрать')),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final content = Form(key: form, child: fields());
    if (widget.embedded) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [const Divider(), const SizedBox(height: 20), content],
        ),
      );
    }
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 12, 12),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'ПЕРСОНАЛЬНЫЙ ПОДБОР',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: trNullable(context, 'Закрыть без изменений'),
                  onPressed: cancel,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: content,
            ),
          ),
          const Divider(height: 1),
          Padding(padding: const EdgeInsets.all(16), child: actions()),
        ],
      ),
    );
  }
}
