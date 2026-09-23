import 'package:flutter/material.dart';

/// A finite entrance animation: no perpetual shimmer or moving body text.
class AiExplanation extends StatelessWidget {
  const AiExplanation({super.key, required this.text, this.generated = true});
  final String text;
  final bool generated;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final reduced = MediaQuery.disableAnimationsOf(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: generated ? colors.primaryContainer : colors.secondaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (generated) ...[
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
                child: Text(
                  generated
                      ? 'Объяснение от ИИ'
                      : 'Почему подходит · по данным каталога',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: colors.onPrimaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            text,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onPrimaryContainer,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
