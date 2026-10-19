import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'drawing_document.dart';
import 'drawing_pixels.dart';
import 'drawing_canvas.dart';

Future<RasterResult?> reviewDrawingExtraction(
    BuildContext context,
    Uint8List bytes,
    RasterResult initial,
    DrawingPixelOperation operation,
    DrawingPoint point,
    List<List<double>> polygon,
    double initialTolerance) async {
  var result = initial, tolerance = initialTolerance;
  var working = false;
  String? error;
  return showDialog<RasterResult>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
          builder: (context, update) => AlertDialog(
                scrollable: true,
                title: const Text('Review extracted drawing'),
                content: SizedBox(
                    width: 520,
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Text(
                          'Check pale colors and fine lines before accepting. The source stays unchanged. Undo restores the previous artwork.'),
                      const SizedBox(height: 12),
                      SizedBox(
                          height: 240,
                          child: CustomPaint(
                              painter: const CheckerPainter(),
                              child: Center(
                                  child: Image.memory(result.bytes,
                                      fit: BoxFit.contain,
                                      semanticLabel: 'Extraction preview')))),
                      if (operation != DrawingPixelOperation.cutout) ...[
                        Text('Cleanup tolerance: ${tolerance.round()}'),
                        Slider(
                            value: tolerance,
                            min: 0,
                            max: 150,
                            divisions: 150,
                            onChanged: working
                                ? null
                                : (value) => update(() => tolerance = value),
                            onChangeEnd: (value) async {
                              update(() {
                                working = true;
                                error = null;
                              });
                              try {
                                final next = await compute(
                                    processDrawingPixels,
                                    RasterRequest(bytes,
                                        operation: operation,
                                        x: point.x.floor(),
                                        y: point.y.floor(),
                                        tolerance: value,
                                        polygon: polygon));
                                if (dialogContext.mounted)
                                  update(() => result = next);
                              } catch (_) {
                                if (dialogContext.mounted)
                                  update(() => error =
                                      'Could not update the preview. Try a different tolerance.');
                              } finally {
                                if (dialogContext.mounted)
                                  update(() => working = false);
                              }
                            }),
                      ],
                      if (working) const LinearProgressIndicator(),
                      if (error != null) Text(error!),
                    ])),
                actions: [
                  TextButton(
                      onPressed:
                          working ? null : () => Navigator.pop(dialogContext),
                      child: const Text('Keep current drawing')),
                  FilledButton(
                      onPressed: working
                          ? null
                          : () => Navigator.pop(dialogContext, result),
                      child: const Text('Use extraction'))
                ],
              )));
}
