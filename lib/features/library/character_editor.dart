import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'character_store.dart';
import 'image_edits.dart';

class CharacterEditor extends StatefulWidget {
  const CharacterEditor({super.key, required this.source});
  final Uint8List source;

  @override
  State<CharacterEditor> createState() => _CharacterEditorState();
}

class _CharacterEditorState extends State<CharacterEditor> {
  List<CharacterEdit> _edits = [];
  EditPreview? _preview;
  RangeValues _horizontal = const RangeValues(0, 100);
  RangeValues _vertical = const RangeValues(0, 100);
  bool _busy = false;
  String? _error;

  Rect get _crop => Rect.fromLTRB(_horizontal.start / 100,
      _vertical.start / 100, _horizontal.end / 100, _vertical.end / 100);

  @override
  void initState() {
    super.initState();
    _render([]);
  }

  Future<void> _render(List<CharacterEdit> edits) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final preview = await compute(
          renderCharacterEdits, EditRequest(widget.source, edits));
      if (!mounted) return;
      setState(() {
        _preview = preview;
        _edits = edits;
        _horizontal = _vertical = const RangeValues(0, 100);
      });
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted)
        setState(() => _error =
            'Could not apply this edit. Your previous edits are kept.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _apply(CharacterEdit edit) => _render([..._edits, edit]);

  Widget _range(
      String label, RangeValues value, ValueChanged<RangeValues> update) {
    void move(bool end, int delta) {
      if (_busy || _preview == null) return;
      setState(() => update(RangeValues(
          end ? value.start : (value.start + delta).clamp(0, value.end - 1),
          end ? (value.end + delta).clamp(value.start + 1, 100) : value.end)));
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('$label: ${value.start.round()}–${value.end.round()}%'),
      CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
                move(false, -1),
            const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
                move(false, 1),
            const SingleActivator(LogicalKeyboardKey.arrowLeft, shift: true):
                () => move(true, -1),
            const SingleActivator(LogicalKeyboardKey.arrowRight, shift: true):
                () => move(true, 1),
          },
          child: Semantics(
              label: label,
              child: RangeSlider(
                  key: ValueKey(label),
                  values: value,
                  min: 0,
                  max: 100,
                  divisions: 100,
                  labels: RangeLabels(
                      '${value.start.round()}%', '${value.end.round()}%'),
                  semanticFormatterCallback: (value) =>
                      '${value.round()} percent',
                  onChanged: _busy
                      ? null
                      : (next) {
                          if (next.end - next.start >= 1)
                            setState(() => update(next));
                        }))),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    final canEdit = !_busy && preview != null && _edits.length < 20;
    return Scaffold(
      appBar: AppBar(title: const Text('Crop and edit')),
      body: ListView(padding: const EdgeInsets.all(24), children: [
        const Text(
            'Your saved original stays unchanged. Edits create a new version when you save.'),
        const Text('Animated uploads are edited as a still image.'),
        const SizedBox(height: 16),
        if (preview != null)
          Center(
              child: ConstrainedBox(
                  constraints:
                      const BoxConstraints(maxWidth: 600, maxHeight: 360),
                  child: AspectRatio(
                      aspectRatio: preview.width / preview.height,
                      child: CustomPaint(
                          foregroundPainter: _CropOverlay(_crop),
                          child: Image.memory(preview.bytes,
                              fit: BoxFit.fill,
                              semanticLabel: 'Character edit preview'))))),
        if (_busy)
          const LinearProgressIndicator(semanticsLabel: 'Preparing image'),
        if (_error != null) Semantics(liveRegion: true, child: Text(_error!)),
        if (preview == null && !_busy)
          TextButton(
              onPressed: () => _render(_edits),
              child: const Text('Retry image')),
        _range('Keep horizontal area', _horizontal,
            (value) => _horizontal = value),
        _range('Keep vertical area', _vertical, (value) => _vertical = value),
        const Text(
            'Keyboard: focus a crop control. Left/right arrows move its first edge; Shift + arrows move its second edge.'),
        const Text(
            'Adjust the edges above, then apply the crop. Rotate and flip apply immediately.'),
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton(
              onPressed: canEdit && _crop != const Rect.fromLTWH(0, 0, 1, 1)
                  ? () => _apply(CharacterEdit(CharacterEditKind.crop, _crop))
                  : null,
              child: const Text('Apply crop')),
          OutlinedButton(
              onPressed: canEdit && _crop == const Rect.fromLTWH(0, 0, 1, 1)
                  ? () => _apply(const CharacterEdit(CharacterEditKind.rotate))
                  : null,
              child: const Text('Rotate right')),
          OutlinedButton(
              onPressed: canEdit && _crop == const Rect.fromLTWH(0, 0, 1, 1)
                  ? () => _apply(const CharacterEdit(CharacterEditKind.flip))
                  : null,
              child: const Text('Flip horizontally')),
          TextButton(
              onPressed: !_busy
                  ? () => setState(() {
                        _horizontal = _vertical = const RangeValues(0, 100);
                      })
                  : null,
              child: const Text('Clear crop selection')),
          TextButton(
              onPressed: !_busy && _edits.isNotEmpty
                  ? () => _render(_edits.sublist(0, _edits.length - 1))
                  : null,
              child: const Text('Undo')),
          TextButton(
              onPressed: !_busy && preview != null ? () => _render([]) : null,
              child: const Text('Reset edits')),
        ]),
        if (_edits.length >= 20)
          const Text(
              'This session has reached 20 edits. Use this drawing, undo, or reset to continue.'),
        FilledButton(
            onPressed: !_busy &&
                    preview != null &&
                    _edits.isNotEmpty &&
                    _crop == const Rect.fromLTWH(0, 0, 1, 1)
                ? () => Navigator.of(context)
                    .pop(OriginalFile(preview.bytes, 'image/png'))
                : null,
            child: const Text('Use edited drawing')),
        if (_crop != const Rect.fromLTWH(0, 0, 1, 1))
          const Text(
              'Apply the selected crop before using the drawing, or reset the selection.'),
      ]),
    );
  }
}

class _CropOverlay extends CustomPainter {
  const _CropOverlay(this.crop);
  final Rect crop;
  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Rect.fromLTRB(crop.left * size.width, crop.top * size.height,
        crop.right * size.width, crop.bottom * size.height);
    final mask = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRect(bounds);
    canvas.drawPath(mask, Paint()..color = Colors.black45);
    canvas.drawRect(
        bounds,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(_CropOverlay oldDelegate) => oldDelegate.crop != crop;
}
