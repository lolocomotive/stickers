import 'package:flutter/material.dart';
import 'package:stickers/generated/intl/app_localizations.dart';
import 'package:stickers/src/video/quality_profile.dart';

/// Preset chips plus an advanced panel (quality, fps, compression effort).
/// Editing a slider switches the preset to [QualityPreset.custom].
class QualitySelector extends StatelessWidget {
  final QualitySettings settings;
  final bool animated;
  final bool enabled;
  final ValueChanged<QualitySettings> onChanged;

  const QualitySelector({
    super.key,
    required this.settings,
    required this.animated,
    required this.enabled,
    required this.onChanged,
  });

  String _label(AppLocalizations l, QualityPreset p) => switch (p) {
        QualityPreset.max => l.qualityMax,
        QualityPreset.balanced => l.qualityBalanced,
        QualityPreset.small => l.qualitySmall,
        QualityPreset.auto => l.qualityAuto,
        QualityPreset.custom => l.qualityCustom,
      };

  void _setCustom(QualityProfile p) =>
      onChanged(QualitySettings(preset: QualityPreset.custom, custom: p));

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final profile = settings.profile;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: Text(l.qualityTitle),
        subtitle: Text(_label(l, settings.preset)),
        children: [
          Wrap(
            spacing: 8,
            children: [
              for (final p in QualityPreset.values)
                ChoiceChip(
                  label: Text(_label(l, p)),
                  selected: settings.preset == p,
                  onSelected: enabled
                      // A preset seeds the custom values, so the sliders start from it.
                      ? (_) => onChanged(QualitySettings(
                            preset: p,
                            custom: p == QualityPreset.custom ? settings.custom : profile,
                          ))
                      : null,
                ),
            ],
          ),
          _slider(l.qualityLevel, profile.quality, 5, 100, 19, (v) => _setCustom(profile.copyWith(quality: v))),
          if (animated) ...[
            _slider(l.qualityFps, profile.fps.toDouble(), QualityProfile.minFps.toDouble(),
                QualityProfile.maxFps.toDouble(), QualityProfile.maxFps - QualityProfile.minFps,
                (v) => _setCustom(profile.copyWith(fps: v.round()))),
            _slider(l.qualityEffort, profile.method.toDouble(), 0, 6, 6,
                (v) => _setCustom(profile.copyWith(method: v.round()))),
          ],
        ],
      ),
    );
  }

  Widget _slider(String label, double value, double min, double max, int divisions, ValueChanged<double> onChanged) {
    return Row(
      children: [
        SizedBox(width: 120, child: Text("$label: ${value.round()}", style: const TextStyle(fontSize: 12))),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: enabled ? onChanged : null,
          ),
        ),
      ],
    );
  }
}
