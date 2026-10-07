import 'package:flutter/material.dart';
import 'package:stickers/generated/intl/app_localizations.dart';
import 'package:stickers/src/globals.dart';

class ExportPackDialog extends StatefulWidget {
  final int packCount;

  const ExportPackDialog({super.key, this.packCount = 1});

  @override
  State<ExportPackDialog> createState() => _ExportPackDialogState();
}

class _ExportPackDialogState extends State<ExportPackDialog> {
  bool _includeEditData = settings.exportIncludeEditData.value;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.packCount > 1 ? AppLocalizations.of(context)!.exportSelected : AppLocalizations.of(context)!.export,
      ),
      content: CheckboxListTile(
        value: _includeEditData,
        onChanged: (val) {
          setState(() {
            _includeEditData = val ?? true;
          });
        },
        title: Text(AppLocalizations.of(context)!.includeEditData),
        subtitle: Text(AppLocalizations.of(context)!.includeEditDataDescription),
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(AppLocalizations.of(context)!.cancel),
        ),
        FilledButton(
          onPressed: () {
            settings.exportIncludeEditData.value = _includeEditData;
            Navigator.of(context).pop(_includeEditData);
          },
          child: Text(AppLocalizations.of(context)!.export),
        ),
      ],
    );
  }
}
