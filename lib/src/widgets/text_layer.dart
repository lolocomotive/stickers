import 'package:flutter/material.dart';
import 'package:image_editor/image_editor.dart';
import 'package:matrix_gesture_detector/matrix_gesture_detector.dart';
import 'package:stickers/src/pages/edit_page.dart';

class TextLayer extends StatefulWidget {
  final EditorText text;
  const TextLayer(
    this.text, {
    super.key,
  });

  @override
  State<TextLayer> createState() => _TextLayerState();
}

class _TextLayerState extends State<TextLayer> with TickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController(text: "");
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => enableEditing());
  }

  void enableEditing() {
    showDialog(
      useRootNavigator: true,
      context: context,
      builder: (context) => Scaffold(
        backgroundColor: Colors.transparent,
        body: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Focus(
                onFocusChange: (value) {
                  if (!value) {
                    disableEditing();
                  }
                },
                child: EditableText(
                  autofocus: true,
                  onEditingComplete: () {
                    disableEditing();
                  },
                  onTapOutside: (_) {
                    disableEditing();
                  },
                  maxLines: null,
                  cursorOpacityAnimates: true,
                  scrollPhysics: const NeverScrollableScrollPhysics(),
                  controller: _controller,
                  textAlign: TextAlign.center,
                  focusNode: _focusNode,
                  style: TextStyle(
                    inherit: false,
                    fontSize: widget.text.fontSize,
                  ),
                  cursorColor: Colors.white,
                  backgroundCursorColor: Colors.white,
                ),
              ),
            ),
          ],
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
    return MatrixGestureDetector(
      onMatrixUpdate: (matrix, translationDeltaMatrix, scaleDeltaMatrix, rotationDeltaMatrix) {
        widget.text.transform = matrix;
        setState(() {});
      },
      shouldRotate: true,
      shouldScale: true,
      shouldTranslate: true,
      child: Transform(
        origin: const Offset(0, 0),
        transform: widget.text.transform,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            GestureDetector(
              onTap: () {
                enableEditing();
              },
              child: Text(
                _controller.text,
                textAlign: TextAlign.center,
                style: TextStyle(
                  inherit: false,
                  fontSize: widget.text.fontSize,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void disableEditing() {
    Navigator.of(context).popUntil((route) => route.settings.name == EditPage.routeName);
  }
}
