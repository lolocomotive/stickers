import 'package:flutter/material.dart';

class ProgressBarButton extends StatelessWidget {
  const ProgressBarButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.showProgress = false,
    this.progress,
    this.progressIndicator,
  });

  final VoidCallback? onPressed;
  final Widget child;
  final bool showProgress;
  final double? progress;
  final Widget? progressIndicator;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      clipBehavior: Clip.antiAlias,
      style: ButtonStyle(
        padding: WidgetStateProperty.all(EdgeInsets.zero),
      ),
      onPressed: onPressed,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          child,
          const SizedBox(height: 8),
          if (showProgress) progressIndicator ?? LinearProgressIndicator(value: progress),
        ],
      ),
    );
  }
}
