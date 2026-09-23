import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Shared modal frame for panels that leave the catalog in place underneath.
Future<T?> showSidePanel<T>(
  BuildContext context, {
  required String barrierLabel,
  required WidgetBuilder builder,
}) => showDialog<T>(
  context: context,
  barrierLabel: barrierLabel,
  builder: (context) => Dialog(
    alignment: Alignment.centerRight,
    insetPadding: const EdgeInsets.all(24),
    clipBehavior: Clip.antiAlias,
    child: SizedBox(
      width: 640,
      height: MediaQuery.sizeOf(context).height - 48,
      // A nested Scaffold installs its own (drawer-only) DismissIntent action.
      // Handle Escape here so it still dismisses the containing modal panel.
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () {
            Navigator.of(context).maybePop();
          },
        },
        child: builder(context),
      ),
    ),
  ),
);
