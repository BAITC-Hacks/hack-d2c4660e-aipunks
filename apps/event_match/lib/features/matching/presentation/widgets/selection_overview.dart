import 'package:event_match/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import '../selection_presentation.dart';

class SelectionOverview extends StatelessWidget {
  const SelectionOverview({
    super.key,
    required this.presentation,
    this.unchecked = const [],
    this.action,
  });
  final SelectionPresentation presentation;
  final List<String> unchecked;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Semantics(
        liveRegion: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text(
                presentation.title,
                key: const Key('selection-title'),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            const SizedBox(height: 8),
            Text(presentation.visibleNote),
            for (final text in unchecked.toSet()) ...[
              const SizedBox(height: 8),
              Text(text),
            ],
          ],
        ),
      ),
      if (action != null) ...[
        const SizedBox(height: 12),
        Align(alignment: Alignment.centerLeft, child: action!),
      ],
      if (presentation.summary.isNotEmpty)
        ExpansionTile(
          key: ValueKey('selection-method-${presentation.summary}'),
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: 16),
          title: Text(tr(context, 'Как мы подобрали')),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(presentation.summary),
            ),
          ],
        ),
    ],
  );
}
