import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

/// Fixed logical geometry; device width scales the sheet, never rewrites or
/// reflows the stored words. Height grows to include every line, without ellipsis.
class StoryTextLayout {
  StoryTextLayout(this.dialogue, this.narration) {
    dialogueHeight = measure(dialogue);
    narrationHeight = measure(narration);
  }
  static const width = 600.0, inset = 32.0, artHeight = 360.0;
  static const style = TextStyle(
      fontSize: 20,
      height: 1.4,
      fontFamily: 'Nunito',
      color: Color(0xff183844));
  final String dialogue, narration;
  late final double dialogueHeight, narrationHeight;
  double get height =>
      inset * 2 +
      artHeight +
      (dialogue.isEmpty ? 0 : dialogueHeight + inset) +
      (narration.isEmpty ? 0 : narrationHeight + inset);

  static double measure(String text) {
    if (text.isEmpty) return 0;
    final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: TextDirection.ltr,
        textScaler: TextScaler.noScaling)
      ..layout(maxWidth: width - inset * 2);
    final height = painter.height;
    painter.dispose();
    return height;
  }
}

class StoryPreview extends StatelessWidget {
  const StoryPreview(
      {super.key,
      required this.image,
      required this.dialogue,
      required this.narration});
  final Uint8List image;
  final String dialogue, narration;

  @override
  Widget build(BuildContext context) {
    if (dialogue.length > 20000 || narration.length > 20000) {
      return const Text(
          'These words are too long for this preview. They are kept in the fields and device draft. Shorten them to show the page.');
    }
    final layout = StoryTextLayout(dialogue, narration);
    Widget words(String text, double height) => SizedBox(
          width: StoryTextLayout.width - StoryTextLayout.inset * 2,
          height: height,
          child: Text(text,
              style: StoryTextLayout.style,
              textDirection: TextDirection.ltr,
              textScaler: TextScaler.noScaling),
        );
    return LayoutBuilder(builder: (context, constraints) {
      final width = math.min(StoryTextLayout.width, constraints.maxWidth);
      return Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: width,
            height: layout.height * width / StoryTextLayout.width,
            child: FittedBox(
              alignment: Alignment.topCenter,
              fit: BoxFit.contain,
              child: Container(
                width: StoryTextLayout.width,
                height: layout.height,
                padding: const EdgeInsets.all(StoryTextLayout.inset),
                color: Colors.white,
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                          height: StoryTextLayout.artHeight,
                          width: double.infinity,
                          child: Image.memory(image,
                              fit: BoxFit.contain,
                              semanticLabel:
                                  'Saved original drawing, not a generated illustration',
                              errorBuilder: (_, __, ___) => const Center(
                                  child:
                                      Text('Original preview unavailable.')))),
                      if (dialogue.isNotEmpty) ...[
                        const SizedBox(height: StoryTextLayout.inset),
                        words(dialogue, layout.dialogueHeight),
                      ],
                      if (narration.isNotEmpty) ...[
                        const SizedBox(height: StoryTextLayout.inset),
                        words(narration, layout.narrationHeight),
                      ],
                    ]),
              ),
            ),
          ));
    });
  }
}
