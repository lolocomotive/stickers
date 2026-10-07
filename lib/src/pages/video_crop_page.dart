import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

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
import 'package:stickers/src/video/gif_transcoder.dart';
import 'package:stickers/src/video/thumbnails.dart';
import 'package:stickers/src/widgets/crop_aspect_ratio_selector.dart';
import 'package:stickers/src/widgets/progress_bar_button.dart';
import 'package:stickers/src/widgets/video_crop_overlay.dart';
import 'package:stickers/src/widgets/video_trim_bar.dart';
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
  VideoPlayerController? _controller;
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

  bool _isGif = false;
  GifInfo? _gifInfo;
  static const int _thumbnailCount = 10;
  List<ui.Image?> _thumbnails = List.filled(_thumbnailCount, null);
  StreamSubscription<(int, ui.Image)>? _thumbnailSubscription;

  static const List<double> _speedSteps = [0.25, 0.5, 1.0, 1.5, 2.0, 5.0, 10.0];

  Duration get _effectiveDuration {
    if (_isGif) {
      return _gifInfo?.duration ?? const Duration(seconds: 1);
    }
    return _controller?.value.duration ?? Duration.zero;
  }

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
    _isGif = widget.imagePath.toLowerCase().endsWith('.gif');
    final isSupported = _isGif ? GifTranscoder.isGifFile(widget.imagePath) : isSupportedVideo(widget.imagePath);
    if (!isSupported) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        showUnsupportedFormatDialog(context).then((_) {
          if (mounted) Navigator.of(context).pop();
        });
      });
      return;
    }
    if (_isGif) {
      _initGif();
    } else {
      _initVideo();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_thumbnailSubscription == null && (_isGif || _controller != null)) {
      _loadThumbnails();
    }
  }

  void _loadThumbnails() {
    // Thumbnails are center-cropped to cover their cell, so their shorter side must match the
    // cell's larger dimension. Cells are usually taller than wide, except on wide screens.
    final trackWidth = MediaQuery.sizeOf(context).width - 32 - VideoTrimBar.defaultHandleWidth * 2;
    final cellExtent = math.max(VideoTrimBar.defaultHeight, trackWidth / _thumbnailCount);
    final shortSide = (cellExtent * MediaQuery.devicePixelRatioOf(context)).ceil();

    _thumbnailSubscription = loadVideoThumbnails(
      widget.imagePath,
      isGif: _isGif,
      count: _thumbnailCount,
      shortSide: shortSide,
    ).listen(
      (thumbnail) {
        final (index, image) = thumbnail;
        if (!mounted) {
          image.dispose();
          return;
        }
        setState(() {
          _thumbnails[index]?.dispose();
          _thumbnails = [..._thumbnails]..[index] = image;
        });
      },
      onError: (e) => debugPrint("Failed to load thumbnails: $e"),
    );
  }

  Future<void> _initGif() async {
    try {
      final info = await GifTranscoder.inspectGifFile(widget.imagePath);
      if (!mounted) return;
      if (info == null) {
        throw Exception("Could not decode GIF");
      }
      setState(() {
        _gifInfo = info;
        _ready = true;
      });
    } catch (e) {
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

  void _initVideo() {
    _controller = VideoPlayerController.file(
      File(widget.imagePath),
      viewType: VideoViewType.textureView,
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
    _controller!.initialize().onError((e, st) {
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
    _controller!.addListener(_videoListener);
    _controller!.setVolume(0);
  }

  void _videoListener() {
    if (_editing || _controller == null) return;
    setState(() {});
    if (_controller!.value.duration > Duration.zero &&
        _controller!.value.position > _controller!.value.duration * _range.end) {
      _requestSeek(_controller!.value.duration * _range.start);
    }
  }

  @override
  void dispose() {
    _thumbnailSubscription?.cancel();
    for (final image in _thumbnails) {
      image?.dispose();
    }
    _controller?.removeListener(_videoListener);
    _controller?.dispose();
    service.dispose();
    super.dispose();
  }

  void _requestSeek(Duration time) async {
    if (_controller == null) return;
    _seekTarget = time;
    if (_canSeek) {
      _canSeek = false;
      await _controller!.seekTo(time);
      await Future.delayed(const Duration(milliseconds: 100));
      _canSeek = true;
      if (_seekTarget != time) {
        _requestSeek(_seekTarget);
      }
    }
  }

  void _play() {
    if (_controller == null) return;
    _controller!.play();
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
    if (_controller == null) return;
    if (_controller!.value.isPlaying) {
      _controller!.pause();
      setState(() {});
    } else {
      _play();
    }
  }

  void _rotate(int degrees) {
    setState(() {
      _rotationDegrees = (_rotationDegrees + degrees + 360) % 360;
      if (_aspectRatio != null) {
        _aspectRatio = 1.0 / _aspectRatio!;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return DefaultActivity(
      appBar: AppBar(
        title: Text(_isGif ? AppLocalizations.of(context)!.cropGif : AppLocalizations.of(context)!.trimVideo),
        actions: [
          IconButton(
            tooltip: AppLocalizations.of(context)!.rotateLeft,
            icon: const Icon(Icons.rotate_left),
            onPressed: () => _rotate(-90),
          ),
          IconButton(
            tooltip: AppLocalizations.of(context)!.rotateRight,
            icon: const Icon(Icons.rotate_right),
            onPressed: () => _rotate(90),
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
                    ? VideoCropOverlay(
                        key: ValueKey(_rotationDegrees),
                        controller: _controller,
                        customPreview: _isGif
                            ? Image.file(
                                File(widget.imagePath),
                                fit: BoxFit.contain,
                                gaplessPlayback: true,
                              )
                            : null,
                        videoAspectRatio: _isGif && _gifInfo != null
                            ? _gifInfo!.width / _gifInfo!.height
                            : null,
                        rotationDegrees: _rotationDegrees,
                        aspectRatio: _aspectRatio,
                        onCropChanged: (rect) {
                          _cropRect = rect;
                        },
                        onTapVideo: _togglePlayPause,
                        btnOpacity: _isGif ? 0.0 : (_controller?.value.isPlaying == true ? _btnOpacity : 1.0),
                      )
                    : const Center(child: CircularProgressIndicator()),
              ),
            ),
            SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 8),
                  if (_ready && _effectiveDuration > Duration.zero) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _formatDuration(_effectiveDuration * _range.start),
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
                                _effectiveDuration * (_range.end - _range.start),
                                _speed,
                              ),
                              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: Theme.of(context).colorScheme.primary,
                                  ),
                            ),
                          ),
                          Text(
                            _formatDuration(_effectiveDuration * _range.end),
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
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: VideoTrimBar(
                      range: _range,
                      thumbnails: _thumbnails,
                      thumbnailRotation: _rotationDegrees,
                      showPlayhead: !_isGif && _ready && (_controller?.value.duration.inMilliseconds ?? 0) > 0,
                      playbackPosition: (_ready &&
                              _controller != null &&
                              _controller!.value.duration > Duration.zero)
                          ? (_controller!.value.position.inMilliseconds /
                                  _controller!.value.duration.inMilliseconds)
                              .clamp(0.0, 1.0)
                          : null,
                      onChangeStart: (_) {
                        _controller?.pause();
                        _editing = true;
                      },
                      onChangeEnd: (_) async {
                        if (_controller != null && _controller!.value.isInitialized) {
                          if (_seekTarget >= _controller!.value.duration * _range.end) {
                            _requestSeek(_controller!.value.duration * _range.end - const Duration(seconds: 1));
                            if (_seekTarget < _controller!.value.duration * _range.start) {
                              _seekTarget = _controller!.value.duration * _range.start;
                            }
                          }
                          _play();
                          setState(() {});
                          await Future.delayed(const Duration(milliseconds: 200));
                          setState(() {});
                        }
                        _editing = false;
                      },
                      onChanged: (values) {
                        if (_isGif) {
                          _range = values;
                          setState(() {});
                          return;
                        }
                        if (_controller == null || !_controller!.value.isInitialized) return;
                        final Duration seekTarget;
                        if (_range.start != values.start) {
                          seekTarget = _controller!.value.duration * values.start;
                        } else if (_range.end != values.end) {
                          seekTarget = _controller!.value.duration * values.end;
                        } else {
                          seekTarget = _controller!.value.duration * values.start;
                        }
                        _requestSeek(seekTarget);
                        _range = values;
                        setState(() {});
                      },
                      onSeek: (positionFraction) {
                        if (_controller == null || !_controller!.value.isInitialized) return;
                        final target = _controller!.value.duration * positionFraction;
                        _requestSeek(target);
                        setState(() {});
                      },
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
                                  _controller?.setPlaybackSpeed(_speed);
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
                      progressIndicator: _isGif
                          ? null
                          : StreamBuilder(
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
    if (_cropRect != null && (_cropRect!.width < 0.01 || _cropRect!.height < 0.01)) {
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
      _controller?.pause();

      final String output;
      if (_isGif) {
        final webpBytes = await GifTranscoder.transcodeToWebP(
          gifPath: widget.imagePath,
          cropRect: _cropRect,
          rotationDegrees: _rotationDegrees,
          stretch: _stretch,
          speed: _speed,
          startFraction: _range.start,
          endFraction: _range.end,
        );
        output = "$mediaCacheDir/import_${uid()}.webp";
        await File(output).writeAsBytes(webpBytes);
      } else {
        output = "$mediaCacheDir/import_${uid()}.mp4";
        final crop = _cropRect ?? const Rect.fromLTRB(0, 0, 1, 1);
        await service.start(
          inputFile: widget.imagePath,
          outputFile: output,
          start: _controller!.value.duration * _range.start,
          end: _controller!.value.duration * _range.end,
          speed: _speed,
          cropLeft: crop.left,
          cropTop: crop.top,
          cropRight: crop.right,
          cropBottom: crop.bottom,
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
    } catch (e) {
      if (_isGif && mounted) {
        showDialog(
          context: context,
          builder: (context) {
            return ErrorDialog(
              title: AppLocalizations.of(context)!.trimFailed,
              message: e.toString(),
            );
          },
        );
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
