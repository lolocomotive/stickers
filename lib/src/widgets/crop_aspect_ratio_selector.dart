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

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<double>(
      showSelectedIcon: false,
      emptySelectionAllowed: true,
      multiSelectionEnabled: false,
      segments: [
        ButtonSegment(
          value: 16 / 9,
          icon: Column(
            children: const [
              Icon(Icons.crop_16_9),
              Text(
                "16:9",
                style: TextStyle(fontSize: 10),
              ),
            ],
          ),
        ),
        ButtonSegment(
          value: 3 / 2,
          icon: Column(
            children: const [
              Icon(Icons.crop_3_2),
              Text(
                "3:2",
                style: TextStyle(fontSize: 10),
              ),
            ],
          ),
        ),
        ButtonSegment(
          value: 1,
          icon: Column(
            children: const [
              Icon(Icons.crop_din),
              Text(
                "1:1",
                style: TextStyle(fontSize: 10),
              ),
            ],
          ),
        ),
        ButtonSegment(
          value: 2 / 3,
          icon: Column(
            children: [
              Transform.rotate(
                angle: pi / 2,
                child: const Icon(Icons.crop_3_2),
              ),
              const Text(
                "2:3",
                style: TextStyle(fontSize: 10),
              ),
            ],
          ),
        ),
        ButtonSegment(
          value: 9 / 16,
          icon: Column(
            children: [
              Transform.rotate(
                angle: pi / 2,
                child: const Icon(Icons.crop_16_9),
              ),
              const Text(
                "9:16",
                style: TextStyle(fontSize: 10),
              ),
            ],
          ),
        ),
      ],
      selected: {aspectRatio == null ? 0 : aspectRatio!},
      onSelectionChanged: (v) {
        HapticFeedback.lightImpact();
        onChanged(v.firstOrNull);
      },
    );
  }
}
