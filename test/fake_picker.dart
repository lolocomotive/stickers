import 'dart:async';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';

class FakePicker extends ImagePickerPlatform {
  List<XFile> images = [];
  Completer<List<XFile>>? pending;
  Exception? error;
  int multiCalls = 0;
  int singleCalls = 0;
  int videoCalls = 0;
  int? limit;

  @override
  Future<List<XFile>> getMultiImageWithOptions({
    MultiImagePickerOptions options = const MultiImagePickerOptions(),
  }) async {
    multiCalls++;
    limit = options.limit;
    if (error != null) throw error!;
    if (pending != null) return pending!.future;
    return images;
  }

  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async {
    singleCalls++;
    return images.isEmpty ? null : images.first;
  }

  @override
  Future<XFile?> getVideo({
    required ImageSource source,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    Duration? maxDuration,
  }) async {
    videoCalls++;
    return images.isEmpty ? null : images.first;
  }
}
