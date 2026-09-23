import 'package:flutter/material.dart';

/// Natural content height, equalised per row, including incomplete final rows.
class EqualCardGrid extends StatelessWidget {
  const EqualCardGrid({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final columns = MediaQuery.textScalerOf(context).scale(16) > 24
          ? 1
          : box.maxWidth >= 1320
          ? 3
          : box.maxWidth >= 840
          ? 2
          : 1;
      return Column(
        children: [
          for (var start = 0; start < children.length; start += columns)
            Padding(
              padding: EdgeInsets.only(
                bottom: start + columns < children.length ? 20 : 0,
              ),
              child: Table(
                defaultVerticalAlignment:
                    TableCellVerticalAlignment.intrinsicHeight,
                columnWidths: {
                  for (var c = 1; c < columns * 2 - 1; c += 2)
                    c: const FixedColumnWidth(20),
                },
                children: [
                  TableRow(
                    children: [
                      for (var c = 0; c < columns; c++) ...[
                        if (c > 0) const SizedBox(width: 20),
                        start + c < children.length
                            ? children[start + c]
                            : const SizedBox.shrink(),
                      ],
                    ],
                  ),
                ],
              ),
            ),
        ],
      );
    },
  );
}
