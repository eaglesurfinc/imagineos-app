import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'drawing_document.dart';
import 'drawing_fonts.dart';
import 'drawing_text_layout.dart';
import 'drawing_tools.dart';

Future<DrawingStroke?> editDrawingText(BuildContext context,
        {required DrawingStroke initial, required double maxHeight}) =>
    showDialog<DrawingStroke>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _TextEditor(initial: initial, maxHeight: maxHeight));

class _TextEditor extends StatefulWidget {
  const _TextEditor({required this.initial, required this.maxHeight});
  final DrawingStroke initial;
  final double maxHeight;
  @override
  State<_TextEditor> createState() => _TextEditorState();
}

class _TextEditorState extends State<_TextEditor> {
  late final _text = TextEditingController(text: widget.initial.text);
  late String _font = widget.initial.fontFamily;
  late double _size = widget.initial.fontSize;
  late int _color = widget.initial.color;
  DrawingStroke get _stroke => DrawingStroke(
      tool: DrawingTool.text,
      points: widget.initial.points,
      color: _color,
      width: widget.initial.width,
      opacity: widget.initial.opacity,
      selection: widget.initial.selection,
      text: _text.text,
      fontFamily: _font,
      fontSize: _size,
      textWidth: widget.initial.textWidth);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stroke = _stroke;
    final painter = drawingTextPainter(stroke);
    final fits = painter.height <= widget.maxHeight;
    painter.dispose();
    final valid =
        _text.text.trim().isNotEmpty && _text.text.length <= 2000 && fits;
    return AlertDialog(
        scrollable: true,
        title: const Text('Canvas text'),
        content: SizedBox(
            width: 520,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                  controller: _text,
                  minLines: 2,
                  maxLines: 6,
                  autocorrect: false,
                  enableSuggestions: false,
                  textCapitalization: TextCapitalization.none,
                  maxLength: 2000,
                  maxLengthEnforcement: MaxLengthEnforcement.none,
                  decoration:
                      const InputDecoration(labelText: 'Your exact text'),
                  onChanged: (_) => setState(() {})),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                  initialValue: _font,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Font'),
                  items: drawingFonts.entries
                      .map((entry) => DropdownMenuItem(
                          value: entry.key,
                          child: Text('${entry.key} - ${entry.value}',
                              style: TextStyle(fontFamily: entry.key))))
                      .toList(),
                  onChanged: (value) {
                    if (value != null) setState(() => _font = value);
                  }),
              const SizedBox(height: 8),
              Text('Text size: ${_size.round()}'),
              Slider(
                  value: _size,
                  min: 8,
                  max: 160,
                  divisions: 152,
                  onChanged: (value) => setState(() => _size = value)),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final color in drawingPalettes['Paint']!)
                  IconButton(
                      tooltip:
                          'Text color ${color.toRadixString(16).substring(2).toUpperCase()}',
                      isSelected: color == _color,
                      onPressed: () => setState(() => _color = color),
                      icon: Icon(Icons.circle, color: Color(color)),
                      selectedIcon:
                          Icon(Icons.check_circle, color: Color(color))),
              ]),
              OutlinedButton.icon(
                  icon: const Icon(Icons.palette_outlined),
                  label: const Text('Custom text color'),
                  onPressed: () async {
                    final color = await chooseDrawingColor(context, _color);
                    if (mounted && color != null)
                      setState(() => _color = color);
                  }),
              const SizedBox(height: 12),
              Container(
                  width: double.infinity,
                  color: const Color(0xffeef5f4),
                  padding: const EdgeInsets.all(12),
                  child: Text(_text.text,
                      style: TextStyle(
                          fontFamily: _font,
                          fontSize: math.min(_size, 48),
                          color: Color(_color)),
                      textScaler: TextScaler.noScaling)),
              if (!fits)
                const Text(
                    'This text does not fit below this point. Use a smaller size, fewer words, or cancel and choose a point nearer the top left.'),
              const Text(
                  'Tap text with the Text tool to change its words, font or color. Pixel cleanup, selection deletion and Merge paint flatten text; Undo restores editability. PNG copies contain pixels.'),
            ])),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel text')),
          FilledButton(
              onPressed: valid ? () => Navigator.pop(context, stroke) : null,
              child: const Text('Place text'))
        ]);
  }
}
