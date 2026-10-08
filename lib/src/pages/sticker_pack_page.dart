import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:stickers/generated/intl/app_localizations.dart';
import 'package:stickers/src/data/load_store.dart';
import 'package:stickers/src/data/sticker_pack.dart';
import 'package:stickers/src/data/storage.dart';
import 'package:stickers/src/settings/settings.dart';
import 'package:stickers/src/video/gif_transcoder.dart';
import 'package:stickers/src/dialogs/delete_confirm_dialog.dart';
import 'package:stickers/src/dialogs/edit_pack_dialog.dart';
import 'package:stickers/src/dialogs/edit_sticker_dialog.dart';
import 'package:stickers/src/dialogs/error_dialog.dart';
import 'package:stickers/src/dialogs/export_pack_dialog.dart';
import 'package:stickers/src/dialogs/export_sticker_dialog.dart';
import 'package:stickers/src/globals.dart';
import 'package:stickers/src/pages/crop_page.dart';
import 'package:stickers/src/pages/default_page.dart';
import 'package:stickers/src/pages/multi_crop_page.dart';
import 'package:stickers/src/util.dart';
import 'package:stickers/src/widgets/drag_select.dart';
import 'package:stickers/src/widgets/sticker_thumbnail.dart';

class StickerPackPage extends StatefulWidget {
  final StickerPack pack;
  final Function deleteCallback;

  const StickerPackPage(this.pack, this.deleteCallback, {super.key});

  static const routeName = "/pack";

  @override
  State<StickerPackPage> createState() => StickerPackPageState();
}

class StickerPackPageState extends State<StickerPackPage> {
  bool _importing = false;
  final Set<int> _selectedIndices = <int>{};
  bool _isReorderMode = false;
  final GlobalKey<NestedScrollViewState> _nestedKey = GlobalKey<NestedScrollViewState>();

  bool get _isSelectionMode => _selectedIndices.isNotEmpty;

  void _toggleStickerSelection(int index) {
    setState(() {
      final wasEmpty = _selectedIndices.isEmpty;
      if (_selectedIndices.contains(index)) {
        _selectedIndices.remove(index);
      } else {
        _selectedIndices.add(index);
      }
      if (wasEmpty && _selectedIndices.isNotEmpty) {
        revealAppBar(_nestedKey);
      }
    });
  }

  void _onStickerTap(int index) {
    if (_isSelectionMode) {
      _toggleStickerSelection(index);
      return;
    }
    if (_isReorderMode) return;
    showDialog(
      context: context,
      builder: ((context) => EditStickerDialog(widget.pack, index)),
    ).then((_) => setState(() {}));
  }

  void _onStickerLongPress(BuildContext itemContext, int index) {
    if (_isReorderMode) return;
    DragSelectRegion.start(itemContext, index);
  }

  void _setSelection(Set<int> selection) {
    setState(() {
      final wasEmpty = _selectedIndices.isEmpty;
      _selectedIndices
        ..clear()
        ..addAll(selection);
      if (wasEmpty && _selectedIndices.isNotEmpty) {
        revealAppBar(_nestedKey);
      }
    });
  }

  void _moveSticker(int fromIndex, int toIndex) {
    if (fromIndex == toIndex) return;
    if (fromIndex < 0 || fromIndex >= widget.pack.stickers.length) return;
    if (toIndex < 0 || toIndex >= widget.pack.stickers.length) return;
    setState(() {
      final sticker = widget.pack.stickers.removeAt(fromIndex);
      widget.pack.stickers.insert(toIndex, sticker);
      widget.pack.onEdit();
    });
  }

  Future<void> _deleteSelectedStickers() async {
    if (_selectedIndices.isEmpty) return;
    final count = _selectedIndices.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => DeleteConfirmDialog.titled(AppLocalizations.of(context)!.deleteSelectedStickers(count)),
    );

    if (confirmed == true) {
      final sorted = _selectedIndices.toList()..sort((a, b) => b.compareTo(a));
      final removed = [for (final index in sorted) widget.pack.stickers.removeAt(index)];
      // Older versions used a sticker as tray icon.
      if (removed.any((sticker) => sticker.source == widget.pack.trayIcon)) {
        widget.pack.trayIcon = null;
      }
      _selectedIndices.clear();
      if (mounted) setState(() {});
      // Only deleted once packs.json no longer refers to them.
      await widget.pack.onEdit();
      await Future.wait(removed.map(deleteStickerFiles));
    }
  }

  Future<void> _deletePack() async {
    final value = await showDialog<bool>(
      context: context,
      builder: (context) => DeleteConfirmDialog(widget.pack.title),
    );
    if (!mounted || value != true) return;
    packs.remove(widget.pack);
    widget.deleteCallback();
    Navigator.of(context).pop();
    await deletePack(widget.pack);
  }

  Future<void> _exportPack() async {
    final includeEditData = await showDialog<bool>(
      context: context,
      builder: (context) => const ExportPackDialog(),
    );
    if (includeEditData == null || !mounted) return;
    await exportWithFeedback(context, () => exportPack(widget.pack, includeEditData: includeEditData));
  }

  Future<void> _exportSelectedStickers() async {
    if (_selectedIndices.isEmpty) return;
    final format = await showDialog<StickerFormat>(
      context: context,
      builder: (context) => ExportStickerDialog(count: _selectedIndices.length),
    );
    if (format == null || !mounted) return;
    final selectedStickers = _selectedIndices.map((i) => widget.pack.stickers[i]).toList();
    await exportStickersWithProgress(context, selectedStickers, format, packTitle: widget.pack.title);
  }

  @override
  Widget build(BuildContext context) {
    final bool allSelected = widget.pack.stickers.isNotEmpty && _selectedIndices.length == widget.pack.stickers.length;

    return PopScope(
      canPop: !_isSelectionMode && !_isReorderMode,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_isSelectionMode) {
          setState(() => _selectedIndices.clear());
        } else if (_isReorderMode) {
          setState(() => _isReorderMode = false);
        }
      },
      child: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: DefaultSliverActivity(
                nestedScrollViewKey: _nestedKey,
                pinned: _isSelectionMode,
                leading: _isSelectionMode
                    ? IconButton(
                        tooltip: AppLocalizations.of(context)!.cancel,
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() => _selectedIndices.clear()),
                      )
                    : null,
                title: _isSelectionMode
                    ? AppLocalizations.of(context)!.selectedCount(_selectedIndices.length)
                    : _isReorderMode
                    ? AppLocalizations.of(context)!.reorderStickers
                    : widget.pack.title,
                actions: _isSelectionMode
                    ? [
                        IconButton(
                          tooltip: allSelected
                              ? AppLocalizations.of(context)!.deselectAll
                              : AppLocalizations.of(context)!.selectAll,
                          icon: Icon(allSelected ? Icons.deselect : Icons.select_all),
                          onPressed: () {
                            setState(() {
                              if (allSelected) {
                                _selectedIndices.clear();
                              } else {
                                _selectedIndices.addAll(List.generate(widget.pack.stickers.length, (i) => i));
                              }
                            });
                          },
                        ),
                        IconButton(
                          tooltip: AppLocalizations.of(context)!.exportSelected,
                          icon: const Icon(Icons.share),
                          onPressed: _exportSelectedStickers,
                        ),
                        IconButton(
                          tooltip: AppLocalizations.of(context)!.delete,
                          icon: const Icon(Icons.delete),
                          onPressed: _deleteSelectedStickers,
                        ),
                      ]
                    : _isReorderMode
                    ? [
                        IconButton(
                          tooltip: AppLocalizations.of(context)!.done,
                          icon: const Icon(Icons.check),
                          onPressed: () => setState(() => _isReorderMode = false),
                        ),
                      ]
                    : [
                        IconButton(
                          tooltip: AppLocalizations.of(context)!.edit,
                          onPressed: () {
                            showDialog(
                              context: context,
                              builder: (context) => EditPackDialog(widget.pack),
                            ).then((value) => setState(() {}));
                          },
                          icon: const Icon(Icons.edit),
                        ),
                        IconButton(
                          tooltip: AppLocalizations.of(context)!.reorderStickers,
                          onPressed: widget.pack.stickers.length < 2
                              ? null
                              : () {
                                  setState(() {
                                    _isReorderMode = true;
                                    _selectedIndices.clear();
                                  });
                                  revealAppBar(_nestedKey);
                                },
                          icon: const Icon(Icons.swap_vert),
                        ),
                        IconButton(
                          tooltip: AppLocalizations.of(context)!.delete,
                          onPressed: _deletePack,
                          icon: const Icon(Icons.delete),
                        ),
                      ],
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: DragSelectRegion(
                    selection: () => _selectedIndices,
                    onSelectionChanged: _setSelection,
                    child: GridView.builder(
                      itemCount: (_isSelectionMode || _isReorderMode)
                          ? widget.pack.stickers.length
                          : widget.pack.stickers.length + 1,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: colCount(MediaQuery.of(context).size.width),
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                      ),
                      itemBuilder: (context, index) {
                        if (index == widget.pack.stickers.length) {
                          bool disabled = _importing || widget.pack.stickers.length >= 30;
                          return Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                color: disabled ? Colors.grey : Theme.of(context).colorScheme.primary,
                                width: 2,
                              ),
                            ),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(24),
                              onTap: disabled ? null : _createSticker,
                              child: Icon(
                                Icons.add,
                                size: 40,
                                color: disabled ? Colors.grey : Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          );
                        }

                        final bool isSelected = _selectedIndices.contains(index);
                        final sticker = widget.pack.stickers[index];
                        final highlightBorder = BoxDecoration(
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: Theme.of(context).colorScheme.primary,
                            width: 3.5,
                          ),
                        );

                        Widget stickerContent = Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(24),
                            color: Color.lerp(
                              Theme.of(context).colorScheme.primary,
                              Theme.of(context).colorScheme.surface,
                              .7,
                            ),
                            boxShadow: [
                              BoxShadow(
                                offset: const Offset(1, 1),
                                blurRadius: 3,
                                color: Theme.of(context).brightness == Brightness.light
                                    ? Colors.black26
                                    : Colors.black12,
                              ),
                            ],
                          ),
                          foregroundDecoration: isSelected ? selectionDecoration(context, radius: 24) : null,
                          clipBehavior: Clip.antiAlias,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              StickerThumbnail(
                                file: File(sticker.source),
                              ),
                              if (_isReorderMode) ...[
                                Positioned(
                                  top: 6,
                                  right: 6,
                                  child: _reorderBadge(Icons.drag_indicator),
                                ),
                                Positioned(
                                  left: 4,
                                  right: 4,
                                  bottom: 4,
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      if (index > 0)
                                        InkWell(
                                          onTap: () => _moveSticker(index, index - 1),
                                          child: _reorderBadge(Icons.chevron_left),
                                        )
                                      else
                                        const SizedBox(width: 26),
                                      if (index < widget.pack.stickers.length - 1)
                                        InkWell(
                                          onTap: () => _moveSticker(index, index + 1),
                                          child: _reorderBadge(Icons.chevron_right),
                                        )
                                      else
                                        const SizedBox(width: 26),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        );

                        if (_isReorderMode) {
                          return DragTarget<int>(
                            onWillAcceptWithDetails: (details) => details.data != index,
                            onAcceptWithDetails: (details) => _moveSticker(details.data, index),
                            builder: (context, candidateData, rejectedData) {
                              final bool isHovered = candidateData.isNotEmpty;
                              return Draggable<int>(
                                data: index,
                                feedback: Material(
                                  color: Colors.transparent,
                                  child: Container(
                                    width: 90,
                                    height: 90,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(20),
                                      boxShadow: const [
                                        BoxShadow(
                                          offset: Offset(2, 4),
                                          blurRadius: 10,
                                          color: Colors.black45,
                                        ),
                                      ],
                                    ),
                                    clipBehavior: Clip.antiAlias,
                                    child: StickerThumbnail(
                                      file: File(sticker.source),
                                      targetSize: 90,
                                    ),
                                  ),
                                ),
                                childWhenDragging: Opacity(
                                  opacity: 0.25,
                                  child: stickerContent,
                                ),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 150),
                                  foregroundDecoration: isHovered ? highlightBorder : null,
                                  child: stickerContent,
                                ),
                              );
                            },
                          );
                        }

                        return DragSelectItem(
                          index: index,
                          child: GestureDetector(
                            onTap: () => _onStickerTap(index),
                            onLongPress: () => _onStickerLongPress(context, index),
                            child: stickerContent,
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
            if (!_isReorderMode)
              Material(
                child: Container(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  color: Theme.of(context).colorScheme.surface,
                  child: _isSelectionMode
                      ? Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                icon: const Icon(Icons.close),
                                onPressed: () => setState(() => _selectedIndices.clear()),
                                label: Text(AppLocalizations.of(context)!.cancel),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 2,
                              child: FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  backgroundColor: Theme.of(context).colorScheme.error,
                                  foregroundColor: Theme.of(context).colorScheme.onError,
                                ),
                                icon: const Icon(Icons.delete),
                                onPressed: _deleteSelectedStickers,
                                label: Text(AppLocalizations.of(context)!.delete),
                              ),
                            ),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (widget.pack.stickers.length < 3)
                              Opacity(
                                opacity: .7,
                                child: Text(
                                  AppLocalizations.of(context)!.youNeedAtLeast3Stickers,
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            if (widget.pack.stickers.length >= 30)
                              Opacity(
                                opacity: .7,
                                child: Text(
                                  AppLocalizations.of(context)!.youCanTHaveMoreThan30Stickers,
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            Row(
                              children: [
                                ElevatedButton.icon(
                                  icon: const Icon(Icons.share),
                                  onPressed: _exportPack,
                                  label: Text(AppLocalizations.of(context)!.export),
                                ),
                                const SizedBox(
                                  width: 8,
                                ),
                                Expanded(
                                  flex: 2,
                                  child: FilledButton(
                                    onPressed: widget.pack.stickers.length < 3
                                        ? null
                                        : () => sendToWhatsappWithErrorHandling(widget.pack, context),
                                    child: Text(AppLocalizations.of(context)!.addToWhatsapp),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _reorderBadge(IconData icon) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.black54,
      ),
      child: Icon(icon, size: 18, color: Colors.white),
    );
  }

  Future<VideoInputMethod?> _askVideoInputMethod() {
    return showModalBottomSheet<VideoInputMethod>(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Text(
                  AppLocalizations.of(context)!.addAnimatedSticker,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              ListTile(
                leading: const Icon(Icons.video_library),
                title: Text(AppLocalizations.of(context)!.videoGallery),
                subtitle: Text(AppLocalizations.of(context)!.videoGallerySubtitle),
                onTap: () => Navigator.of(context).pop(VideoInputMethod.gallery),
              ),
              ListTile(
                leading: const Icon(Icons.folder_open),
                title: Text(AppLocalizations.of(context)!.videoFile),
                subtitle: Text(AppLocalizations.of(context)!.videoFileSubtitle),
                onTap: () => Navigator.of(context).pop(VideoInputMethod.filePicker),
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  Future<void> _createSticker() async {
    if (_importing || widget.pack.stickers.length >= 30) return;
    setState(() => _importing = true);
    // Copies made by the pickers, deleted once the stickers are made.
    final picked = <String>[];
    try {
      final ImagePicker picker = ImagePicker();
      if (widget.pack.animated) {
        final method = settings.videoInputMethod.value == VideoInputMethod.ask
            ? await _askVideoInputMethod()
            : settings.videoInputMethod.value;

        if (method == null || !mounted) return;
        final selectVideoTitle = AppLocalizations.of(context)!.selectVideo;

        final String selectedPath;
        final bool isValid;
        if (method == VideoInputMethod.gallery) {
          final XFile? video = await picker.pickVideo(source: ImageSource.gallery);
          if (video == null) return;
          selectedPath = video.path;
          isValid = isSupportedVideo(selectedPath) || GifTranscoder.isGifFile(selectedPath);
        } else {
          final file = await FilePicker.pickFile(
            type: FileType.custom,
            allowedExtensions: ['gif', ...supportedVideoExtensions],
            dialogTitle: selectVideoTitle,
          );
          final path = file?.path;
          if (path == null) return;
          selectedPath = path;
          isValid = isSupportedVideo(selectedPath) || GifTranscoder.isGifFile(selectedPath);
        }
        picked.add(selectedPath);

        if (!mounted) return;
        if (!isValid) {
          showUnsupportedFormatDialog(context);
          return;
        }
        await Navigator.pushNamed(
          context,
          "/crop_video",
          arguments: EditArguments(
            pack: widget.pack,
            index: widget.pack.stickers.length,
            mediaPath: selectedPath,
          ),
        );
      } else {
        final remaining = 30 - widget.pack.stickers.length;
        // The multi-image picker requires a limit of at least two.
        final List<XFile> images;
        if (remaining == 1) {
          final image = await picker.pickImage(source: ImageSource.gallery);
          images = image == null ? [] : [image];
        } else {
          images = await picker.pickMultiImage(limit: remaining);
        }
        picked.addAll(images.map((image) => image.path));
        if (!mounted) return;
        if (images.isEmpty) return;

        final validImages = images.where((image) => isSupportedImage(image.path)).toList();
        if (validImages.isEmpty) {
          showUnsupportedFormatDialog(context);
          return;
        }

        if (validImages.length == 1) {
          await Navigator.pushNamed(
            context,
            "/crop",
            arguments: EditArguments(
              pack: widget.pack,
              index: widget.pack.stickers.length,
              mediaPath: validImages.first.path,
            ),
          );
        } else {
          await Navigator.of(context).push<void>(
            MaterialPageRoute(
              builder: (_) => MultiCropPage(
                pack: widget.pack,
                paths: validImages.take(remaining).map((image) => image.path).toList(),
                selectionWasLimited: validImages.length > remaining,
              ),
            ),
          );
        }
      }
    } on Exception catch (e) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) {
            return ErrorDialog(
              title: AppLocalizations.of(context)!.couldntLoadMedia,
              message: e.toString(),
            );
          },
        );
      }
    } finally {
      await Future.wait(picked.map(deleteTemporaryFile));
      if (mounted) setState(() => _importing = false);
    }
  }
}
