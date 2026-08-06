import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

import '../core/constants.dart';

/// An image chosen by the user, already read into memory.
///
/// Bytes rather than a path: the web build has no filesystem paths, and the
/// upload API takes bytes anyway.
class PickedImage {
  final String name;
  final Uint8List bytes;

  const PickedImage({required this.name, required this.bytes});

  int get size => bytes.length;

  String get readableSize {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(0)} KB';
    return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// Raised when a pick fails or the chosen image is rejected.
class ImagePickerException implements Exception {
  final String message;
  const ImagePickerException(this.message);

  @override
  String toString() => message;
}

/// Wraps `package:image_picker` so callers get bytes and plain errors.
///
/// The picker is resized on the way in ([_maxDimension]) because camera
/// originals are routinely 8–12 MB, which would fail the size check for no
/// benefit — these are evidence photos, not print assets.
class ImagePickerService {
  ImagePickerService({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  static const double _maxDimension = 1920;
  static const int _quality = 85;

  /// Pick from the photo library. Returns null if the user cancels.
  Future<PickedImage?> pickFromGallery() => _pick(ImageSource.gallery);

  /// Take a photo. Returns null if the user cancels.
  ///
  /// Not available on the web desktop build — [ImageSource.camera] falls back
  /// to a file dialog there.
  Future<PickedImage?> pickFromCamera() => _pick(ImageSource.camera);

  Future<PickedImage?> _pick(ImageSource source) async {
    final XFile? file;
    try {
      file = await _picker.pickImage(
        source: source,
        maxWidth: _maxDimension,
        maxHeight: _maxDimension,
        imageQuality: _quality,
      );
    } on Object catch (e) {
      // Platform channels throw PlatformException, and a missing permission
      // surfaces the same way; both are useless to the user as raw text.
      throw ImagePickerException('Could not open the image picker: $e');
    }
    if (file == null) return null;

    final bytes = await file.readAsBytes();
    if (bytes.length > AppConstants.maxImageBytes) {
      final limit = AppConstants.maxImageBytes ~/ (1024 * 1024);
      throw ImagePickerException(
        '${file.name} is too large — the limit is $limit MB.',
      );
    }

    final extension = file.name.split('.').last.toLowerCase();
    if (!AppConstants.imageExtensions.contains(extension)) {
      throw ImagePickerException(
        'Only ${AppConstants.imageExtensions.join(', ')} images are accepted.',
      );
    }

    return PickedImage(name: file.name, bytes: bytes);
  }
}
