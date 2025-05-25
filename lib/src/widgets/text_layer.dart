import 'package:flutter/material.dart';
import 'package:image_editor/image_editor.dart';
import 'package:stickers/src/pages/edit_page.dart';

class TextLayer extends StatefulWidget {
  final EditorText text;
  late final TextLayerState state;

  TextLayer(
    this.text, {
    super.key,
  });

  @override
  State<TextLayer> createState() {
    state = TextLayerState();
    return state;
  }

  void update(Matrix4 matrix) {
    state.update(matrix);
  }
}

class TextLayerState extends State<TextLayer> with TickerProviderStateMixin {
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
                fontSize: widget.text.fontSize,
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
