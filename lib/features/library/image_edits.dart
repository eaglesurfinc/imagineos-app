import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:image/image.dart' as image;

import 'character_store.dart' show maxOriginalBytes;

enum CharacterEditKind { crop, rotate, flip }

class CharacterEdit {
  const CharacterEdit(this.kind,
      [this.bounds = const Rect.fromLTWH(0, 0, 1, 1)]);
  final CharacterEditKind kind;
  final Rect bounds;
}

class EditRequest {
  const EditRequest(this.source, this.edits);
  final Uint8List source;
  final List<CharacterEdit> edits;
}

class EditPreview {
  const EditPreview(this.bytes, this.width, this.height);
  final Uint8List bytes;
  final int width, height;
}

// Replay a short command history instead of retaining large decoded undo images.
// This runs in an isolate on native platforms; Flutter Web runs compute locally.
EditPreview renderCharacterEdits(EditRequest request) {
  final decoded = image.decodeImage(request.source, frame: 0);
  if (decoded == null)
    throw const FormatException('Could not open this image.');
  var drawing = image.bakeOrientation(decoded);
  for (final edit in request.edits) {
    switch (edit.kind) {
      case CharacterEditKind.crop:
        final rect = edit.bounds;
        if (!rect.isFinite ||
            rect.left < 0 ||
            rect.top < 0 ||
            rect.right > 1 ||
            rect.bottom > 1 ||
            rect.width <= 0 ||
            rect.height <= 0) {
          throw const FormatException('Choose a crop area inside the image.');
        }
        final left = (rect.left * drawing.width).floor();
        final top = (rect.top * drawing.height).floor();
        final right = (rect.right * drawing.width).ceil();
        final bottom = (rect.bottom * drawing.height).ceil();
        drawing = image.copyCrop(drawing,
            x: left, y: top, width: right - left, height: bottom - top);
      case CharacterEditKind.rotate:
        drawing = image.copyRotate(drawing, angle: 90);
      case CharacterEditKind.flip:
        drawing = image.flipHorizontal(drawing);
    }
  }
  final bytes = request.edits.isEmpty
      ? request.source
      : image.encodePng(drawing, level: 6);
  if (bytes.length > maxOriginalBytes) {
    throw const FormatException(
        'The edited PNG exceeds 5 MB. Try a smaller crop first.');
  }
  return EditPreview(bytes, drawing.width, drawing.height);
}
