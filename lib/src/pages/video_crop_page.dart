import 'dart:async';
import 'dart:io';

import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:stickers/generated/intl/app_localizations.dart';
import 'package:stickers/src/data/sticker_pack.dart';
import 'package:stickers/src/pages/default_page.dart';
import 'package:stickers/src/video/crop_scale.dart';
import 'package:video_player/video_player.dart';

class VideoCropPage extends StatefulWidget {
  final StickerPack pack;
  final int index;
  final String imagePath;
  final GlobalKey<ExtendedImageEditorState> editorKey = GlobalKey<ExtendedImageEditorState>();

  VideoCropPage({
    required this.pack,
    required this.index,
    required this.imagePath,
    super.key,
  });

  static const routeName = "/crop_video";

  @override
  State<VideoCropPage> createState() => _VideoCropPageState();
}

class _VideoCropPageState extends State<VideoCropPage> with TickerProviderStateMixin {
  late final AnimationController _maskColorController;
  final ImageEditorController _editorController = ImageEditorController();
  late final VideoPlayerController _controller;
  double _btnOpacity = 1;

  RangeValues _range = RangeValues(0, 1);
  bool _previousPtrVal = false;
  Duration _seekTarget = Duration();

  @override
  void initState() {
    super.initState();
    _maskColorController = AnimationController(vsync: this);
    Tween<double> tween = Tween(begin: 0.0, end: 1.0);
    Animation anim = CurvedAnimation(parent: _maskColorController, curve: Curves.ease, reverseCurve: Curves.ease);
    anim.drive(tween);
    _maskColorController.addListener(_animationListener);
    _controller = VideoPlayerController.file(File(widget.imagePath), viewType: VideoViewType.platformView);
    _controller.initialize().then((_) => setState(() {}));
    _controller.addListener(_videoListener);
    _controller.setVolume(0);
  }

  void _videoListener() {
    if (_editing) return;
    setState(() {});
    if (_controller.value.position > _controller.value.duration * _range.end) {
      _requestSeek(_controller.value.duration * _range.start);
    }
  }

  void _animationListener() {
    setState(() {});
  }

  @override
  void dispose() {
    super.dispose();
    _maskColorController.removeListener(_animationListener);
    _maskColorController.dispose();
    _controller.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultActivity(
      appBar: AppBar(
        title: Text("Crop and trim video"),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Container(
              // The clip and empty BoxDecoration is intentional, sometimes the done button doesn't appear otherwise
              // See: https://github.com/lolocomotive/stickers/issues/1
              clipBehavior: Clip.antiAlias,
              decoration: const BoxDecoration(),
              child: Stack(
                children: [
                  Center(
                    child: AspectRatio(
                      aspectRatio: _controller.value.aspectRatio,
                      child: VideoPlayer(_controller),
                    ),
                  ),
                  Center(
                    child: _controller.value.isPlaying
                        ? AnimatedOpacity(
                            opacity: _btnOpacity,
                            duration: Duration(milliseconds: 300),
                            child: IconButton(
                              onPressed: () {
                                _controller.pause();
                                setState(() {});
                              },
                              icon: Icon(
                                Icons.pause,
                                color: Colors.white,
                                shadows: [Shadow(color: Colors.black, blurRadius: 32)],
                              ),
                              iconSize: 100,
                            ),
                          )
                        : IconButton(
                            onPressed: _play,
                            icon: Icon(
                              Icons.play_arrow,
                              color: Colors.white,
                              shadows: [Shadow(color: Colors.black, blurRadius: 32)],
                            ),
                            iconSize: 100,
                          ),
                  )
                ],
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 10,
              ),
              Stack(
                children: [
                  RangeSlider(
                      year2023: false,
                      values: _range,
                      onChangeEnd: (_) async {
                        if (_seekTarget == _controller.value.duration * _range.end) {
                          _requestSeek(_controller.value.duration * _range.end - Duration(seconds: 1));
                          if (_seekTarget < _controller.value.duration * _range.start) {
                            _seekTarget = _controller.value.duration * _range.start;
                          }
                        }
                        _play();
                        setState(() {});
                        await Future.delayed(Duration(milliseconds: 200));
                        setState(() {});
                        _editing = false;
                      },
                      onChangeStart: (_) {
                        _controller.pause();
                        _editing = true;
                      },
                      onChanged: (values) {
                        final Duration seekTarget;
                        if (_range.start != values.start) {
                          seekTarget = _controller.value.duration * values.start;
                        } else if (_range.end != values.end) {
                          seekTarget = _controller.value.duration * values.end;
                        } else {
                          return;
                        }
                        _requestSeek(seekTarget);
                        _range = values;
                        setState(() {});
                      }),
                  if (!_editing)
                    IgnorePointer(
                      child: Slider(
                        thumbColor: Theme.of(context).colorScheme.onSurface,
                        activeColor: Colors.transparent,
                        inactiveColor: Colors.transparent,
                        value: _controller.value.position.inMilliseconds / _controller.value.duration.inMilliseconds,
                        onChanged: (_) {},
                        year2023: false,
                      ),
                    ),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    onPressed: () {
                      _editorController.rotate(degree: -90, animation: true);
                    },
                    icon: Icon(Icons.rotate_left),
                  ),
                  IconButton(
                    onPressed: () {
                      _editorController.rotate(degree: 90, animation: true);
                    },
                    icon: Icon(Icons.rotate_right),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 16),
                child: FilledButton(
                  clipBehavior: Clip.antiAlias,
                  style: ButtonStyle(
                    padding: WidgetStateProperty.all(EdgeInsets.zero),
                  ),
                  onPressed: () => doCrop(),
                  child: Column(
                    children: [
                      SizedBox(height: 8),
                      Text(AppLocalizations.of(context)!.done),
                      SizedBox(height: 8),
                      StreamBuilder(
                          stream: service.progressStream,
                          builder: (context, asyncSnapshot) {
                            return LinearProgressIndicator(
                              value: asyncSnapshot.data?.progress,
                            );
                          })
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  bool _canSeek = true;

  void _requestSeek(Duration time) async {
    _seekTarget = time;
    if (_canSeek) {
      _canSeek = false;
      await _controller.seekTo(time);
      await Future.delayed(Duration(milliseconds: 100));
      _canSeek = true;
      if (_seekTarget != time) {
        _requestSeek(_seekTarget);
      }
    }
  }

  void _play() {
    _controller.play();
    _btnOpacity = 1;
    setState(() {});
    Future.delayed(Duration(seconds: 1)).then((_) {
      _btnOpacity = 0;
      setState(() {});
    });
  }

  CropAndScaleService service = CropAndScaleService();

  bool _editing = false;

  Future<void> doCrop() async {
    service.start(inputFile: widget.imagePath, outputFile: "${(await getTemporaryDirectory()).path}/temp.mp4");
  }
}
