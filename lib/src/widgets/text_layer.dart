import 'dart:math';

import 'package:flutter/material.dart';
import 'package:image_editor/image_editor.dart';
import 'package:stickers/src/dialogs/edit_text_dialog.dart';
import 'package:stickers/src/fonts_api/fonts_registry.dart';
import 'package:stickers/src/pages/edit_page.dart';

class TextLayer extends StatefulWidget implements EditorLayer {
  final EditorText text;
  TextLayerState? state;

  final Function(TextLayer)? onDelete;

  final GlobalKey rbKey;

  bool openNextFrame;

  TextLayer(
    this.text, {
    super.key,
    this.onDelete,
    required this.rbKey,
    this.openNextFrame = true,
  });

  @override
  State<TextLayer> createState() {
    state = TextLayerState();
    return state!;
  }

  void update(Matrix4 matrix) {
    state?.update(matrix);
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      "type": "text",
      "text": text.text,
      "transform": text.transform.storage,
      "fontSize": text.fontSize,
      "textColor": text.textColor.toARGB32(),
      "fontName": text.fontName,
      "outlineColor": text.outlineColor.toARGB32(),
      "outlineWidth": text.outlineWidth,
    };
  }

  static TextLayer fromJson(Map<String, dynamic> json, GlobalKey rbKey) {
    final text = EditorText(
      text: json["text"],
      transform: Matrix4.fromList(json["transform"].map<double>((e) => e as double).toList()),
      fontSize: json["fontSize"],
      textColor: Color(json["textColor"]),
      fontName: json["fontName"],
      outlineColor: Color(json["outlineColor"]),
      outlineWidth: json["outlineWidth"],
    );

    final layer = TextLayer(text, rbKey: rbKey);
    return layer;
  }
}

class TextLayerState extends State<TextLayer> with TickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _editorKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    if (widget.openNextFrame) {
      WidgetsBinding.instance.addPostFrameCallback((_) => enableEditing());
    }
  }

  void enableEditing() {
    _controller.text = widget.text.text;
    showDialog(
      useRootNavigator: true,
      context: context,
      barrierDismissible: false,
      builder: (context) => Scaffold(
        backgroundColor: Colors.transparent,
        body: TextEditingDialog(
          key: _editorKey,
          rbKey: widget.rbKey,
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
            child: Stack(
              children: [
                Text(
                  widget.text.text,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    inherit: false,
                    fontSize: widget.text.fontSize * (FontsRegistry.sizeMultiplier(widget.text.fontName) ?? 1),
                    foreground: Paint()
                      ..strokeJoin = StrokeJoin.round
                      ..strokeCap = StrokeCap.round
                      ..color = widget.text.outlineColor
                      ..style = PaintingStyle.stroke
                      ..strokeWidth = widget.text.outlineWidth,
                    fontFamily: widget.text.fontName,
                  ),
                ),
                Text(
                  widget.text.text,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    inherit: false,
                    fontSize: widget.text.fontSize * (FontsRegistry.sizeMultiplier(widget.text.fontName) ?? 1),
                    color: widget.text.textColor,
                    fontFamily: widget.text.fontName,
                  ),
                ),
              ],
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
  final FontsRegistryEntry font;
  final bool active;

  const FontPreview(this.font, {super.key, this.active = false});

  @override
  Widget build(BuildContext context) {
    final double paddingDiff = MediaQuery.of(context).textScaler.scale(max(15 * (font.sizeMultiplier - 1), 0)) / 2;
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
                overflow: TextOverflow.fade,
                softWrap: false,
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
