import 'package:flutter/services.dart';

class ImageViewerService {
  static const MethodChannel _channel = MethodChannel('com.devson.ragadl/image_viewer');

  /// Open native image viewer with zoom and pan capabilities
  ///
  /// [imagePath] - Path to the image to open initially
  /// [imageList] - List of all image paths for gallery view
  /// [initialIndex] - Index of the initial image in the list
  static Future<bool> openImageViewer({
    required String imagePath,
    required List<String> imageList,
    int initialIndex = 0,
  }) async {
    try {
      final bool result = await _channel.invokeMethod('openImageViewer', {
        'imagePath': imagePath,
        'imageList': imageList,
        'initialIndex': initialIndex,
      });
      return result;
    } on PlatformException catch (e) {
      print('Error opening image viewer: ${e.message}');
      return false;
    }
  }

  /// Open native video player
  ///
  /// [videoPath] - Path to the video file
  static Future<bool> openVideoPlayer({
    required String videoPath,
  }) async {
    try {
      final bool result = await _channel.invokeMethod('openVideoPlayer', {
        'videoPath': videoPath,
      });
      return result;
    } on PlatformException catch (e) {
      print('Error opening video player: ${e.message}');
      return false;
    }
  }
}
