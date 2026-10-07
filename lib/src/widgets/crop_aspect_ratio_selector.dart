import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CropAspectRatioSelector extends StatelessWidget {
  const CropAspectRatioSelector({
    super.key,
    required this.aspectRatio,
    required this.onChanged,
  });

  final double? aspectRatio;
  final ValueChanged<double?> onChanged;

  static const ratios = [
    (value: 16 / 9, icon: Icons.crop_16_9, label: "16:9", portrait: false),
    (value: 3 / 2, icon: Icons.crop_3_2, label: "3:2", portrait: false),
    (value: 1.0, icon: Icons.crop_din, label: "1:1", portrait: false),
    (value: 2 / 3, icon: Icons.crop_3_2, label: "2:3", portrait: true),
    (value: 9 / 16, icon: Icons.crop_16_9, label: "9:16", portrait: true),
  ];

  @override
  Widget build(BuildContext context) {
    final selected = aspectRatio == null
        ? null
        : ratios.map((r) => r.value).where((r) => (r - aspectRatio!).abs() < 0.01).firstOrNull;
    return SegmentedButton<double>(
      showSelectedIcon: false,
      emptySelectionAllowed: true,
      multiSelectionEnabled: false,
      segments: [
        for (final ratio in ratios)
          ButtonSegment(
            value: ratio.value,
            icon: Column(
              children: [
                Transform.rotate(
                  angle: ratio.portrait ? pi / 2 : 0,
                  child: Icon(ratio.icon),
                ),
                Text(
                  ratio.label,
                  style: const TextStyle(fontSize: 10),
                ),
              ],
            ),
          ),
      ],
      selected: {?selected},
      onSelectionChanged: (v) {
        HapticFeedback.lightImpact();
        onChanged(v.firstOrNull);
      },
    );
  }
}
