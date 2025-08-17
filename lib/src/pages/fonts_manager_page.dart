import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:stickers/src/dialogs/delete_confirm_dialog.dart';
import 'package:stickers/src/fonts_api/fonts_registry.dart';
import 'package:stickers/src/pages/default_page.dart';
import 'package:stickers/src/settings/settings_page.dart';

import 'fonts_search_page.dart';

class FontsManagerPage extends StatefulWidget {
  static const routeName = "${SettingsPage.routeName}/fonts";

  const FontsManagerPage({super.key});

  @override
  State<FontsManagerPage> createState() => _FontsManagerPageState();
}

class _FontsManagerPageState extends State<FontsManagerPage> {
  @override
  Widget build(BuildContext context) {
    return DefaultSliverActivity(
        title: "Fonts manager",
        child: ReorderableListView.builder(
          footer: ListTile(
            onTap: () {
              Navigator.of(context).push(MaterialPageRoute(builder: (context) => FontsSearchPage())).then((_) {
                setState(() {});
              });
            },
            leading: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14.0),
              child: Icon(Icons.add),
            ),
            title: Text("Add more"),
          ),
          buildDefaultDragHandles: false,
          itemCount: FontsRegistry.fontCount,
          onReorderStart: (i) {
            HapticFeedback.lightImpact();
          },
          itemBuilder: (context, i) {
            return ReorderableDelayedDragStartListener(
              index: i,
              key: ValueKey(i),
              child: ListTile(
                leading: IconButton(
                  onPressed: () async {
                    final shouldDelete = await showDialog(
                        context: context, builder: (context) => DeleteConfirmDialog(FontsRegistry.at(i).family));
                    if (shouldDelete) {
                      FontsRegistry.delete(FontsRegistry.at(i).family);
                      setState(() {});
                    }
                  },
                  icon: Icon(Icons.delete),
                ),
                title: Text(
                  FontsRegistry.at(i).family,
                  style: TextStyle(fontFamily: FontsRegistry.at(i).family),
                ),
                trailing: ReorderableDragStartListener(
                  index: i,
                  child: Opacity(
                    opacity: .5,
                    child: Icon(Icons.reorder),
                  ),
                ),
              ),
            );
          },
          onReorder: (int oldIndex, int newIndex) {
            FontsRegistry.reorder(oldIndex, newIndex);
            setState(() {});
          },
        ));
  }
}
