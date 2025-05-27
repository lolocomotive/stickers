import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_editor/image_editor.dart';
import 'package:stickers/src/globals.dart';
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
      barrierDismissible: false,
      builder: (context) => Scaffold(
        backgroundColor: Colors.transparent,
        body: TextEditingDialog(
          disableEditing: disableEditing,
          controller: _controller,
          focusNode: _focusNode,
          parent: widget,
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
                fontFamily:
                    fonts.firstWhere((font) => font.fontName == widget.text.fontName, orElse: () => fonts.first).family,
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

class TextEditingDialog extends StatefulWidget {
  final Function disableEditing;
  final TextEditingController controller;
  final FocusNode focusNode;
  final TextLayer parent;

  TextEditingDialog(
      {super.key,
      required this.disableEditing,
      required this.controller,
      required this.focusNode,
      required this.parent});

  @override
  State<TextEditingDialog> createState() => _TextEditingDialogState();
}

class _TextEditingDialogState extends State<TextEditingDialog> {
  int page = 0;

  final PageController _pageController = PageController(viewportFraction: .35);

  @override
  Widget build(BuildContext context) {
    if (fonts.where((f) => f.fontName == widget.parent.text.fontName).isNotEmpty) {
      _pageController.jumpToPage(fonts.indexWhere((f) => f.fontName == widget.parent.text.fontName));
    }
    return Focus(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Expanded(
              child: GestureDetector(
            onTap: () => widget.disableEditing(),
          )),
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: EditableText(
              autofocus: true,
              onEditingComplete: () {
                widget.disableEditing();
              },
              maxLines: null,
              cursorOpacityAnimates: true,
              scrollPhysics: const NeverScrollableScrollPhysics(),
              controller: widget.controller,
              textAlign: TextAlign.center,
              focusNode: widget.focusNode,
              style: TextStyle(
                inherit: false,
                fontSize: widget.parent.text.fontSize,
                fontFamily: fonts
                    .firstWhere((font) => font.fontName == widget.parent.text.fontName, orElse: () => fonts.first)
                    .family, //This is stupid
              ),
              cursorColor: Colors.white,
              backgroundCursorColor: Colors.white,
            ),
          ),
          SizedBox(
            height: MediaQuery.of(context).textScaler.scale(25) + 48,
            child: PageView.builder(
              itemCount: fonts.length,
              onPageChanged: (page) {
                HapticFeedback.lightImpact();
                setState(() {
                  this.page = page;
                  widget.parent.text.fontName = fonts[page].fontName ?? fonts[page].family;
                });
              },
              pageSnapping: true,
              controller: _pageController,
              itemBuilder: (context, i) {
                return GestureDetector(
                  onTap: () {
                    _pageController.animateToPage(
                      i,
                      duration: Duration(milliseconds: 150),
                      curve: Curves.easeInOutQuad,
                    );
                  },
                  child: FontPreview(
                    fonts[i].family,
                    display: fonts[i].display,
                    active: page == i,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class FontPreview extends StatelessWidget {
  final String family;
  final String? display;
  final bool active;

  const FontPreview(this.family, {super.key, this.display, this.active = false});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: EdgeInsets.fromLTRB(12, 8, 12, 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: active
                ? (Theme.of(context).brightness == Brightness.light
                    ? Theme.of(context).colorScheme.primary.withAlpha(100)
                    : Theme.of(context).colorScheme.primary.withAlpha(50))
                : Theme.of(context).brightness == Brightness.light
                    ? Colors.black12
                    : Colors.white10,
          ),
          child: Baseline(
              baseline: family == "PressStart2P"
                  ? MediaQuery.of(context).textScaler.scale(25) + 5
                  : MediaQuery.of(context).textScaler.scale(25),
              baselineType: TextBaseline.alphabetic,
              child: Text(display ?? family,
                  style: TextStyle(
                    color: Colors.white,
                    fontFamily: family,
                    fontSize: MediaQuery.of(context).textScaler.scale(25),
                  ))),
        ),
      ],
    );
  }
}
