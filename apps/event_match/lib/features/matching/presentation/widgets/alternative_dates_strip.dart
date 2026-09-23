import 'package:flutter/material.dart';
import '../../domain/alternative_dates.dart';
import '../../domain/models.dart';

String variantCount(int count) {
  final tail = count % 100;
  final suffix = tail >= 11 && tail <= 14
      ? 'вариантов'
      : count % 10 == 1
      ? 'вариант'
      : count % 10 >= 2 && count % 10 <= 4
      ? 'варианта'
      : 'вариантов';
  return '$count $suffix';
}

class AlternativeDatesStrip extends StatelessWidget {
  const AlternativeDatesStrip({
    super.key,
    required this.days,
    required this.selectedDate,
    required this.onSelected,
    this.enabled = true,
  });
  final List<AlternativeDate> days;
  final DateTime selectedDate;
  final ValueChanged<DateTime> onSelected;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final localizations = MaterialLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'А если выбрать другую дату?',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        const Text(
          'Все подходящие варианты с теми же фильтрами. Нажмите на дату, чтобы обновить подбор.',
        ),
        const SizedBox(height: 12),
        // Wrapping instead of a fixed-height carousel supports large text and keyboard navigation.
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final day in days)
              Semantics(
                selected: DateUtils.isSameDay(day.date, selectedDate),
                child: OutlinedButton(
                  key: ValueKey('alternative-${dateKey(day.date)}'),
                  onPressed:
                      enabled && !DateUtils.isSameDay(day.date, selectedDate)
                      ? () => onSelected(day.date)
                      : null,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(112, 72),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    backgroundColor: DateUtils.isSameDay(day.date, selectedDate)
                        ? colors.primaryContainer
                        : colors.surface,
                    disabledForegroundColor:
                        DateUtils.isSameDay(day.date, selectedDate)
                        ? colors.onPrimaryContainer
                        : null,
                    side: BorderSide(
                      color: DateUtils.isSameDay(day.date, selectedDate)
                          ? colors.primary
                          : colors.outline,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        localizations.formatMediumDate(day.date),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(variantCount(day.count)),
                      if (DateUtils.isSameDay(day.date, selectedDate))
                        const Text('Выбрано'),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
