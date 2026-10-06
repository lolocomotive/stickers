import 'dart:io';

import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:stickers/generated/intl/app_localizations.dart';
import 'package:stickers/src/checker_painter.dart';
import 'package:stickers/src/data/load_store.dart';
import 'package:stickers/src/data/sticker_pack.dart';
import 'package:stickers/src/dialogs/delete_confirm_dialog.dart';
import 'package:stickers/src/dialogs/edit_pack_dialog.dart';
import 'package:stickers/src/globals.dart';
import 'package:stickers/src/pages/sticker_pack_page.dart';

class StickerPackPreviewCard extends StatefulWidget {
  final StickerPack pack;
  final Function deleteCallback;
  final bool isSelectionMode;
  final bool isSelected;
  final VoidCallback? onToggleSelect;
  final VoidCallback? onLongPress;

  const StickerPackPreviewCard(
    this.pack,
    this.deleteCallback, {
    super.key,
    this.isSelectionMode = false,
    this.isSelected = false,
    this.onToggleSelect,
    this.onLongPress,
  });

  @override
  State<StickerPackPreviewCard> createState() => _StickerPackPreviewCardState();
}

class _StickerPackPreviewCardState extends State<StickerPackPreviewCard> {
  @override
  Widget build(BuildContext context) {
    final Color surface = ElevationOverlay.applySurfaceTint(
      Theme.of(context).colorScheme.surface,
      Theme.of(context).colorScheme.primary,
      2,
    );
    final Color selectedSurface = ElevationOverlay.applySurfaceTint(
      Theme.of(context).colorScheme.primaryContainer,
      Theme.of(context).colorScheme.primary,
      4,
    );

    final String? trayPath =
        widget.pack.trayIcon ?? (widget.pack.stickers.isNotEmpty ? widget.pack.stickers.first.source : null);
    final bool hasValidTray = trayPath != null && File(trayPath).existsSync();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: OpenContainer(
        tappable: false,
        closedColor: widget.isSelected ? selectedSurface : surface,
        openColor: Theme.of(context).colorScheme.surface,
        middleColor: widget.isSelected ? selectedSurface : surface,
        closedShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        closedBuilder: (context, action) => Container(
          foregroundDecoration: widget.isSelected
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.primary,
                    width: 2.5,
                  ),
                )
              : null,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () {
              if (widget.isSelectionMode) {
                widget.onToggleSelect?.call();
              } else {
                action();
              }
            },
            onLongPress: widget.onLongPress,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ListTile(
                  title: Text(widget.pack.title),
                  subtitle: Opacity(
                    opacity: .8,
                    child: Text(widget.pack.author),
                  ),
                  leading: !hasValidTray
                      ? null
                      : Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(24),
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
                          clipBehavior: Clip.antiAlias,
                          child: CustomPaint(
                            painter: CheckerPainter(context),
                            child: Image.file(
                              File(trayPath),
                            ),
                          ),
                        ),
                  trailing: widget.isSelectionMode
                      ? null
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: AppLocalizations.of(context)!.edit,
                              icon: const Icon(Icons.edit),
                              onPressed: () {
                                showDialog(
                                  context: context,
                                  builder: (context) => EditPackDialog(widget.pack),
                                ).then(
                                  (_) => setState(() {}),
                                );
                              },
                            ),
                            IconButton(
                              tooltip: AppLocalizations.of(context)!.delete,
                              icon: const Icon(Icons.delete),
                              onPressed: () {
                                showDialog<bool>(
                                  context: context,
                                  builder: (context) => DeleteConfirmDialog(widget.pack.title),
                                ).then(
                                  (value) async {
                                    if (value == true) {
                                      packs.remove(widget.pack);
                                      widget.deleteCallback();
                                      Directory("$packsDir/${widget.pack.id}").delete(recursive: true);
                                      savePacks(packs);
                                    }
                                  },
                                );
                              },
                            ),
                          ],
                        ),
                ),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onLongPress: widget.onLongPress,
                  onTap: widget.isSelectionMode ? widget.onToggleSelect : null,
                  child: IgnorePointer(
                    ignoring: widget.isSelectionMode,
                    child: Container(
                      height: 100,
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                      child: ListView.builder(
                        shrinkWrap: true,
                        scrollDirection: Axis.horizontal,
                        itemBuilder: (context, index) {
                          var sticker = widget.pack.stickers[index];
                          return Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Container(
                              width: 84,
                              height: 84,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(defaultBorderRadius),
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
                              clipBehavior: Clip.antiAlias,
                              child: CustomPaint(
                                painter: CheckerPainter(context),
                                child: Image.file(
                                  File(sticker.source),
                                ),
                              ),
                            ),
                          );
                        },
                        itemCount: widget.pack.stickers.length,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        openBuilder: (BuildContext context, void Function({Object? returnValue}) action) =>
            StickerPackPage(widget.pack, widget.deleteCallback),
      ),
    );
  }
}
