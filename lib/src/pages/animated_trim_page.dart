import 'dart:async';

import 'package:flutter/material.dart';
import 'package:stickers/generated/intl/app_localizations.dart';
import 'package:stickers/src/checker_painter.dart';
import 'package:stickers/src/data/sticker_pack.dart';
import 'package:stickers/src/dialogs/error_dialog.dart';
import 'package:stickers/src/pages/crop_page.dart';
import 'package:stickers/src/pages/default_page.dart';
import 'package:stickers/src/video/frame_decoder.dart';
import 'package:stickers/src/video/frame_player.dart';
import 'package:stickers/src/video/frame_export.dart';
import 'package:stickers/src/globals.dart';
import 'package:stickers/src/util.dart';

/// A trim page that uses frame-based playback to preserve alpha channels
/// Replaces video_crop_page.dart for transparency-aware media
class AnimatedTrimPage extends StatefulWidget {
  final StickerPack pack;
  final int index;
  final String mediaPath;

  const AnimatedTrimPage({
    required this.pack,
    required this.index,
    required this.mediaPath,
    super.key,
  });

  static const routeName = "/trim_animated";

  @override
  State<AnimatedTrimPage> createState() => _AnimatedTrimPageState();
}

class _AnimatedTrimPageState extends State<AnimatedTrimPage>
    with TickerProviderStateMixin {
  final FrameDecoderService _decoder = FrameDecoderService();
  FramePlayerController? _controller;

  bool _isLoading = true;
  bool _isExporting = false;
  String? _errorMessage;
  double _loadProgress = 0;
  double _exportProgress = 0;

  // Trim range (0.0 to 1.0)
  RangeValues _trimRange = const RangeValues(0.0, 1.0);
  bool _isDraggingTrim = false;
  bool _isEnforcingBounds = false; // Prevent infinite loop in listener

  // Playback indicator opacity
  double _playButtonOpacity = 1.0;

  @override
  void initState() {
    super.initState();
    _loadMedia();
  }

  Future<void> _loadMedia() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    // Listen to decode progress
    _decoder.progressStream.listen((progress) {
      if (mounted) {
        setState(() => _loadProgress = progress);
      }
    });

    final success = await _decoder.decode(widget.mediaPath);

    if (!mounted) return;

    if (success) {
      _controller = FramePlayerController(_decoder);
      _controller!.initialize(this);
      _controller!.setLooping(true);
      _controller!.addListener(_onPlaybackUpdate);
      _controller!.play();

      setState(() => _isLoading = false);
    } else {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to load media';
      });
    }
  }

  void _onPlaybackUpdate() {
    if (_isDraggingTrim) return;
    if (!mounted || _controller == null) return;
    if (_isEnforcingBounds) return; // Prevent re-entry

    // Enforce trim bounds during playback
    final normalized = _controller!.normalizedPosition;
    if (normalized < _trimRange.start) {
      _isEnforcingBounds = true;
      _controller!.seekToNormalized(_trimRange.start);
      _isEnforcingBounds = false;
    } else if (normalized > _trimRange.end) {
      _isEnforcingBounds = true;
      _controller!.seekToNormalized(_trimRange.start);
      _isEnforcingBounds = false;
    }

    setState(() {});
  }

  @override
  void dispose() {
    _controller?.removeListener(_onPlaybackUpdate);
    _controller?.dispose();
    _decoder.dispose();
    super.dispose();
  }

  void _togglePlayPause() {
    _controller?.togglePlayPause();

    if (_controller?.isPlaying == true) {
      _playButtonOpacity = 1.0;
      setState(() {});
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted && _controller?.isPlaying == true) {
          setState(() => _playButtonOpacity = 0.0);
        }
      });
    } else {
      setState(() => _playButtonOpacity = 1.0);
    }
  }

  Future<void> _exportTrimmed() async {
    if (_controller == null || !_decoder.isReady) return;

    setState(() {
      _isExporting = true;
      _exportProgress = 0;
    });

    try {
      _controller!.pause();

      // Calculate frame range
      final frameCount = _decoder.frames!.length;
      final startFrame = (_trimRange.start * frameCount).floor();
      var endFrame = (_trimRange.end * frameCount).ceil();

      // Ensure at least 2 frames if possible
      if (endFrame - startFrame < 2 && frameCount >= 2) {
        if (startFrame + 2 <= frameCount) {
          endFrame = startFrame + 2;
        } else {
          // If we can't extend forward, extend backward (only if startFrame > 0)
          // But we prefer extending forward.
          // This case (startFrame + 2 > frameCount) implies we are near the end.
          // Since endFrame <= frameCount, if startFrame + 2 > frameCount,
          // then startFrame >= frameCount - 1.
          // In that case we probably should have adjusted startFrame.
        }
      }
      endFrame = endFrame.clamp(startFrame + 1, frameCount);

      // Get trimmed frames (no re-encoding - just slice the frame list)
      final trimmedFrames = _decoder.frames!.sublist(startFrame, endFrame);

      // Validate frame count before export
      if (trimmedFrames.length < 2) {
        if (mounted) {
          String errorMessage;
          if (trimmedFrames.isEmpty) {
            errorMessage = AppLocalizations.of(
              context,
            )!.trimResultedInZeroFrames;
          } else {
            errorMessage = AppLocalizations.of(
              context,
            )!.trimResultedInSingleFrame;
          }
          _showError(errorMessage);
        }
        return;
      }

      // Export trimmed frames to animated WebP
      final exportService = FrameExportService();
      final outputPath = "$mediaCacheDir/trimmed_${uid()}.webp";
      final success = await exportService.exportFrames(
        frames: trimmedFrames,
        outputPath: outputPath,
        fps: _decoder.metadata!.fps,
        width: _decoder.metadata!.width,
        height: _decoder.metadata!.height,
        quality: 80,
      );

      if (!success) {
        if (mounted) _showError('Failed to export trimmed animation');
        return;
      }

      // Mark decoder frames as transferred (don't dispose them)
      _decoder.transferOwnership();

      // Invalidate controller to prevent using transferred (potentially disposed) frames
      // This safeguards against crashes if the next page disposes the frames
      final oldController = _controller;
      _controller = null;
      setState(() => _exportProgress = 1.0);
      oldController?.dispose();

      if (!mounted) return;

      // Navigate to edit page with the exported WebP file
      await Navigator.of(context).pushNamed(
        "/edit",
        arguments: EditArguments(
          pack: widget.pack,
          index: widget.index,
          mediaPath: outputPath, // Exported WebP file
          type: MediaType.animatedWebp,
          useFrameCache: false, // Not using cache
        ),
      );

      // Reload media on return to ensure we have valid frames
      if (mounted) {
        _loadMedia();
      }
    } catch (e) {
      if (mounted) _showError(e.toString());
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  void _showError(String message) {
    showDialog(
      context: context,
      builder: (context) => ErrorDialog(
        title: AppLocalizations.of(context)!.trimFailed,
        message: message,
      ),
    );
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
            Expanded(child: _buildPreview()),
            _buildControls(),
          ],
        ),
      ),
    );
  }

  Widget _buildPreview() {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(
              value: _loadProgress > 0 ? _loadProgress : null,
            ),
            const SizedBox(height: 16),
            Text('Loading... ${(_loadProgress * 100).toStringAsFixed(0)}%'),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(_errorMessage!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadMedia,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_controller == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Stack(
      children: [
        // Checkerboard background to show transparency
        Center(
          child: AspectRatio(
            aspectRatio: _controller!.aspectRatio,
            child: CustomPaint(
              painter: CheckerPainter(context),
              child: FramePlayerWidget(
                controller: _controller!,
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),
        // Play/pause overlay
        Center(
          child: AnimatedOpacity(
            opacity: _playButtonOpacity,
            duration: const Duration(milliseconds: 300),
            child: IconButton(
              onPressed: _togglePlayPause,
              icon: Icon(
                _controller!.isPlaying ? Icons.pause : Icons.play_arrow,
                color: Colors.white,
                shadows: const [Shadow(color: Colors.black, blurRadius: 32)],
              ),
              iconSize: 100,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildControls() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 10),
        // Trim range slider
        Stack(
          children: [
            RangeSlider(
              year2023: false,
              values: _trimRange,
              onChangeStart: (_) {
                _controller?.pause();
                _isDraggingTrim = true;
              },
              onChanged: (values) {
                // Enforce minimum of 2 frames selected while preserving the
                // non-dragged thumb. Detect which thumb moved and only adjust
                // the active one to satisfy the constraint.
                RangeValues adjustedValues = values;
                bool startMoved = values.start != _trimRange.start;
                bool endMoved = values.end != _trimRange.end;

                if (_decoder.frames != null) {
                  final frameCount = _decoder.frames!.length;

                  if (startMoved && !endMoved) {
                    // User moved start thumb: keep end fixed.
                    final fixedEndFrame = (_trimRange.end * frameCount).ceil();
                    int reqStartFrame = (values.start * frameCount).floor();
                    // Ensure at least 2 frames remain
                    if (fixedEndFrame - reqStartFrame < 2) {
                      reqStartFrame = (fixedEndFrame - 2).clamp(
                        0,
                        frameCount - 2,
                      );
                    }
                    adjustedValues = RangeValues(
                      reqStartFrame / frameCount,
                      _trimRange.end,
                    );
                  } else if (endMoved && !startMoved) {
                    // User moved end thumb: keep start fixed.
                    final fixedStartFrame = (_trimRange.start * frameCount)
                        .floor();
                    int reqEndFrame = (values.end * frameCount).ceil();
                    if (reqEndFrame - fixedStartFrame < 2) {
                      reqEndFrame = (fixedStartFrame + 2).clamp(2, frameCount);
                    }
                    adjustedValues = RangeValues(
                      _trimRange.start,
                      reqEndFrame / frameCount,
                    );
                  } else {
                    // Both moved or initial change: enforce minimum by adjusting
                    // end first, then start if necessary.
                    int startFrame = (values.start * frameCount).floor();
                    int endFrame = (values.end * frameCount).ceil();
                    if (endFrame - startFrame < 2) {
                      int newEnd = startFrame + 2;
                      if (newEnd <= frameCount) {
                        adjustedValues = RangeValues(
                          values.start,
                          newEnd / frameCount,
                        );
                      } else {
                        int newStart = (endFrame - 2).clamp(0, frameCount - 2);
                        adjustedValues = RangeValues(
                          newStart / frameCount,
                          values.end,
                        );
                      }
                    } else {
                      adjustedValues = RangeValues(
                        startFrame / frameCount,
                        endFrame / frameCount,
                      );
                    }
                  }
                }

                // Apply adjusted values and seek based on which thumb moved.
                setState(() => _trimRange = adjustedValues);
                if (startMoved && !endMoved) {
                  _controller?.seekToNormalized(adjustedValues.start);
                } else if (endMoved && !startMoved) {
                  _controller?.seekToNormalized(adjustedValues.end);
                } else if (startMoved && endMoved) {
                  // If both moved, seek to start to keep playback inside range.
                  _controller?.seekToNormalized(adjustedValues.start);
                }
              },
              onChangeEnd: (_) async {
                _isDraggingTrim = false;
                await Future.delayed(const Duration(milliseconds: 200));
                _controller?.seekToNormalized(_trimRange.start);
                _controller?.play();
                setState(() {});
              },
            ),
            // Playback position indicator
            if (!_isDraggingTrim && _controller != null && _decoder.isReady)
              IgnorePointer(
                child: Slider(
                  year2023: false,
                  value: _controller!.normalizedPosition.clamp(0.0, 1.0),
                  onChanged: (_) {},
                  thumbColor: Theme.of(context).colorScheme.onSurface,
                  activeColor: Colors.transparent,
                  inactiveColor: Colors.transparent,
                ),
              ),
          ],
        ),
        // Frame count info
        if (_decoder.metadata != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              '${_getSelectedFrameCount()} frames selected',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ),
        // Export button
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 16),
          child: FilledButton(
            onPressed: _isExporting ? null : _exportTrimmed,
            child: Column(
              children: [
                const SizedBox(height: 8),
                Text(AppLocalizations.of(context)!.done),
                const SizedBox(height: 8),
                if (_isExporting)
                  LinearProgressIndicator(
                    value: _exportProgress > 0 ? _exportProgress : null,
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  int _getSelectedFrameCount() {
    if (_decoder.frames == null) return 0;
    final frameCount = _decoder.frames!.length;
    final startFrame = (_trimRange.start * frameCount).floor();
    final endFrame = (_trimRange.end * frameCount).ceil();
    return (endFrame - startFrame).clamp(1, frameCount);
  }
}
