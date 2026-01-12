import 'dart:async';
import 'dart:io';

import 'package:extended_image/extended_image.dart' hide MediaType;
import 'package:flutter/material.dart';
import 'package:stickers/generated/intl/app_localizations.dart';
import 'package:stickers/src/data/sticker_pack.dart';
import 'package:stickers/src/dialogs/error_dialog.dart';
import 'package:stickers/src/globals.dart';
import 'package:stickers/src/pages/crop_page.dart';
import 'package:stickers/src/pages/default_page.dart';
import 'package:stickers/src/util.dart';
import 'package:stickers/src/video/common.dart';
import 'package:stickers/src/video/crop_scale.dart';
import 'package:stickers/src/video/frame_decoder.dart';
import 'package:video_player/video_player.dart';
import 'package:ffmpeg_kit_flutter_new_video/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_video/return_code.dart';
import 'package:path_provider/path_provider.dart';

class VideoCropPage extends StatefulWidget {
  final StickerPack pack;
  final int index;
  final String imagePath;
  final GlobalKey<ExtendedImageEditorState> editorKey =
      GlobalKey<ExtendedImageEditorState>();

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

class _VideoCropPageState extends State<VideoCropPage>
    with TickerProviderStateMixin {
  late final AnimationController _maskColorController;
  late VideoPlayerController _controller;
  late String _activeVideoPath;
  double _btnOpacity = 0;
  bool _ready = false;
  bool _exporting = false;
  bool _converting = false;
  bool _wasPlaying = false;
  bool _wasPlayingBeforeEdit = false;
  RangeValues _range = RangeValues(0, 1);

  @override
  void initState() {
    super.initState();
    _maskColorController = AnimationController(vsync: this);
    _activeVideoPath = widget.imagePath;
    Tween<double> tween = Tween(begin: 0.0, end: 1.0);
    Animation anim = CurvedAnimation(
      parent: _maskColorController,
      curve: Curves.ease,
      reverseCurve: Curves.ease,
    );
    anim.drive(tween);
    _maskColorController.addListener(_animationListener);
    _controller = VideoPlayerController.file(
      File(widget.imagePath),
      viewType: VideoViewType.textureView,
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
    _controller
        .initialize()
        .then((_) {
          if (mounted) {
            setState(() {
              _ready = true;
            });
            _controller.play();
          }
        })
        .catchError((e) {
          print("Video initialization failed: $e. Attempting conversion...");
          if (mounted) setState(() => _converting = true);
          _convertAndReloadError(widget.imagePath);
        });
    _controller.addListener(_videoListener);
    _controller.setVolume(0);
  }

  void _videoListener() {
    setState(() {});
    if (_editing) return;
    final start = _controller.value.duration * _range.start;
    final end = _controller.value.duration * _range.end;
    if (_controller.value.isPlaying) {
      _wasPlaying = true;
    } else if (_wasPlaying && _controller.value.position >= end) {
      _requestSeek(start);
      _controller.play();
      _wasPlaying = false;
    }
    if (_controller.value.position < start ||
        _controller.value.position >= end) {
      _requestSeek(start);
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
        title: Text(AppLocalizations.of(context)!.trimVideo),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Container(
                // The clip and empty BoxDecoration is intentional, sometimes the done button doesn't appear otherwise
                // See: https://github.com/lolocomotive/stickers/issues/1
                clipBehavior: Clip.antiAlias,
                decoration: const BoxDecoration(),
                child: !_ready
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(),
                            if (_converting) ...[
                              SizedBox(height: 16),
                              Text(
                                "Converting video format...",
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ],
                          ],
                        ),
                      )
                    : Stack(
                        children: [
                          Center(
                            child: AspectRatio(
                              aspectRatio: _controller.value.aspectRatio,
                              child: VideoPlayer(_controller),
                            ),
                          ),
                          Center(
                            child: !_editing
                                ? (_controller.value.isPlaying
                                      ? AnimatedOpacity(
                                          opacity: _controller.value.isPlaying
                                              ? _btnOpacity
                                              : 1.0,
                                          duration: Duration(milliseconds: 300),
                                          child: IconButton(
                                            onPressed: () {
                                              _controller.pause();
                                              setState(() {});
                                            },
                                            icon: Icon(
                                              Icons.pause,
                                              color: Colors.white,
                                              shadows: [
                                                Shadow(
                                                  color: Colors.black,
                                                  blurRadius: 32,
                                                ),
                                              ],
                                            ),
                                            iconSize: 100,
                                          ),
                                        )
                                      : AnimatedOpacity(
                                          opacity: _controller.value.isPlaying
                                              ? _btnOpacity
                                              : 1.0,
                                          duration: Duration(milliseconds: 300),
                                          child: IconButton(
                                            onPressed: _play,
                                            icon: Icon(
                                              Icons.play_arrow,
                                              color: Colors.white,
                                              shadows: [
                                                Shadow(
                                                  color: Colors.black,
                                                  blurRadius: 32,
                                                ),
                                              ],
                                            ),
                                            iconSize: 100,
                                          ),
                                        ))
                                : null,
                          ),
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
                        if (_wasPlayingBeforeEdit) _controller.play();
                        setState(() {});
                        await Future.delayed(Duration(milliseconds: 200));
                        setState(() {});
                        _editing = false;
                      },
                      onChangeStart: (_) {
                        setState(() {
                          _wasPlayingBeforeEdit = _controller.value.isPlaying;
                          _controller.pause();
                          _editing = true;
                        });
                      },
                      onChanged: (values) {
                        // Detect which thumb moved
                        bool startMoved = values.start != _range.start;
                        bool endMoved = values.end != _range.end;

                        RangeValues adjustedValues = values;
                        final totalDuration = _controller.value.duration;
                        final minDiff = 16.0 / totalDuration.inMilliseconds;

                        if (startMoved && !endMoved) {
                          // User moved start thumb: keep end fixed
                          double fixedEnd = _range.end;
                          double reqStart = values.start;
                          if (fixedEnd - reqStart < minDiff) {
                            reqStart = (fixedEnd - minDiff).clamp(
                              0.0,
                              fixedEnd,
                            );
                          }
                          adjustedValues = RangeValues(reqStart, fixedEnd);
                        } else if (endMoved && !startMoved) {
                          // User moved end thumb: keep start fixed
                          double fixedStart = _range.start;
                          double reqEnd = values.end;
                          if (reqEnd - fixedStart < minDiff) {
                            reqEnd = (fixedStart + minDiff).clamp(
                              fixedStart,
                              1.0,
                            );
                          }
                          adjustedValues = RangeValues(fixedStart, reqEnd);
                        } else {
                          // Both moved or initial: enforce minimum by adjusting end first
                          if (adjustedValues.end - adjustedValues.start <
                              minDiff) {
                            double newEnd = (adjustedValues.start + minDiff)
                                .clamp(adjustedValues.start, 1.0);
                            if (newEnd - adjustedValues.start >= minDiff) {
                              adjustedValues = RangeValues(
                                adjustedValues.start,
                                newEnd,
                              );
                            } else {
                              double newStart = (adjustedValues.end - minDiff)
                                  .clamp(0.0, adjustedValues.end);
                              adjustedValues = RangeValues(
                                newStart,
                                adjustedValues.end,
                              );
                            }
                          }
                        }

                        final Duration seekTarget;
                        if (_range.start != adjustedValues.start) {
                          seekTarget = totalDuration * adjustedValues.start;
                        } else if (_range.end != adjustedValues.end) {
                          seekTarget = totalDuration * adjustedValues.end;
                        } else {
                          return;
                        }
                        _range = adjustedValues;
                        _requestSeek(seekTarget);
                      },
                    ),
                    if (!_editing && _ready)
                      IgnorePointer(
                        child: Slider(
                          thumbColor: Theme.of(context).colorScheme.onSurface,
                          activeColor: Colors.transparent,
                          inactiveColor: Colors.transparent,
                          value: _controller.value.duration.inMilliseconds > 0
                              ? (_controller.value.position.inMilliseconds /
                                        _controller
                                            .value
                                            .duration
                                            .inMilliseconds)
                                    .clamp(0.0, 1.0)
                              : 0.0,
                          onChanged: (_) {},
                          year2023: false,
                        ),
                      ),
                  ],
                ),
                if (_ready)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      '${_getSelectedDuration()} selected',
                      style: Theme.of(context).textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 16),
                  child: FilledButton(
                    clipBehavior: Clip.antiAlias,
                    style: ButtonStyle(
                      padding: WidgetStateProperty.all(EdgeInsets.zero),
                    ),
                    onPressed: _exporting ? null : () => doCrop(),
                    child: Column(
                      children: [
                        SizedBox(height: 8),
                        Text(AppLocalizations.of(context)!.done),
                        SizedBox(height: 8),
                        if (_exporting)
                          StreamBuilder(
                            stream: service.progressStream,
                            builder: (context, asyncSnapshot) {
                              return LinearProgressIndicator(
                                value: asyncSnapshot.data?.progress,
                              );
                            },
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _requestSeek(Duration time) {
    _controller.seekTo(time);
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
    setState(() {
      _exporting = true;
    });
    try {
      _controller.pause();
      final output = "$mediaCacheDir/import_${uid()}.mp4";

      // Get the video's fps for accurate frame-based trimming
      final totalDuration = _controller.value.duration;
      // Estimate fps from video controller (typically videos are 24-30 fps)
      // This is used to calculate a half-frame buffer for accurate end time
      final estimatedFps =
          24.0; // Default, will be refined by FFprobe in service

      await service.start(
        inputFile: _activeVideoPath,
        outputFile: output,
        start: totalDuration * _range.start,
        end: totalDuration * _range.end,
        fps: estimatedFps,
      );
      await for (final s in service.progressStream) {
        if (s.status == Status.success) {
          break;
        } else if (s.status == Status.failed) {
          print("Transcoding failed!");
          if (mounted) {
            showDialog(
              context: context,
              builder: (context) {
                return ErrorDialog(
                  title: AppLocalizations.of(context)!.trimFailed,
                  message: AppLocalizations.of(context)!.trimFailedMsg,
                );
              },
            );
          }
          throw Exception();
        }
      }
      if (!mounted) return;

      // Validate the output video has enough frames
      final frameInfo = await MediaValidator.getQuickFrameInfo(output);
      if (!frameInfo.hasEnoughFrames) {
        // Show error dialog and prevent navigation
        if (mounted) {
          String errorMessage;
          if (frameInfo.isEmpty) {
            errorMessage = AppLocalizations.of(
              context,
            )!.trimResultedInZeroFrames;
          } else if (frameInfo.isSingleFrame) {
            errorMessage = AppLocalizations.of(
              context,
            )!.trimResultedInSingleFrame;
          } else {
            errorMessage =
                frameInfo.error ??
                AppLocalizations.of(
                  context,
                )!.animatedStickersMustHaveAtLeast2Frames;
          }
          showDialog(
            context: context,
            builder: (context) {
              return ErrorDialog(
                title: AppLocalizations.of(context)!.trimFailed,
                message: errorMessage,
              );
            },
          );
        }
        // Clean up the invalid output file
        try {
          await File(output).delete();
        } catch (_) {}
        return;
      }

      if (!mounted) return;

      Navigator.of(context).pushNamed(
        "/edit",
        arguments: EditArguments(
          pack: widget.pack,
          index: widget.index,
          mediaPath: output,
          type: MediaType.video,
        ),
      );
    } finally {
      setState(() {
        _exporting = false;
      });
    }
  }

  Future<void> _convertAndReloadError(String originalPath) async {
    final tempDir = await getTemporaryDirectory();
    final tempPath = "${tempDir.path}/converted_${uid()}.mp4";

    // Use executeWithArguments to handle paths with spaces correctly and avoid shell parsing issues
    final arguments = [
      '-y',
      '-i',
      originalPath,
      '-vf',
      'scale=trunc(iw/2)*2:trunc(ih/2)*2',
      '-c:v',
      'mpeg4',
      '-pix_fmt',
      'yuv420p',
      '-q:v',
      '4',
      '-c:a',
      'aac',
      tempPath,
    ];

    print("Executing FFmpeg conversion: $arguments");

    await FFmpegKit.executeWithArguments(arguments).then((session) async {
      final returnCode = await session.getReturnCode();

      if (ReturnCode.isSuccess(returnCode)) {
        print("Conversion successful. Reloading controller with $tempPath");
        if (!mounted) return;

        final newController = VideoPlayerController.file(
          File(tempPath),
          viewType: VideoViewType.textureView,
          videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
        );

        newController
            .initialize()
            .then((_) {
              if (mounted) {
                setState(() {
                  _controller.dispose();
                  _controller = newController;
                  _activeVideoPath = tempPath;
                  _controller.addListener(_videoListener);
                  _controller.setVolume(0);
                  _ready = true;
                  _converting = false;
                });
                _controller.play();
              } else {
                newController.dispose();
              }
            })
            .catchError((e) {
              if (mounted) setState(() => _converting = false);
              print("Converted video also failed to load: $e");
              _showError(e);
            });
      } else {
        if (mounted) setState(() => _converting = false);
        print(
          "FFmpeg conversion failed with state ${await session.getState()} and rc $returnCode",
        );
        print(await session.getLogsAsString());
        _showError("Video conversion failed");
      }
    });
  }

  String _getSelectedDuration() {
    final totalDuration = _controller.value.duration;
    final selectedDuration = totalDuration * (_range.end - _range.start);
    return getDurationString(selectedDuration);
  }

  void _showError(Object e) {
    if (mounted) {
      showDialog(
        context: context,
        builder: (context) {
          return ErrorDialog(
            title: AppLocalizations.of(context)!.couldntLoadVideo,
            message: e.toString(),
          );
        },
      ).then((_) {
        if (mounted) Navigator.of(context).pop();
      });
    }
  }
}
