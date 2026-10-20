import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'drawing_canvas.dart';
import 'drawing_pixels.dart';

Future<RasterResult?> reviewDrawingExtraction(
        BuildContext context, RasterRequest request, RasterResult initial) =>
    showDialog<RasterResult>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _ExtractionReview(request: request, initial: initial));

class _ExtractionReview extends StatefulWidget {
  const _ExtractionReview({required this.request, required this.initial});
  final RasterRequest request;
  final RasterResult initial;
  @override
  State<_ExtractionReview> createState() => _ExtractionReviewState();
}

class _ExtractionReviewState extends State<_ExtractionReview> {
  late RasterResult _result = widget.initial;
  late double _tolerance = widget.request.tolerance.clamp(0, 100);
  late bool _edges = widget.request.protectEdges,
      _gaps = widget.request.closeGaps;
  bool _working = false, _original = false;
  String? _error;
  Future<void> _update() async {
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final next = await compute(processDrawingPixels,
          widget.request.withTolerance(_tolerance, edges: _edges, gaps: _gaps));
      if (mounted) setState(() => _result = next);
    } catch (_) {
      if (mounted)
        setState(() => _error =
            'Could not update this preview. Adjust the settings or keep your current drawing.');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final operation = widget.request.operation;
    return AlertDialog(
        scrollable: true,
        title: const Text('Review extracted drawing'),
        content: SizedBox(
            width: 520,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(operation == DrawingPixelOperation.paper
                  ? 'Cleanup estimates page color, lighting and photo noise. Increase strength for remaining paper, or lower it to keep faint marks. Compare the original before accepting.'
                  : 'Check the boundary before accepting. Lower tolerance removes a narrower color range. A selection limits cleanup to its outline.'),
              const SizedBox(height: 12),
              if (_result.paperCleared != null)
                Semantics(
                    liveRegion: true,
                    child: Text(_result.paperCleared == 0
                        ? 'No paper was cleared. Adjust strength, crop closer to the page, or use Outline cutout for a busy background.'
                        : '${(_result.paperCleared! * 100).toStringAsFixed(1)}% of image pixels made transparent. This is not a paper-removal success score. Check remaining paper and drawing lines before accepting.')),
              SizedBox(
                  height: 240,
                  child: CustomPaint(
                      painter: const CheckerPainter(),
                      child: Center(
                          child: Image.memory(
                              _original ? widget.request.bytes : _result.bytes,
                              gaplessPlayback: true,
                              fit: BoxFit.contain,
                              semanticLabel: _original
                                  ? 'Original before extraction'
                                  : 'Extraction preview')))),
              SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Compare original'),
                  value: _original,
                  onChanged: (value) => setState(() => _original = value)),
              if (operation != DrawingPixelOperation.cutout) ...[
                Text(operation == DrawingPixelOperation.paper
                    ? 'Paper cleanup strength: ${_tolerance.round()}'
                    : 'Color tolerance: ${_tolerance.round()}'),
                Slider(
                    value: _tolerance,
                    max: 100,
                    divisions: 100,
                    onChanged: _working
                        ? null
                        : (value) => setState(() => _tolerance = value),
                    onChangeEnd: _working ? null : (_) => _update()),
              ],
              if (operation == DrawingPixelOperation.remove) ...[
                SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Protect drawing edges'),
                    value: _edges,
                    onChanged: _working
                        ? null
                        : (value) {
                            _edges = value;
                            _update();
                          }),
                SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Bridge tiny gaps'),
                    value: _gaps,
                    onChanged: _working || !_edges
                        ? null
                        : (value) {
                            _gaps = value;
                            _update();
                          }),
              ],
              if (_working) const LinearProgressIndicator(),
              if (_error != null) Text(_error!),
            ])),
        actions: [
          TextButton(
              onPressed: _working ? null : () => Navigator.pop(context),
              child: const Text('Keep current drawing')),
          FilledButton(
              onPressed: _working || _error != null
                  ? null
                  : () => Navigator.pop(context, _result),
              child: const Text('Use extraction')),
        ]);
  }
}
