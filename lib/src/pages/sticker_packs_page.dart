import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:stickers/generated/intl/app_localizations.dart';
import 'package:stickers/src/data/load_store.dart';
import 'package:stickers/src/data/sticker_pack.dart';
import 'package:stickers/src/dialogs/create_pack_dialog.dart';
import 'package:stickers/src/dialogs/delete_confirm_dialog.dart';
import 'package:stickers/src/dialogs/error_dialog.dart';
import 'package:stickers/src/dialogs/export_pack_dialog.dart';
import 'package:stickers/src/globals.dart';
import 'package:stickers/src/pages/default_page.dart';
import 'package:stickers/src/widgets/drag_select.dart';
import 'package:stickers/src/widgets/sticker_pack_preview_card.dart';
import 'package:stickers/src/util.dart';

class StickerPacksPage extends StatefulWidget {
  const StickerPacksPage({super.key});

  static const routeName = "/";

  @override
  State<StickerPacksPage> createState() => StickerPacksPageState();
}

class StickerPacksPageState extends State<StickerPacksPage> {
  final Set<StickerPack> _selectedPacks = <StickerPack>{};
  final GlobalKey<NestedScrollViewState> _nestedKey = GlobalKey<NestedScrollViewState>();

  bool get _isSelectionMode => _selectedPacks.isNotEmpty;

  @override
  initState() {
    super.initState();
    homeState = this;
  }

  void update() {
    if (!mounted) return;
    setState(() {});
  }

  void _togglePackSelection(StickerPack pack) {
    setState(() {
      final wasEmpty = _selectedPacks.isEmpty;
      if (_selectedPacks.contains(pack)) {
        _selectedPacks.remove(pack);
      } else {
        _selectedPacks.add(pack);
      }
      if (wasEmpty && _selectedPacks.isNotEmpty) {
        revealAppBar(_nestedKey);
      }
    });
  }

  void _setPackSelection(Set<int> indices) {
    setState(() {
      final wasEmpty = _selectedPacks.isEmpty;
      _selectedPacks
        ..clear()
        ..addAll(indices.map((i) => packs[i]));
      if (wasEmpty && _selectedPacks.isNotEmpty) {
        revealAppBar(_nestedKey);
      }
    });
  }

  Future<void> _exportSelectedPacks() async {
    if (_selectedPacks.isEmpty) return;
    final includeEditData = await showDialog<bool>(
      context: context,
      builder: (context) => ExportPackDialog(packCount: _selectedPacks.length),
    );
    if (includeEditData == null || !mounted) return;
    await exportWithFeedback(context, () => exportPacks(_selectedPacks.toList(), includeEditData: includeEditData));
  }

  Future<void> _deleteSelectedPacks() async {
    if (_selectedPacks.isEmpty) return;
    final count = _selectedPacks.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => count == 1
          ? DeleteConfirmDialog(_selectedPacks.first.title)
          : DeleteConfirmDialog.titled(AppLocalizations.of(context)!.deleteSelectedPacks(count)),
    );

    if (confirmed == true) {
      for (final pack in _selectedPacks.toList()) {
        packs.remove(pack);
        await deletePackDirectory(pack);
      }
      _selectedPacks.clear();
      await savePacks(packs);
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool allSelected = packs.isNotEmpty && _selectedPacks.length == packs.length;

    return PopScope(
      canPop: !_isSelectionMode,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_isSelectionMode) {
          setState(() => _selectedPacks.clear());
        }
      },
      child: DefaultSliverActivity(
        nestedScrollViewKey: _nestedKey,
        pinned: _isSelectionMode,
        leading: _isSelectionMode
            ? IconButton(
                tooltip: AppLocalizations.of(context)!.cancel,
                icon: const Icon(Icons.close),
                onPressed: () => setState(() => _selectedPacks.clear()),
              )
            : null,
        title: _isSelectionMode
            ? AppLocalizations.of(context)!.selectedCount(_selectedPacks.length)
            : (AppLocalizations.of(context)?.pTitle ?? localizationUnavailable),
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
                        _selectedPacks.clear();
                      } else {
                        _selectedPacks.addAll(packs);
                      }
                    });
                  },
                ),
                IconButton(
                  tooltip: AppLocalizations.of(context)!.exportSelected,
                  icon: const Icon(Icons.share),
                  onPressed: _exportSelectedPacks,
                ),
                IconButton(
                  tooltip: AppLocalizations.of(context)!.delete,
                  icon: const Icon(Icons.delete),
                  onPressed: _deleteSelectedPacks,
                ),
              ]
            : [
                IconButton(
                  tooltip: AppLocalizations.of(context)!.settings,
                  onPressed: () {
                    Navigator.of(context).pushNamed("/settings");
                  },
                  icon: const Icon(Icons.settings),
                ),
              ],
        fab: _isSelectionMode
            ? null
            : Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  FloatingActionButton(
                    tooltip: AppLocalizations.of(context)!.import,
                    onPressed: () async {
                      FilePickerResult? result = await FilePicker.pickFiles(
                        type: FileType.custom,
                        allowedExtensions: const ['stickify', 'zip', 'wastickers'],
                        dialogTitle: AppLocalizations.of(context)!.selectPack,
                      );
                      if (result == null) return;
                      for (final f in result.files) {
                        try {
                          if (f.path == null || !isSupportedPack(f.path!)) {
                            if (context.mounted) showUnsupportedFormatDialog(context);
                            continue;
                          }
                          await importPack(File(f.path!));
                          setState(() {});
                        } on Exception catch (e, st) {
                          debugPrint(e.toString());
                          debugPrintStack(stackTrace: st);
                          if (!context.mounted) return;
                          showDialog(
                            context: context,
                            builder: (context) => ErrorDialog(
                              title: AppLocalizations.of(context)!.couldntImportPack,
                              message: AppLocalizations.of(context)!.checkPack,
                            ),
                          );
                        }
                      }
                      setState(() {});
                    },
                    mini: true,
                    child: const Icon(Icons.upload_file),
                  ),
                  const SizedBox(
                    width: 8,
                  ),
                  FloatingActionButton.extended(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    onPressed: () {
                      showDialog(context: context, builder: (_) => CreatePackDialog(packs)).then(
                        (_) => setState(() {
                          savePacks(packs);
                        }),
                      );
                    },
                    icon: Icon(
                      Icons.add,
                      color: Theme.of(context).colorScheme.onPrimary,
                    ),
                    label: Text(
                      AppLocalizations.of(context)!.createPack,
                      style: TextStyle(color: Theme.of(context).colorScheme.onPrimary),
                    ),
                  ),
                ],
              ),
        child: packs.isEmpty
            ? Padding(
                padding: const EdgeInsets.fromLTRB(8, 36, 8, 0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    Text(
                      AppLocalizations.of(context)!.noPacks,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    Opacity(
                      opacity: .8,
                      child: Text(
                        AppLocalizations.of(context)!.clickOnTheBottomRightToAddAStickerPack,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              )
            : DragSelectRegion(
                selection: () => {
                  for (int i = 0; i < packs.length; i++)
                    if (_selectedPacks.contains(packs[i])) i,
                },
                onSelectionChanged: _setPackSelection,
                child: ListView.separated(
                  separatorBuilder: (context, index) => Container(),
                  itemBuilder: (context, index) => DragSelectItem(
                    index: index,
                    child: StickerPackPreviewCard(
                      packs[index],
                      () {
                        setState(() {});
                      },
                      isSelectionMode: _isSelectionMode,
                      isSelected: _selectedPacks.contains(packs[index]),
                      onToggleSelect: () => _togglePackSelection(packs[index]),
                      onLongPress: () => DragSelectRegion.start(context, index),
                    ),
                  ),
                  itemCount: packs.length,
                ),
              ),
      ),
    );
  }
}
