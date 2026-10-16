import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:imagineos/features/library/image_edits.dart';

void main() {
  final drawing = image.Image(width: 4, height: 2, numChannels: 4);
  for (var y = 0; y < 2; y++) {
    for (var x = 0; x < 4; x++) {
      drawing.setPixelRgba(x, y, x * 50, y * 100, 80, x == 0 ? 0 : 255);
    }
  }
  final source = image.encodePng(drawing);

  test('crop keeps selected pixels, dimensions, alpha, and source bytes', () {
    final before = Uint8List.fromList(source);
    final result = renderCharacterEdits(EditRequest(source, const [
      CharacterEdit(CharacterEditKind.crop, Rect.fromLTRB(.25, 0, .75, 1)),
    ]));
    final cropped = image.decodePng(result.bytes)!;
    expect([result.width, result.height], [2, 2]);
    expect(cropped.getPixel(0, 1).r, 50);
    expect(cropped.getPixel(1, 1).r, 100);
    expect(source, before);
    final transparent = renderCharacterEdits(EditRequest(source, const [
      CharacterEdit(CharacterEditKind.crop, Rect.fromLTRB(0, 0, .5, 1)),
    ]));
    expect(image.decodePng(transparent.bytes)!.getPixel(0, 0).a, 0);
  });

  test('rotate and flip compose correctly; undo/reset replay from source', () {
    const rotate = CharacterEdit(CharacterEditKind.rotate);
    const flip = CharacterEdit(CharacterEditKind.flip);
    final rotated = renderCharacterEdits(EditRequest(source, [rotate]));
    expect([rotated.width, rotated.height], [2, 4]);
    expect(image.decodePng(rotated.bytes)!.getPixel(0, 0).g, 100);
    final flipped = renderCharacterEdits(EditRequest(source, [rotate, flip]));
    expect(image.decodePng(flipped.bytes)!.getPixel(0, 0).g, 0);
    expect(renderCharacterEdits(EditRequest(source, [rotate])).bytes,
        rotated.bytes);
    expect(renderCharacterEdits(EditRequest(source, [])).bytes, source);
  });

  test('invalid or empty crop is rejected instead of producing a broken file',
      () {
    for (final bounds in [
      const Rect.fromLTRB(-.1, 0, 1, 1),
      const Rect.fromLTRB(1, 0, 1, 1),
      const Rect.fromLTRB(0, 0, 1.1, 1),
      const Rect.fromLTRB(double.nan, 0, 1, 1),
    ]) {
      expect(
          () => renderCharacterEdits(EditRequest(source, [
                CharacterEdit(CharacterEditKind.crop, bounds),
              ])),
          throwsFormatException);
    }
  });
}
