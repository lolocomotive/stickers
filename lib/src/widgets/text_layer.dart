import 'dart:math';

import 'package:flutter/material.dart';
import 'package:image_editor/image_editor.dart';
import 'package:stickers/src/dialogs/edit_text_dialog.dart';
import 'package:stickers/src/globals.dart';
import 'package:stickers/src/pages/edit_page.dart';

class TextLayer extends StatefulWidget implements EditorLayer {
  final EditorText text;
  TextLayerState? state;

  final Function(TextLayer)? onDelete;

  TextLayer(
    this.text, {
    super.key,
    this.onDelete,
  });

  @override
  State<TextLayer> createState() {
    state = TextLayerState();
    return state!;
  }

  void update(Matrix4 matrix) {
    state?.update(matrix);
  }
}

class TextLayerState extends State<TextLayer> with TickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController(text: "");
  final _focusNode = FocusNode();
  final _editorKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => enableEditing());
  }

  void enableEditing() {
    showDialog(
      useRootNavigator: true,
      context: context,
      barrierDismissible: false,
      builder: (context) => Scaffold(
        backgroundColor: Colors.transparent,
        body: TextEditingDialog(
          key: _editorKey,
          disableEditing: disableEditing,
          controller: _controller,
          focusNode: _focusNode,
          parent: widget,
          onDelete: () {
            widget.onDelete?.call(widget);
          },
        ),
      ),
    ).then(
      (value) => setState(() {
        widget.text.text = _controller.text;
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Transform(
      origin: const Offset(0, 0),
      transform: widget.text.transform,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          GestureDetector(
            onTap: enableEditing,
            child: Text(
              _controller.text,
              textAlign: TextAlign.center,
              style: TextStyle(
                inherit: false,
                fontSize:
                    widget.text.fontSize * (fontsMap[widget.text.fontName]?.sizeMultiplier ?? 1),
                color: widget.text.textColor,
                fontFamily: fonts
                    .firstWhere((font) => font.fontName == widget.text.fontName,
                        orElse: () => fonts.first)
                    .family,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void update(Matrix4 matrix) {
    widget.text.transform = matrix;
    setState(() {});
  }

  void disableEditing() {
    Navigator.of(context).popUntil((route) => route.settings.name == EditPage.routeName);
  }
}

class FontPreview extends StatelessWidget {
  final PreviewFont font;
  final bool active;

  const FontPreview(this.font, {super.key, this.active = false});

  @override
  Widget build(BuildContext context) {
    final double paddingDiff =
        MediaQuery.of(context).textScaler.scale(max(15 * (font.sizeMultiplier - 1), 0)) / 2;
    return Column(
      children: [
        Container(
          padding: EdgeInsets.fromLTRB(12, 8 - paddingDiff, 12, 8 - paddingDiff),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: active
                ? (Theme.of(context).brightness == Brightness.light
                    ? Theme.of(context).colorScheme.primary.withAlpha(100)
                    : Theme.of(context).colorScheme.primary.withAlpha(50))
                : Colors.transparent,
          ),
          child: Baseline(
              baseline: MediaQuery.of(context).textScaler.scale(15),
              baselineType: TextBaseline.alphabetic,
              child: Text(
                font.display ?? font.family,
                style: TextStyle(
                    color: Colors.white,
                    fontFamily: font.family,
                    fontSize: MediaQuery.of(context).textScaler.scale(15 * font.sizeMultiplier)),
              )),
        ),
      ],
    );
  }
}
