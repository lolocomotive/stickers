import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:stickers/generated/intl/app_localizations.dart';
import 'package:stickers/src/checker_painter.dart';
import 'package:stickers/src/data/batch_import.dart';
import 'package:stickers/src/data/sticker_pack.dart';
import 'package:stickers/src/dialogs/error_dialog.dart';
import 'package:stickers/src/pages/crop_page.dart';
import 'package:stickers/src/pages/default_page.dart';
import 'package:stickers/src/pages/video_crop_page.dart';
import 'package:stickers/src/util.dart';
import 'package:stickers/src/widgets/progress_bar_button.dart';

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

const _preparationWorkers = 3;

class _MultiCropPageState extends State<MultiCropPage> {
  late final List<_Selection> _selections = widget.paths.map(_Selection.new).toList();
  bool _saving = false;
  bool _openingCrop = false;
  int _prepared = 0;

  Future<void> _crop(_Selection selection) async {
    if (_saving || _openingCrop) return;
    setState(() => _openingCrop = true);
    try {
      final result = await Navigator.of(context).pushNamed(
        widget.pack.animated ? VideoCropPage.routeName : CropPage.routeName,
        arguments: EditArguments(
          pack: widget.pack,
          index: 0,
          mediaPath: selection.path,
          type: widget.pack.animated ? StickerMediaType.video : StickerMediaType.picture,
          returnResult: true,
        ),
      ) as Uint8List?;
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
      final prepared = List<Uint8List?>.filled(_selections.length, null);
      var failed = false;
      var next = 0;
      // The image editor runs each call on its own native thread, so a few
      // workers prepare images in parallel. Kept small because every worker
      // holds a full-resolution bitmap natively.
      Future<void> worker() async {
        while (next < _selections.length && mounted) {
          final index = next++;
          final selection = _selections[index];
          try {
            prepared[index] = selection.crop ?? await prepareUncroppedSticker(selection.path);
            selection.error = null;
          } catch (error) {
            selection.error = error.toString();
            failed = true;
          }
          if (mounted) setState(() => _prepared++);
        }
      }

      await Future.wait(List.generate(_preparationWorkers, (_) => worker()));
      if (!mounted || failed) return;
      await saveStickerBatch(widget.pack, prepared.cast<Uint8List>());
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
                Text(
                  l10n.packFullKeptFirst(_selections.length),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
                  textAlign: TextAlign.center,
                ),
              Text(
                l10n.tapStickersToEdit,
                style: TextStyle(color: Theme.of(context).textTheme.bodySmall?.color),
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
                          childAspectRatio: 1.0,
                        ),
                        itemBuilder: (context, index) {
                          final selection = _selections[index];
                          return Column(
                            key: ObjectKey(selection),
                            children: [
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(16),
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
                                            child: LayoutBuilder(
                                              builder: (context, constraints) {
                                                final pixelRatio = MediaQuery.devicePixelRatioOf(context);
                                                return Image(
                                                  image: ResizeImage(
                                                    selection.crop == null
                                                        ? FileImage(File(selection.path))
                                                        : MemoryImage(selection.crop!),
                                                    width: math.max(1, (constraints.maxWidth * pixelRatio).ceil()),
                                                    height: math.max(1, (constraints.maxHeight * pixelRatio).ceil()),
                                                    policy: ResizeImagePolicy.fit,
                                                  ),
                                                  fit: BoxFit.contain,
                                                  errorBuilder: (_, error, stack) => const Icon(Icons.broken_image),
                                                );
                                              },
                                            ),
                                          ),
                                        ),
                                        Positioned(
                                          top: -2,
                                          right: -2,
                                          child: IconButton.filledTonal(
                                            iconSize: 16,
                                            padding: EdgeInsets.all(6),
                                            constraints: const BoxConstraints(),
                                            tooltip: l10n.removeSelectedSticker(selection.name),
                                            onPressed: busy
                                                ? null
                                                : () => setState(() => _selections.remove(selection)),
                                            icon: const Icon(Icons.close),
                                          ),
                                        ),
                                        if (selection.crop != null)
                                          Positioned(
                                            left: -2,
                                            bottom: -2,
                                            child: IconButton.filledTonal(
                                              constraints: const BoxConstraints(),
                                              padding: EdgeInsets.all(6),
                                              iconSize: 16,
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
                              if (selection.error != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Tooltip(
                                    message: selection.error!,
                                    child: Text(
                                      l10n.couldntLoadMedia,
                                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                                    ),
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
                    ProgressBarButton(
                      onPressed: busy || _selections.isEmpty ? null : _saveAll,
                      showProgress: _saving,
                      progress: _prepared / _selections.length,
                      child: Text(
                        _saving
                            ? l10n.importingStickers(_prepared, _selections.length)
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
