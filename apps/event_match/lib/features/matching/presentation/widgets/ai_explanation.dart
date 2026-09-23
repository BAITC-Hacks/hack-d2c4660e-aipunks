import 'package:flutter/material.dart';

enum ExplanationKind { matching, services }

/// A finite entrance animation: no perpetual shimmer or moving body text.
class AiExplanation extends StatelessWidget {
  const AiExplanation({
    super.key,
    required this.text,
    this.generated = false,
    this.source,
    this.kind = ExplanationKind.matching,
    this.maxLines,
  });
  final String text;

  /// Retained for older callers. Authorship is determined only by [source].
  final bool generated;
  final String? source;
  final ExplanationKind kind;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final reduced = MediaQuery.disableAnimationsOf(context);
    final matching = kind == ExplanationKind.matching;
    final fromLlm = source == 'llm';
    final foreground = matching
        ? colors.onPrimaryContainer
        : colors.onSecondaryContainer;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: matching ? colors.primaryContainer : colors.secondaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (fromLlm) ...[
                ExcludeSemantics(
                  child: TweenAnimationBuilder<double>(
                    key: ValueKey(text),
                    tween: Tween(begin: reduced ? 1 : .65, end: 1),
                    duration: reduced
                        ? Duration.zero
                        : const Duration(milliseconds: 450),
                    curve: Curves.easeOutCubic,
                    builder: (context, value, child) =>
                        Transform.scale(scale: value, child: child),
                    child: Icon(
                      Icons.auto_awesome_outlined,
                      size: 20,
                      color: colors.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    matching ? 'Почему в подборке' : 'Об услугах',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            text,
            maxLines: maxLines,
            overflow: maxLines == null ? null : TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: foreground,
              height: 1.5,
            ),
          ),
          if (fromLlm) ...[
            const SizedBox(height: 8),
            Text(
              matching ? 'Формулировка выбрана ИИ · GPT' : 'Сводка ИИ · GPT',
              style: theme.textTheme.labelSmall?.copyWith(color: foreground),
            ),
          ],
        ],
      ),
    );
  }
}

/// Unknown conditions remain separate from the explanation of known matches.
class ExplanationLimitations extends StatelessWidget {
  const ExplanationLimitations({super.key, required this.items});
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    final values = items
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet();
    if (values.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text('Что уточнить', style: theme.textTheme.labelLarge),
        ),
        const SizedBox(height: 6),
        for (final value in values)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text('• $value', style: theme.textTheme.bodySmall),
          ),
      ],
    );
  }
}
