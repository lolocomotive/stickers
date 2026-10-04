import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

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
import 'package:stickers/src/video/trim_range.dart';
import 'package:stickers/src/video/video_timeline.dart';
import 'package:stickers/src/widgets/video_crop_overlay.dart';
import 'package:stickers/src/widgets/video_trim_timeline.dart';
import 'package:video_player/video_player.dart';

class VideoCropPage extends StatefulWidget {
  final StickerPack pack;
  final int index;
  final String imagePath;
  const VideoCropPage({
    required this.pack,
    required this.index,
    required this.imagePath,
    super.key,
  });

  static const routeName = "/crop_video";

  @override
  State<VideoCropPage> createState() => _VideoCropPageState();
}

class _VideoCropPageState extends State<VideoCropPage> {
  late final VideoPlayerController _controller;
  bool _ready = false;
  bool _exporting = false;
  RangeValues _range = const RangeValues(0, 1);
  Duration _seekTarget = Duration.zero;
  Future<void>? _seekTask;
  Duration? _scrubPosition;
  final ValueNotifier<Duration> _playhead = ValueNotifier(Duration.zero);
  final Stopwatch _seekClock = Stopwatch()..start();
  int _lastDragSeekMs = -80;
  Timer? _dragSeekTimer;
  Duration _pendingDragSeek = Duration.zero;
  bool _steppingFrame = false;
  bool _startingPlayback = false;
  bool _loopingSegment = false;
  bool _shouldPlaySegment = false;
  bool _playFromSelectionStart = false;
  TrimEdge _selectedEdge = TrimEdge.start;
  List<Uint8List?> _thumbnails = [];
  final VideoTimelineService _timelineService = VideoTimelineService();
  final ValueNotifier<Rect> _crop = ValueNotifier(const Rect.fromLTRB(0, 0, 1, 1));
  double? _aspectRatio;
  bool _stretch = false;
  int _quarterTurns = 0;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(
      File(widget.imagePath),
      viewType: VideoViewType.textureView,
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
    _initializeVideo();
    _controller.addListener(_videoListener);
    _controller.setVolume(0);
  }

  Future<void> _initializeVideo() async {
    try {
      await _controller.initialize();
      if (mounted) {
        setState(() => _ready = true);
        _loadThumbnails();
      }
    } on Exception catch (e) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => ErrorDialog(
          title: AppLocalizations.of(context)!.couldntLoadVideo,
          message: e.toString(),
        ),
      );
      if (mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _loadThumbnails() async {
    try {
      final frames = await _timelineService.thumbnails(widget.imagePath);
      if (mounted) setState(() => _thumbnails = frames);
    } on Exception {
      // The time controls remain usable if a decoder cannot produce previews.
    }
  }

  void _videoListener() {
    if (!_ready || !mounted) return;
    _playhead.value = _controller.value.position;
    if (_editing || _startingPlayback || _loopingSegment || !_shouldPlaySegment) return;
    if (_controller.value.position >= _controller.value.duration * _range.end || _controller.value.isCompleted) {
      _loopSelectedSegment();
    }
  }

  @override
  void dispose() {
    _dragSeekTimer?.cancel();
    _controller.dispose();
    _playhead.dispose();
    _crop.dispose();
    service.dispose();
    super.dispose();
  }

  void _setAspectRatio(double? ratio) {
    setState(() {
      _aspectRatio = ratio;
      if (ratio == null) return;
      final videoRatio = _quarterTurns.isOdd ? 1 / _controller.value.aspectRatio : _controller.value.aspectRatio;
      final width = ratio >= videoRatio ? 1.0 : ratio / videoRatio;
      final height = ratio >= videoRatio ? videoRatio / ratio : 1.0;
      _crop.value = Rect.fromLTWH((1 - width) / 2, (1 - height) / 2, width, height);
    });
  }

  void _rotate(int turns) {
    setState(() {
      _quarterTurns = (_quarterTurns + turns) % 4;
      _aspectRatio = null;
      _crop.value = const Rect.fromLTRB(0, 0, 1, 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final canExport =
        _ready &&
        !_exporting &&
        _controller.value.duration * (_range.end - _range.start) >= const Duration(milliseconds: 100);
    return PopScope(
      canPop: !_exporting,
      child: DefaultActivity(
        appBar: AppBar(
          title: Text(l10n.cropYourSticker),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => Column(
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
                              aspectRatio: _quarterTurns.isOdd
                                  ? 1 / _controller.value.aspectRatio
                                  : _controller.value.aspectRatio,
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  RepaintBoundary(
                                    child: RotatedBox(quarterTurns: _quarterTurns, child: VideoPlayer(_controller)),
                                  ),
                                  IgnorePointer(
                                    ignoring: _exporting,
                                    child: RepaintBoundary(
                                      child: ValueListenableBuilder<Rect>(
                                        valueListenable: _crop,
                                        builder: (context, crop, _) => VideoCropOverlay(
                                          crop: crop,
                                          aspectRatio: _aspectRatio,
                                          onChanged: (value) => _crop.value = value,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : const Center(child: CircularProgressIndicator()),
                  ),
                ),
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: math.min(420, constraints.maxHeight * .72)),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_ready) ...[
                          const SizedBox(height: 8),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: SegmentedButton<double>(
                              showSelectedIcon: false,
                              emptySelectionAllowed: true,
                              segments: const [
                                ButtonSegment(value: 16 / 9, label: Text('16:9')),
                                ButtonSegment(value: 3 / 2, label: Text('3:2')),
                                ButtonSegment(value: 1, label: Text('1:1')),
                                ButtonSegment(value: 2 / 3, label: Text('2:3')),
                                ButtonSegment(value: 9 / 16, label: Text('9:16')),
                              ],
                              selected: _aspectRatio == null ? {} : {_aspectRatio!},
                              onSelectionChanged: _exporting ? null : (values) => _setAspectRatio(values.firstOrNull),
                            ),
                          ),
                          const SizedBox(height: 8),
                          SegmentedButton<bool>(
                            showSelectedIcon: false,
                            segments: [
                              ButtonSegment(
                                value: false,
                                icon: const Icon(Icons.fit_screen),
                                label: Text(l10n.cropFit),
                              ),
                              ButtonSegment(
                                value: true,
                                icon: const Icon(Icons.fullscreen),
                                label: Text(l10n.cropStretch),
                              ),
                            ],
                            selected: {_stretch},
                            onSelectionChanged: _exporting ? null : (values) => setState(() => _stretch = values.first),
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              IconButton(
                                tooltip: l10n.rotateLeft,
                                onPressed: _exporting ? null : () => _rotate(3),
                                icon: const Icon(Icons.rotate_left),
                              ),
                              IconButton(
                                tooltip: l10n.rotateRight,
                                onPressed: _exporting ? null : () => _rotate(1),
                                icon: const Icon(Icons.rotate_right),
                              ),
                              ValueListenableBuilder<VideoPlayerValue>(
                                valueListenable: _controller,
                                builder: (context, video, _) => IconButton(
                                  tooltip: video.isPlaying ? l10n.previewPause : l10n.previewPlay,
                                  onPressed: _exporting || _steppingFrame || _startingPlayback
                                      ? null
                                      : video.isPlaying
                                      ? _pause
                                      : _play,
                                  icon: Icon(video.isPlaying ? Icons.pause : Icons.play_arrow),
                                ),
                              ),
                            ],
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              IconButton(
                                tooltip: l10n.trimOneFrameEarlier,
                                onPressed: _exporting || _steppingFrame || _startingPlayback
                                    ? null
                                    : () => _nudgeSelectedEdge(-1),
                                icon: const Icon(Icons.navigate_before),
                              ),
                              SegmentedButton<TrimEdge>(
                                showSelectedIcon: false,
                                segments: [
                                  ButtonSegment(value: TrimEdge.start, label: Text(l10n.trimStart)),
                                  ButtonSegment(value: TrimEdge.end, label: Text(l10n.trimEnd)),
                                ],
                                selected: {_selectedEdge},
                                onSelectionChanged: _exporting || _steppingFrame
                                    ? null
                                    : (values) => setState(() => _selectedEdge = values.first),
                              ),
                              IconButton(
                                tooltip: l10n.trimOneFrameLater,
                                onPressed: _exporting || _steppingFrame || _startingPlayback
                                    ? null
                                    : () => _nudgeSelectedEdge(1),
                                icon: const Icon(Icons.navigate_next),
                              ),
                            ],
                          ),
                        ],
                        if (_ready)
                          VideoTrimTimeline(
                            duration: _controller.value.duration,
                            range: _range,
                            playhead: _playhead,
                            positionOverride: _scrubPosition,
                            thumbnails: _thumbnails,
                            enabled:
                                !_exporting &&
                                !_steppingFrame &&
                                _controller.value.duration >= const Duration(milliseconds: 100),
                            onEdgeSelected: (edge) => setState(() => _selectedEdge = edge),
                            onRangeChangeStart: () {
                              _shouldPlaySegment = false;
                              _playFromSelectionStart = true;
                              _controller.pause();
                              setState(() => _editing = true);
                            },
                            onRangeChanged: _changeRange,
                            onRangeChangeEnd: () async {
                              final target = _scrubPosition ?? _seekTarget;
                              _dragSeekTimer?.cancel();
                              _dragSeekTimer = null;
                              await _requestSeek(target);
                              if (mounted) {
                                setState(() {
                                  _scrubPosition = null;
                                  _editing = false;
                                });
                              }
                            },
                            onSeekStart: () {
                              _shouldPlaySegment = false;
                              _playFromSelectionStart = false;
                              _controller.pause();
                              setState(() => _editing = true);
                            },
                            onSeekChanged: (time) {
                              setState(() => _scrubPosition = time);
                              _scheduleDragSeek(time);
                            },
                            onSeekEnd: (time) async {
                              _dragSeekTimer?.cancel();
                              _dragSeekTimer = null;
                              await _requestSeek(time);
                              if (mounted) {
                                setState(() {
                                  _scrubPosition = null;
                                  _editing = false;
                                });
                              }
                            },
                          ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(10, 8, 10, 16),
                          child: FilledButton(
                            clipBehavior: Clip.antiAlias,
                            style: ButtonStyle(
                              padding: WidgetStateProperty.all(EdgeInsets.zero),
                            ),
                            onPressed: canExport ? doCrop : null,
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
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _changeRange(RangeValues values) {
    _playFromSelectionStart = true;
    final duration = _controller.value.duration;
    final minSpan = 100000 / duration.inMicroseconds;
    final RangeValues next;
    Duration seek;
    if (values.start != _range.start) {
      next = RangeValues(values.start.clamp(0.0, _range.end - minSpan), _range.end);
      seek = duration * next.start;
    } else {
      next = RangeValues(_range.start, values.end.clamp(_range.start + minSpan, 1.0));
      seek = duration * next.end;
      if (seek == duration) seek = duration - const Duration(microseconds: 1);
    }
    setState(() {
      _range = next;
      _scrubPosition = seek;
    });
    _scheduleDragSeek(seek);
  }

  void _scheduleDragSeek(Duration time) {
    _pendingDragSeek = time;
    final remainingMs = 80 - (_seekClock.elapsedMilliseconds - _lastDragSeekMs);
    if (remainingMs <= 0) {
      _dragSeekTimer?.cancel();
      _dragSeekTimer = null;
      _lastDragSeekMs = _seekClock.elapsedMilliseconds;
      _requestSeek(time);
    } else {
      _dragSeekTimer ??= Timer(Duration(milliseconds: remainingMs), () {
        _dragSeekTimer = null;
        _lastDragSeekMs = _seekClock.elapsedMilliseconds;
        _requestSeek(_pendingDragSeek);
      });
    }
  }

  Future<void> _requestSeek(Duration time) {
    if (!_ready || !mounted) return Future.value();
    _seekTarget = time;
    return _seekTask ??= _drainSeeks();
  }

  Future<void> _drainSeeks() async {
    try {
      while (mounted) {
        final target = _seekTarget;
        await _controller.seekTo(target);
        if (target == _seekTarget) break;
      }
    } finally {
      _seekTask = null;
    }
  }

  Future<void> _nudgeSelectedEdge(int direction) async {
    if (!_ready || _steppingFrame || _startingPlayback || _exporting) return;
    _shouldPlaySegment = false;
    setState(() => _steppingFrame = true);
    try {
      await _controller.pause();
      if (!mounted) return;
      final duration = _controller.value.duration;
      final edge = _selectedEdge;
      final boundary = duration * (edge == TrimEdge.start ? _range.start : _range.end);
      final adjacent = await _timelineService.adjacentFrame(widget.imagePath, boundary, direction);
      if (!mounted) return;
      // The final frame's right edge is the video duration, not another sample timestamp.
      final frame = edge == TrimEdge.end && direction > 0 && adjacent == boundary ? duration : adjacent;
      final next = moveTrimBoundary(duration: duration, range: _range, edge: edge, frame: frame);
      if (next == null) return;
      final preview = edge == TrimEdge.start
          ? duration * next.start
          : duration * next.end - const Duration(microseconds: 1);
      _playFromSelectionStart = true;
      setState(() {
        _range = next;
        _scrubPosition = preview;
        _editing = true;
      });
      await _requestSeek(preview);
      if (mounted) {
        setState(() {
          _scrubPosition = null;
          _editing = false;
        });
      }
    } on Exception catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) {
        setState(() {
          _steppingFrame = false;
          _editing = false;
        });
      }
    }
  }

  void _pause() {
    _shouldPlaySegment = false;
    _controller.pause();
  }

  Future<void> _play() async {
    if (!_ready || _exporting || _startingPlayback) return;
    _shouldPlaySegment = false;
    _dragSeekTimer?.cancel();
    _dragSeekTimer = null;
    setState(() => _startingPlayback = true);
    try {
      await _controller.pause();
      final duration = _controller.value.duration;
      final requested = _scrubPosition ?? _controller.value.position;
      final restart = playbackRestartPosition(
        duration: duration,
        range: _range,
        position: requested,
        selectionChanged: _playFromSelectionStart,
        completed: _controller.value.isCompleted,
      );
      if (restart != null) {
        await _requestSeek(restart);
      } else if (_seekTask != null || _scrubPosition != null) {
        await _requestSeek(requested);
      }
      if (!mounted || _exporting) return;
      _playFromSelectionStart = false;
      _scrubPosition = null;
      _editing = false;
      _shouldPlaySegment = true;
      await _controller.play();
    } on Exception catch (error) {
      _shouldPlaySegment = false;
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _startingPlayback = false);
    }
  }

  Future<void> _loopSelectedSegment() async {
    if (_loopingSegment) return;
    _loopingSegment = true;
    try {
      await _controller.pause();
      await _requestSeek(_controller.value.duration * _range.start);
      if (mounted && _shouldPlaySegment && !_editing && !_exporting) await _controller.play();
    } on Exception catch (error) {
      _shouldPlaySegment = false;
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      _loopingSegment = false;
    }
  }

  final CropAndScaleService service = CropAndScaleService();

  bool _editing = false;

  Future<void> doCrop() async {
    if (!_ready ||
        _exporting ||
        _controller.value.duration == Duration.zero ||
        _controller.value.duration * (_range.end - _range.start) < const Duration(milliseconds: 100)) {
      return;
    }
    final trimFailedMessage = AppLocalizations.of(context)!.trimFailedMsg;
    setState(() {
      _exporting = true;
    });
    final completion = Completer<Progress>();
    final progressSubscription = service.progressStream.listen((progress) {
      if (!completion.isCompleted &&
          (progress.status == Status.SUCCESS ||
              progress.status == Status.FAILED ||
              progress.status == Status.CANCELLED)) {
        completion.complete(progress);
      }
    });
    try {
      _shouldPlaySegment = false;
      _controller.pause();
      final output = "$mediaCacheDir/import_${uid()}.mp4";
      await service.start(
        inputFile: widget.imagePath,
        outputFile: output,
        start: _controller.value.duration * _range.start,
        end: _controller.value.duration * _range.end,
        crop: _crop.value,
        stretch: _stretch,
        quarterTurns: _quarterTurns,
      );
      final progress = await completion.future.timeout(const Duration(minutes: 3));
      if (progress.status != Status.SUCCESS) throw Exception(trimFailedMessage);
      if (!mounted) return;
      Navigator.of(context).pushNamed(
        "/edit",
        arguments: EditArguments(
          pack: widget.pack,
          index: widget.index,
          mediaPath: output,
          type: .video,
        ),
      );
    } on Exception catch (e) {
      if (mounted) {
        showDialog<void>(
          context: context,
          builder: (context) => ErrorDialog(title: AppLocalizations.of(context)!.trimFailed, message: e.toString()),
        );
      }
    } finally {
      await progressSubscription.cancel();
      if (mounted) setState(() => _exporting = false);
    }
  }
}
