// Local-only review of a user-supplied photo. Outputs belong under ignored
// build/. Never add source photos or review images to the public repository.
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as image;

import '../lib/features/drawing/drawing_pixels.dart';

void main(List<String> arguments) {
  if (arguments.length != 2) {
    stderr.writeln(
        'Usage: dart run tool/preview_paper.dart <photo> <output.png>');
    exitCode = 64;
    return;
  }
  final source = File(arguments[0]);
  final bytes = source.readAsBytesSync();
  final before = sha256.convert(bytes).toString();
  final result = processDrawingPixels(RasterRequest(bytes,
      operation: DrawingPixelOperation.paper, tolerance: 100));
  final output = File(arguments[1]);
  final previewFile = File('${output.path}.white.png');
  for (final target in [output, previewFile]) {
    if (source.absolute.path.toLowerCase() ==
            target.absolute.path.toLowerCase() ||
        (target.existsSync() &&
            FileSystemEntity.identicalSync(source.path, target.path))) {
      throw ArgumentError('Choose separate output paths.');
    }
  }
  output.parent.createSync(recursive: true);
  output.writeAsBytesSync(result.bytes);
  final extracted = image.decodePng(result.bytes)!;
  final preview = image.Image(
      width: extracted.width, height: extracted.height, numChannels: 4);
  image.fill(preview, color: image.ColorRgba8(255, 255, 255, 255));
  image.compositeImage(preview, extracted);
  previewFile.writeAsBytesSync(image.encodePng(preview));
  if (sha256.convert(source.readAsBytesSync()).toString() != before ||
      sha256.convert(bytes).toString() != before) {
    throw StateError('Source bytes changed');
  }
  stdout.writeln('Local extraction: ${result.width} x ${result.height}; '
      '${(result.paperCleared! * 100).toStringAsFixed(2)}% of all pixels made transparent. '
      'This is not a paper-removal success score. Original unchanged.');
}
