import 'package:flutter/material.dart';
import 'package:stickers/generated/intl/app_localizations.dart';
import 'package:stickers/src/globals.dart';

/// Lets the user pick the app's accent color, or go back to the system colors.
///
/// Changes apply immediately so the user can preview them.
class AccentColorDialog extends StatelessWidget {
  const AccentColorDialog({super.key});

  static const accentColors = <Color>[
    Colors.red,
    Colors.deepOrange,
    Colors.orange,
    Colors.amber,
    Colors.pink,
    Colors.lightGreen,
    Colors.lime,
    Colors.yellow,
    Colors.purple,
    Colors.green,
    Colors.teal,
    Colors.cyan,
    Colors.deepPurple,
    Colors.indigo,
    Colors.blue,
    Colors.lightBlue,
  ];

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: settings.accentColor,
      builder: (context, _) {
        final selected = settings.accentColor.value?.toARGB32();
        final outline = Theme.of(context).colorScheme.onSurface;
        return AlertDialog(
          title: Text(AppLocalizations.of(context)!.accentColor),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    border: Border.all(color: selected == null ? outline : Colors.transparent, width: 2),
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: TextButton(
                    onPressed: () => settings.accentColor.value = null,
                    child: Text(AppLocalizations.of(context)!.systemColors),
                  ),
                ),
                GridView.count(
                  crossAxisCount: 4,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: EdgeInsets.zero,
                  children: [
                    for (final color in accentColors)
                      Padding(
                        padding: const EdgeInsets.all(6),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () => settings.accentColor.value = color,
                          child: Ink(
                            decoration: ShapeDecoration(
                              color: color,
                              shape: CircleBorder(
                                side: BorderSide(
                                  color: selected == color.toARGB32() ? outline : Colors.transparent,
                                  width: 2,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(AppLocalizations.of(context)!.done),
            ),
          ],
        );
      },
    );
  }
}
