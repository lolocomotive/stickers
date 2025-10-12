// Enums and classes to mirror the Kotlin side
enum Status { IDLE, RUNNING, SUCCESS, FAILED, CANCELLED }

class Progress {
  final Status status;
  final double progress;
  final int currentFrame;
  final int totalFrames;

  Progress({
    this.status = Status.IDLE,
    this.progress = 0.0,
    this.currentFrame = 0,
    this.totalFrames = 0,
  });

  @override
  String toString() {
    return 'Progress{status: $status, progress: $progress, currentFrame: $currentFrame, totalFrames: $totalFrames}';
  }
}

enum WebPImageHint {
  defaultHint,
  picture,
  photo,
  graph,
}

class WebPConfig {
  final bool? lossless;
  final double? quality;
  final int? method;
  final WebPImageHint? imageHint;
  final int? targetSize;
  final double? targetPSNR;
  final int? segments;
  final int? snsStrength;
  final int? filterStrength;
  final int? filterSharpness;
  final int? filterType;
  final bool? autofilter;
  final int? alphaCompression;
  final int? alphaFiltering;
  final int? alphaQuality;
  final int? pass;
  final bool? showCompressed;
  final int? preprocessing;
  final int? partitions;
  final int? partitionLimit;
  final bool? emulateJpegSize;
  final bool? threadLevel;
  final bool? lowMemory;
  final int? nearLossless;
  final bool? exact;

  const WebPConfig({
    this.lossless,
    this.quality,
    this.method,
    this.imageHint,
    this.targetSize,
    this.targetPSNR,
    this.segments,
    this.snsStrength,
    this.filterStrength,
    this.filterSharpness,
    this.filterType,
    this.autofilter,
    this.alphaCompression,
    this.alphaFiltering,
    this.alphaQuality,
    this.pass,
    this.showCompressed,
    this.preprocessing,
    this.partitions,
    this.partitionLimit,
    this.emulateJpegSize,
    this.threadLevel,
    this.lowMemory,
    this.nearLossless,
    this.exact,
  });

  Map<String, dynamic> toMap() {
    return {
      'lossless': lossless,
      'quality': quality,
      'method': method,
      'imageHint': imageHint?.name,
      'targetSize': targetSize,
      'targetPSNR': targetPSNR,
      'segments': segments,
      'snsStrength': snsStrength,
      'filterStrength': filterStrength,
      'filterSharpness': filterSharpness,
      'filterType': filterType,
      'autofilter': autofilter,
      'alphaCompression': alphaCompression,
      'alphaFiltering': alphaFiltering,
      'alphaQuality': alphaQuality,
      'pass': pass,
      'showCompressed': showCompressed,
      'preprocessing': preprocessing,
      'partitions': partitions,
      'partitionLimit': partitionLimit,
      'emulateJpegSize': emulateJpegSize,
      'threadLevel': threadLevel,
      'lowMemory': lowMemory,
      'nearLossless': nearLossless,
      'exact': exact,
    }..removeWhere((key, value) => value == null);
  }
}
