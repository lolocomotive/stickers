import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:stickers/generated/intl/app_localizations.dart';
import 'package:stickers/src/globals.dart';
import 'package:stickers/src/widgets/text_layer.dart';

class TextEditingDialog extends StatefulWidget {
  final Function disableEditing;
  final TextEditingController controller;
  final FocusNode focusNode;
  final TextLayer parent;

  final GestureTapCallback? onDelete;

  TextEditingDialog({
    super.key,
    required this.disableEditing,
    required this.controller,
    required this.focusNode,
    required this.parent,
    this.onDelete,
  });

  @override
  State<TextEditingDialog> createState() => _TextEditingDialogState();
}

class _TextEditingDialogState extends State<TextEditingDialog> {
  int page = 0;
  bool _showSizeSlider = true;

  late final PageController _pageController;

  @override
  void initState() {
    if (fonts.where((f) => f.fontName == widget.parent.text.fontName).isNotEmpty) {
      page = fonts.indexWhere((f) => f.fontName == widget.parent.text.fontName);
    }
    _pageController = PageController(viewportFraction: .25, initialPage: page);
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
      child: LayoutBuilder(builder: (context, constraints) {
        final isHorizontal = constraints.maxWidth > constraints.maxHeight;
        final textField = Padding(
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
              color: widget.parent.text.textColor,
              fontFamily: fonts
                  .firstWhere((font) => font.fontName == widget.parent.text.fontName, orElse: () => fonts.first)
                  .family, //This is stupid
            ),
            cursorColor: widget.parent.text.textColor,
            backgroundCursorColor: widget.parent.text.textColor,
          ),
        );
        final topActionBar = GestureDetector(
          onTap: () => widget.disableEditing(),
          behavior: HitTestBehavior.opaque,
          child: Row(
            mainAxisSize: MainAxisSize.max,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 8.0, left: 12),
                child: IconButton(
                  tooltip: AppLocalizations.of(context)!.delete,
                  onPressed: () {
                    Navigator.of(context).pop();
                    widget.onDelete?.call();
                  },
                  icon: Icon(Icons.delete),
                  color: Colors.white,
                ),
              ),
              Expanded(
                child: IgnorePointer(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 12, top: 8.0),
                    child: Text(
                      AppLocalizations.of(context)!.done,
                      textAlign: TextAlign.end,
                      style: TextStyle(
                        fontSize: MediaQuery.of(context).textScaler.scale(18),
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
        final fontSelector = SizedBox(
          height: MediaQuery.of(context).textScaler.scale(15) + 24,
          child: PageView.builder(
            itemCount: fonts.length,
            onPageChanged: (page) {
              HapticFeedback.lightImpact();
              setState(() {});
              this.page = page;
              widget.parent.text.fontName = fonts[page].fontName ?? fonts[page].family;
            },
            pageSnapping: false,
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
        );
        final sliderAndColors = Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Column(
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: 512),
                child: Row(
                  mainAxisSize: MainAxisSize.max,
                  children: [
                    IconButton(
                      onPressed: () {
                        setState(() {
                          _showSizeSlider = true;
                        });
                      },
                      icon: Icon(
                        Icons.format_size,
                        color: Colors.white,
                      ),
                    ),
                    Expanded(
                      child: AnimatedCrossFade(
                          firstChild: Slider(
                            thumbColor: Colors.white,
                            activeColor: Colors.white,
                            min: 10,
                            max: 120,
                            value: widget.parent.text.fontSize,
                            onChanged: (newSize) {
                              if (newSize == 10 || newSize == 120) {
                                HapticFeedback.lightImpact();
                              }
                              setState(() {
                                widget.parent.text.fontSize = newSize;
                              });
                            },
                          ),
                          secondChild: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8.0),
                            child: Column(
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: colors
                                      .getRange(0, (colors.length / 2).floor())
                                      .map((c) => ColorButton(
                                            c,
                                            onTap: () => _setColor(c),
                                            active: c == widget.parent.text.textColor,
                                          ))
                                      .toList(),
                                ),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: colors
                                      .getRange((colors.length / 2).floor() + 1, colors.length)
                                      .map((c) => ColorButton(
                                            c,
                                            onTap: () => _setColor(c),
                                            active: c == widget.parent.text.textColor,
                                          ))
                                      .toList(),
                                )
                              ],
                            ),
                          ),
                          crossFadeState: _showSizeSlider ? CrossFadeState.showFirst : CrossFadeState.showSecond,
                          duration: Duration(milliseconds: 150)),
                    ),
                    IconButton(
                        onPressed: () {
                          setState(() {
                            _showSizeSlider = false;
                          });
                        },
                        icon: Icon(Icons.palette))
                  ],
                ),
              ),
            ],
          ),
        );
        return isHorizontal
            ? SizedBox(
                child: Row(
                  children: [
                    Expanded(child: textField),
                    Expanded(
                        child: SingleChildScrollView(
                      child: Column(
                        children: [
                          topActionBar,
                          fontSelector,
                          sliderAndColors,
                        ],
                      ),
                    ))
                  ],
                ),
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  topActionBar,
                  Expanded(
                      child: GestureDetector(
                    onTap: () => widget.disableEditing(),
                  )),
                  textField,
                  fontSelector,
                  sliderAndColors,
                  SizedBox(
                    height: 16,
                  )
                ],
              );
      }),
    );
  }

  _setColor(Color color) {
    setState(() {
      widget.parent.text.textColor = color;
    });
  }
}

class ColorButton extends StatelessWidget {
  final Color color;
  final GestureTapCallback? onTap;
  final bool active;

  final double? size;

  const ColorButton(
    this.color, {
    super.key,
    this.onTap,
    required this.active,
    this.size,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(2.0),
        child: Container(
          height: size ?? 23,
          width: size ?? 23,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(5),
            color: color,
            border: Border.all(
              color: active ? Theme.of(context).colorScheme.primary : Colors.transparent,
              width: 3,
            ),
          ),
        ),
      ),
    );
  }
}
