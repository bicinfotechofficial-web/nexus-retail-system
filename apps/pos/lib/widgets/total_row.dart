import 'package:flutter/material.dart';

/// A label on the left and an amount on the right.
class TotalRow extends StatelessWidget {
  const TotalRow(this.label, this.value, {this.style, super.key});

  final String label;
  final String value;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(value, style: style),
        ],
      ),
    );
  }
}
