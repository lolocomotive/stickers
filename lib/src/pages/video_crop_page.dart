import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:stickers/generated/intl/app_localizations.dart';
import 'package:stickers/src/data/sticker_pack.dart';
import 'package:stickers/src/dialogs/error_dialog.dart';
import 'package:stickers/src/globals.dart';
import 'package:stickers/src/pages/crop_page.dart';
import 'package:stickers/src/pages/default_page.dart';
import 'package:stickers/src/util.dart';
import 'package:stickers/src/video/common.dart';
import 'package:stickers/src/video/crop_scale.dart';
import 'package:stickers/src/widgets/crop_aspect_ratio_selector.dart';
import 'package:stickers/src/widgets/progress_bar_button.dart';
import 'package:stickers/src/widgets/video_crop_overlay.dart';
import 'package:video_player/video_player.dart';

class VideoCropPage extends StatefulWidget {
  final StickerPack pack;
  final int index;
  final String imagePath;
  final bool returnResult;

  const VideoCropPage({
    required this.pack,
    required this.index,
    required this.imagePath,
    this.returnResult = false,
    super.key,
  });

  static const routeName = "/crop_video";

  @override
  State<VideoCropPage> createState() => _VideoCropPageState();
}

class _VideoCropPageState extends State<VideoCropPage> {
  late final VideoPlayerController _controller;
  double _btnOpacity = 1;
  bool _ready = false;
  bool _exporting = false;
  RangeValues _range = const RangeValues(0, 1);
  Duration _seekTarget = Duration.zero;

  double? _aspectRatio;
  bool _stretch = false;
  double _speed = 1.0;
  int _rotationDegrees = 0;
  Rect? _cropRect;
  Size _videoRenderSize = Size.zero;

  static const List<double> _speedSteps = [0.25, 0.5, 1.0, 1.5, 2.0, 5.0, 10.0];


  String _formatSpeed(double speed) {
    return speed == speed.roundToDouble() ? "${speed.toInt()}x" : "${speed}x";
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    final tenths = (duration.inMilliseconds % 1000) ~/ 100;
    return '$minutes:${seconds.toString().padLeft(2, '0')}.$tenths';
  }

  String _formatClipDuration(Duration duration, double speed) {
    return '${(duration.inMilliseconds / speed / 1000).toStringAsFixed(1)}s';
  }

  final CropAndScaleService service = CropAndScaleService();
  bool _editing = false;
  bool _canSeek = true;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(
      File(widget.imagePath),
      viewType: VideoViewType.platformView,
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
    _controller.initialize().onError((e, st) {
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
    }).then((_) {
      if (mounted) {
        setState(() {
          _ready = true;
        });
      }
    });
    _controller.addListener(_videoListener);
    _controller.setVolume(0);
  }

  void _videoListener() {
    if (_editing) return;
    setState(() {});
    if (_controller.value.duration > Duration.zero &&
        _controller.value.position > _controller.value.duration * _range.end) {
      _requestSeek(_controller.value.duration * _range.start);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_videoListener);
    _controller.dispose();
    service.dispose();
    super.dispose();
  }

  double get _displayedAspectRatio {
    if (!_controller.value.isInitialized || _controller.value.aspectRatio == 0) {
      return 1.0;
    }
    final baseAspect = _controller.value.aspectRatio;
    if (_rotationDegrees % 180 != 0) {
      return 1.0 / baseAspect;
    }
    return baseAspect;
  }

  void _requestSeek(Duration time) async {
    _seekTarget = time;
    if (_canSeek) {
      _canSeek = false;
      await _controller.seekTo(time);
      await Future.delayed(const Duration(milliseconds: 100));
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
    Future.delayed(const Duration(seconds: 1)).then((_) {
      if (mounted) {
        _btnOpacity = 0;
        setState(() {});
      }
    });
  }

  void _togglePlayPause() {
    if (_controller.value.isPlaying) {
      _controller.pause();
      setState(() {});
    } else {
      _play();
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultActivity(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.trimVideo),
        actions: [
          IconButton(
            tooltip: AppLocalizations.of(context)!.rotateLeft,
            icon: const Icon(Icons.rotate_left),
            onPressed: () {
              setState(() {
                _rotationDegrees = (_rotationDegrees - 90 + 360) % 360;
              });
            },
          ),
          IconButton(
            tooltip: AppLocalizations.of(context)!.rotateRight,
            icon: const Icon(Icons.rotate_right),
            onPressed: () {
              setState(() {
                _rotationDegrees = (_rotationDegrees + 90) % 360;
              });
            },
          ),
        ],
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
                child: _ready
                    ? Center(
                        child: AspectRatio(
                          aspectRatio: _displayedAspectRatio,
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              _videoRenderSize = constraints.biggest;
                              return Stack(
                                children: [
                                  Positioned.fill(
                                    child: RotatedBox(
                                      quarterTurns: _rotationDegrees ~/ 90,
                                      child: VideoPlayer(_controller),
                                    ),
                                  ),
                                  Positioned.fill(
                                    child: VideoCropOverlay(
                                      aspectRatio: _aspectRatio,
                                      onCropChanged: (rect) {
                                        _cropRect = rect;
                                      },
                                      onTapVideo: _togglePlayPause,
                                    ),
                                  ),
                                  Center(
                                    child: IgnorePointer(
                                      child: AnimatedOpacity(
                                        opacity: _controller.value.isPlaying ? _btnOpacity : 1.0,
                                        duration: const Duration(milliseconds: 300),
                                        child: Icon(
                                          _controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
                                          color: Colors.white,
                                          shadows: const [Shadow(color: Colors.black, blurRadius: 32)],
                                          size: 80,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      )
                    : const Center(child: CircularProgressIndicator()),
              ),
            ),
            SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 8),
                  if (_ready && _controller.value.isInitialized && _controller.value.duration > Duration.zero) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _formatDuration(_controller.value.duration * _range.start),
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              _formatClipDuration(
                                _controller.value.duration * (_range.end - _range.start),
                                _speed,
                              ),
                              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: Theme.of(context).colorScheme.primary,
                                  ),
                            ),
                          ),
                          Text(
                            _formatDuration(_controller.value.duration * _range.end),
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 2),
                  ],
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4.0),
                    child: Stack(
                      children: [
                        RangeSlider(
                          values: _range,
                          onChangeEnd: (_) async {
                            if (_controller.value.isInitialized) {
                              if (_seekTarget == _controller.value.duration * _range.end) {
                                _requestSeek(_controller.value.duration * _range.end - const Duration(seconds: 1));
                                if (_seekTarget < _controller.value.duration * _range.start) {
                                  _seekTarget = _controller.value.duration * _range.start;
                                }
                              }
                              _play();
                              setState(() {});
                              await Future.delayed(const Duration(milliseconds: 200));
                              setState(() {});
                            }
                            _editing = false;
                          },
                          onChangeStart: (_) {
                            _controller.pause();
                            _editing = true;
                          },
                          onChanged: (values) {
                            if (!_controller.value.isInitialized) return;
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
                          },
                        ),
                        if (!_editing && _ready && _controller.value.duration.inMilliseconds > 0)
                          IgnorePointer(
                            child: Slider(
                              thumbColor: Theme.of(context).colorScheme.onSurface,
                              activeColor: Colors.transparent,
                              inactiveColor: Colors.transparent,
                              value: (_controller.value.position.inMilliseconds /
                                      _controller.value.duration.inMilliseconds)
                                  .clamp(0.0, 1.0),
                              onChanged: (_) {},
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: CropAspectRatioSelector(
                      aspectRatio: _aspectRatio,
                      onChanged: (ratio) {
                        setState(() {
                          _aspectRatio = ratio;
                        });
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Row(
                      children: [
                        Expanded(
                          child: SegmentedButton<bool>(
                            multiSelectionEnabled: false,
                            emptySelectionAllowed: false,
                            showSelectedIcon: false,
                            onSelectionChanged: (value) {
                              setState(() {
                                _stretch = value.first;
                              });
                            },
                            segments: [
                              ButtonSegment(
                                value: false,
                                icon: const Icon(Icons.fit_screen),
                                label: Text(AppLocalizations.of(context)!.fit),
                              ),
                              ButtonSegment(
                                value: true,
                                icon: const Icon(Icons.fullscreen),
                                label: Text(AppLocalizations.of(context)!.stretch),
                              ),
                            ],
                            selected: {_stretch},
                          ),
                        ),
                        const SizedBox(width: 8),
                        MenuAnchor(
                          builder: (context, controller, child) {
                            return OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(0, 40),
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                ),
                              ),
                              onPressed: () {
                                if (controller.isOpen) {
                                  controller.close();
                                } else {
                                  controller.open();
                                }
                              },
                              icon: const Icon(Icons.speed, size: 18),
                              label: Text(_formatSpeed(_speed)),
                            );
                          },
                          menuChildren: _speedSteps.map((speed) {
                            final isSelected = speed == _speed;
                            return MenuItemButton(
                              leadingIcon: isSelected
                                  ? Icon(Icons.check, size: 18, color: Theme.of(context).colorScheme.primary)
                                  : const SizedBox(width: 18),
                              onPressed: () {
                                setState(() {
                                  _speed = speed;
                                  _controller.setPlaybackSpeed(_speed);
                                  HapticFeedback.lightImpact();
                                });
                              },
                              child: Text(_formatSpeed(speed)),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    child: ProgressBarButton(
                      onPressed: _exporting ? null : () => doCrop(),
                      showProgress: _exporting,
                      progressIndicator: StreamBuilder(
                        stream: service.progressStream,
                        builder: (context, asyncSnapshot) {
                          return LinearProgressIndicator(
                            value: asyncSnapshot.data?.progress,
                          );
                        },
                      ),
                      child: Text(AppLocalizations.of(context)!.done),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> doCrop() async {
    if (_cropRect != null && (_cropRect!.width < 1.0 || _cropRect!.height < 1.0)) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(AppLocalizations.of(context)!.cropTooSmall),
          content: Text(AppLocalizations.of(context)!.cropTooSmallDetails),
          actions: [
            FilledButton(onPressed: () => Navigator.of(context).pop(), child: Text(AppLocalizations.of(context)!.ok)),
          ],
        ),
      );
      return;
    }

    setState(() {
      _exporting = true;
    });
    try {
      _controller.pause();
      final output = "$mediaCacheDir/import_${uid()}.mp4";

      double cropLeft = 0.0;
      double cropTop = 0.0;
      double cropRight = 1.0;
      double cropBottom = 1.0;

      if (_cropRect != null && _videoRenderSize.width > 0 && _videoRenderSize.height > 0) {
        cropLeft = (_cropRect!.left / _videoRenderSize.width).clamp(0.0, 1.0);
        cropTop = (_cropRect!.top / _videoRenderSize.height).clamp(0.0, 1.0);
        cropRight = (_cropRect!.right / _videoRenderSize.width).clamp(0.0, 1.0);
        cropBottom = (_cropRect!.bottom / _videoRenderSize.height).clamp(0.0, 1.0);
      }

      await service.start(
        inputFile: widget.imagePath,
        outputFile: output,
        start: _controller.value.duration * _range.start,
        end: _controller.value.duration * _range.end,
        speed: _speed,
        cropLeft: cropLeft,
        cropTop: cropTop,
        cropRight: cropRight,
        cropBottom: cropBottom,
        rotation: _rotationDegrees,
        stretch: _stretch,
      );
      await for (final s in service.progressStream) {
        if (s.status == Status.SUCCESS) {
          break;
        } else if (s.status == Status.FAILED) {
          print("Transcoding failed!");
          if (mounted) {
            showDialog(
                context: context,
                builder: (context) {
                  return ErrorDialog(
                      title: AppLocalizations.of(context)!.trimFailed,
                      message: AppLocalizations.of(context)!.trimFailedMsg);
                });
          }
          throw Exception();
        }
      }
      if (!mounted) return;
      final result = await Navigator.of(context).pushNamed(
        "/edit",
        arguments: EditArguments(
          pack: widget.pack,
          index: widget.index,
          mediaPath: output,
          type: StickerMediaType.video,
          returnResult: widget.returnResult,
        ),
      );
      if (widget.returnResult && mounted && result != null) {
        Navigator.of(context).pop(result);
      }
    } finally {
      if (mounted) {
        setState(() {
          _exporting = false;
        });
      }
    }
  }
}
