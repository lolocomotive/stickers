import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:stickers/generated/intl/app_localizations.dart';
import 'package:stickers/src/checker_painter.dart';
import 'package:stickers/src/data/batch_import.dart';
import 'package:stickers/src/data/sticker_pack.dart';
import 'package:stickers/src/dialogs/error_dialog.dart';
import 'package:stickers/src/pages/crop_page.dart';
import 'package:stickers/src/pages/default_page.dart';
import 'package:stickers/src/util.dart';

class _Selection {
  _Selection(this.path);

  final String path;
  Uint8List? crop;
  String? error;

  String get name => File(path).uri.pathSegments.last;
}

class MultiCropPage extends StatefulWidget {
  const MultiCropPage({super.key, required this.pack, required this.paths, this.selectionWasLimited = false});

  final StickerPack pack;
  final List<String> paths;
  final bool selectionWasLimited;

  @override
  State<MultiCropPage> createState() => _MultiCropPageState();
}

class _MultiCropPageState extends State<MultiCropPage> {
  late final List<_Selection> _selections = widget.paths.map(_Selection.new).toList();
  bool _saving = false;
  bool _openingCrop = false;
  int _prepared = 0;

  Future<void> _crop(_Selection selection) async {
    if (_saving || _openingCrop) return;
    setState(() => _openingCrop = true);
    try {
      final result = await Navigator.of(context).push<Uint8List>(
        MaterialPageRoute(
          builder: (_) => CropPage(
            pack: widget.pack,
            index: 0,
            imagePath: selection.path,
            returnCrop: true,
          ),
        ),
      );
      if (!mounted || result == null) return;
      setState(() {
        selection.crop = result;
        selection.error = null;
      });
    } finally {
      if (mounted) setState(() => _openingCrop = false);
    }
  }

  Future<void> _saveAll() async {
    if (_saving || _openingCrop || _selections.isEmpty) return;
    setState(() {
      _saving = true;
      _prepared = 0;
    });
    try {
      final prepared = <Uint8List>[];
      var failed = false;
      for (final selection in _selections) {
        try {
          prepared.add(selection.crop ?? await prepareUncroppedSticker(selection.path, widget.pack));
          selection.error = null;
        } catch (error) {
          selection.error = error.toString();
          failed = true;
        }
        if (!mounted) return;
        setState(() => _prepared++);
      }
      if (failed) return;
      await saveStickerBatch(widget.pack, prepared);
      if (!mounted) return;
      // Re-enable popping before leaving the saving screen.
      setState(() => _saving = false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
    } catch (error) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => ErrorDialog(
          title: AppLocalizations.of(context)!.couldntExportSticker,
          message: error.toString(),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final busy = _saving || _openingCrop;
    final hasErrors = _selections.any((selection) => selection.error != null);
    return PopScope(
      canPop: !_saving,
      child: DefaultActivity(
        appBar: AppBar(title: Text(l10n.reviewStickers)),
        child: SafeArea(
          child: Column(
            children: [
              if (widget.selectionWasLimited)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(l10n.youCanTHaveMoreThan30Stickers),
                ),
              Expanded(
                child: _selections.isEmpty
                    ? Center(child: Text(l10n.noStickersSelected))
                    : GridView.builder(
                        padding: const EdgeInsets.all(8),
                        itemCount: _selections.length,
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: colCount(MediaQuery.sizeOf(context).width),
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                          childAspectRatio: .8,
                        ),
                        itemBuilder: (context, index) {
                          final selection = _selections[index];
                          return Column(
                            key: ObjectKey(selection),
                            children: [
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(24),
                                  child: Material(
                                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        CustomPaint(painter: CheckerPainter(context)),
                                        InkWell(
                                          onTap: busy ? null : () => _crop(selection),
                                          child: Semantics(
                                            label: l10n.cropSelectedSticker(selection.name),
                                            button: true,
                                            child: Padding(
                                              padding: const EdgeInsets.all(8),
                                              child: selection.crop == null
                                                  ? Image.file(
                                                      File(selection.path),
                                                      fit: BoxFit.contain,
                                                      errorBuilder: (_, error, stack) => const Icon(Icons.broken_image),
                                                    )
                                                  : Image.memory(selection.crop!, fit: BoxFit.contain),
                                            ),
                                          ),
                                        ),
                                        Positioned(
                                          top: 4,
                                          right: 4,
                                          child: IconButton.filledTonal(
                                            tooltip: l10n.removeSelectedSticker(selection.name),
                                            onPressed: busy
                                                ? null
                                                : () => setState(() => _selections.remove(selection)),
                                            icon: const Icon(Icons.close),
                                          ),
                                        ),
                                        if (selection.crop != null)
                                          Positioned(
                                            left: 4,
                                            bottom: 4,
                                            child: IconButton.filledTonal(
                                              tooltip: l10n.resetCrop,
                                              onPressed: busy ? null : () => setState(() => selection.crop = null),
                                              icon: const Icon(Icons.undo),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(selection.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                              ),
                              if (selection.error != null)
                                Tooltip(
                                  message: selection.error!,
                                  child: Text(
                                    l10n.couldntLoadMedia,
                                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (hasErrors) ...[
                      Text(l10n.batchImportErrors, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                      const SizedBox(height: 8),
                    ],
                    if (_saving) ...[
                      LinearProgressIndicator(value: _prepared / _selections.length),
                      const SizedBox(height: 8),
                    ],
                    FilledButton.icon(
                      onPressed: busy || _selections.isEmpty ? null : _saveAll,
                      icon: const Icon(Icons.check),
                      label: Text(
                        _saving
                            ? l10n.savingStickers(_prepared, _selections.length)
                            : l10n.saveAllStickers(_selections.length),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
