import 'package:event_match/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import '../../../matching/domain/models.dart';
import '../../../matching/presentation/widgets/recommendation_comparison.dart';

class AssistantRecommendations extends StatelessWidget {
  const AssistantRecommendations({
    super.key,
    required this.recommendations,
    required this.unverified,
    required this.preliminary,
    required this.onReject,
    this.enabled = true,
    this.isFavorite,
    this.onFavorite,
  });
  final List<Recommendation> recommendations;
  final Map<String, List<String>> unverified;
  final bool preliminary;
  final bool enabled;
  final bool Function(String id)? isFavorite;
  final ValueChanged<Contractor>? onFavorite;
  final Future<void> Function(String id, String reason) onReject;

  Future<void> _reject(BuildContext context, Contractor contractor) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => _RejectDialog(name: contractor.name),
    );
    if (reason != null) await onReject(contractor.id, reason);
  }

  @override
  Widget build(BuildContext context) => RecommendationComparison(
    recommendations: recommendations,
    unverified: unverified,
    enabled: enabled,
    isFavorite: isFavorite,
    onFavorite: onFavorite,
    onReject: (contractor) => _reject(context, contractor),
  );
}

class _RejectDialog extends StatefulWidget {
  const _RejectDialog({required this.name});
  final String name;

  @override
  State<_RejectDialog> createState() => _RejectDialogState();
}

class _RejectDialogState extends State<_RejectDialog> {
  final _reason = TextEditingController();
  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: Text(tr(context, 'Что не подошло?')),
    content: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Уберём «${widget.name}» из подборки и учтём причину.'),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final reason in ['Дорого', 'Не мой стиль', 'Мало информации'])
              ActionChip(
                label: Text(reason),
                onPressed: () => Navigator.pop(context, reason),
              ),
          ],
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _reason,
          maxLength: 300,
          minLines: 1,
          maxLines: 4,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            labelText: trNullable(context, 'Своя причина'),
          ),
          onChanged: (_) => setState(() {}),
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) Navigator.pop(context, value.trim());
          },
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(tr(context, 'Отмена')),
      ),
      FilledButton(
        onPressed: _reason.text.trim().isEmpty
            ? null
            : () => Navigator.pop(context, _reason.text.trim()),
        child: Text(tr(context, 'Обновить подборку')),
      ),
    ],
  );
}
