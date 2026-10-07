import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stickers/generated/intl/app_localizations.dart';
import 'package:stickers/src/data/load_store.dart';

class ExportStickerDialog extends StatefulWidget {
  final int count;

  const ExportStickerDialog({super.key, this.count = 1});

  @override
  State<ExportStickerDialog> createState() => _ExportStickerDialogState();
}

class _ExportStickerDialogState extends State<ExportStickerDialog> {
  StickerFormat _selectedFormat = StickerFormat.png;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((prefs) {
      final saved = prefs.getString("exportStickerFormat");
      if (saved != null && mounted) {
        final match = StickerFormat.values.where((f) => f.name == saved).firstOrNull;
        if (match != null) {
          setState(() => _selectedFormat = match);
        }
      }
    });
  }

  String _getFormatDescription(BuildContext context, StickerFormat format) {
    switch (format) {
      case StickerFormat.png:
        return AppLocalizations.of(context)!.pngDescription;
      case StickerFormat.webp:
        return AppLocalizations.of(context)!.webpDescription;
      case StickerFormat.jpeg:
        return AppLocalizations.of(context)!.jpegDescription;
      case StickerFormat.gif:
        return AppLocalizations.of(context)!.gifDescription;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.count > 1 ? AppLocalizations.of(context)!.exportSelected : AppLocalizations.of(context)!.exportSticker,
      ),
      content: SingleChildScrollView(
        child: RadioGroup<StickerFormat>(
          groupValue: _selectedFormat,
          onChanged: (val) {
            if (val != null) setState(() => _selectedFormat = val);
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: StickerFormat.values.map((format) {
              return RadioListTile<StickerFormat>(
                value: format,
                title: Text(format.label),
                subtitle: Text(_getFormatDescription(context, format)),
                contentPadding: EdgeInsets.zero,
              );
            }).toList(),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(AppLocalizations.of(context)!.cancel),
        ),
        FilledButton(
          onPressed: () {
            SharedPreferences.getInstance().then((prefs) {
              prefs.setString("exportStickerFormat", _selectedFormat.name);
            });
            Navigator.of(context).pop(_selectedFormat);
          },
          child: Text(AppLocalizations.of(context)!.export),
        ),
      ],
    );
  }
}
