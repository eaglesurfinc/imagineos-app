import 'package:flutter/material.dart';
import 'drawing_document.dart';

const drawingToolNames = <DrawingTool, String>{
  DrawingTool.select: 'Select area',
  DrawingTool.lasso: 'Lasso select',
  DrawingTool.pen: 'Pen',
  DrawingTool.pencil: 'Pencil',
  DrawingTool.marker: 'Marker',
  DrawingTool.highlighter: 'Highlighter',
  DrawingTool.softBrush: 'Soft brush',
  DrawingTool.eraser: 'Eraser',
  DrawingTool.fill: 'Fill',
  DrawingTool.eyedropper: 'Color picker',
  DrawingTool.line: 'Line',
  DrawingTool.rectangle: 'Rectangle',
  DrawingTool.ellipse: 'Ellipse',
  DrawingTool.cutout: 'Outline cutout',
  DrawingTool.backgroundEraser: 'Remove area',
  DrawingTool.pan: 'Pan',
  DrawingTool.square: 'Square',
  DrawingTool.circle: 'Circle',
  DrawingTool.triangle: 'Triangle',
  DrawingTool.diamond: 'Diamond',
  DrawingTool.pentagon: 'Pentagon',
  DrawingTool.hexagon: 'Hexagon',
  DrawingTool.star: 'Star',
  DrawingTool.heart: 'Heart',
  DrawingTool.arrow: 'Arrow'
};
const drawingToolIcons = <DrawingTool, IconData>{
  DrawingTool.select: Icons.near_me_outlined,
  DrawingTool.lasso: Icons.gesture,
  DrawingTool.pen: Icons.edit,
  DrawingTool.pencil: Icons.draw,
  DrawingTool.marker: Icons.brush,
  DrawingTool.highlighter: Icons.highlight,
  DrawingTool.softBrush: Icons.blur_on,
  DrawingTool.eraser: Icons.auto_fix_normal,
  DrawingTool.fill: Icons.format_color_fill,
  DrawingTool.eyedropper: Icons.colorize,
  DrawingTool.line: Icons.horizontal_rule,
  DrawingTool.rectangle: Icons.crop_square,
  DrawingTool.ellipse: Icons.circle_outlined,
  DrawingTool.cutout: Icons.gesture,
  DrawingTool.backgroundEraser: Icons.auto_fix_high,
  DrawingTool.pan: Icons.pan_tool_outlined,
  DrawingTool.square: Icons.square_outlined,
  DrawingTool.circle: Icons.circle_outlined,
  DrawingTool.triangle: Icons.change_history,
  DrawingTool.diamond: Icons.diamond_outlined,
  DrawingTool.pentagon: Icons.pentagon_outlined,
  DrawingTool.hexagon: Icons.hexagon_outlined,
  DrawingTool.star: Icons.star_outline,
  DrawingTool.heart: Icons.favorite_border,
  DrawingTool.arrow: Icons.arrow_forward
};
const drawingPalettes = <String, List<int>>{
  'Sketch': [
    0xff242135,
    0xff5c5268,
    0xff9b8ea5,
    0xffe7d9ce,
    0xff774936,
    0xffbb6b51,
    0xffe9ad83,
    0xff387573,
    0xff4777a6,
    0xffffffff,
    0xff000000,
    0xffe15e72
  ],
  'Ink': [
    0xff182235,
    0xff34495e,
    0xff476ded,
    0xff7b4cce,
    0xffcc4384,
    0xffe25a40,
    0xffd68c1b,
    0xff118970,
    0xff2487a6,
    0xffaeb7c2,
    0xffffffff,
    0xff000000
  ],
  'Paint': [
    0xffe4475d,
    0xfff08240,
    0xfff6c648,
    0xff6cad5d,
    0xff239c97,
    0xff3e80d6,
    0xff7959c3,
    0xffd764b5,
    0xff8a573f,
    0xfff5d1b5,
    0xffffffff,
    0xff232337
  ],
  'Bright': [
    0xffff426f,
    0xffff9148,
    0xffffdf38,
    0xffadf444,
    0xff32dab6,
    0xff45ccff,
    0xff6476ff,
    0xffaa69ff,
    0xffff71d7,
    0xff163147,
    0xffffffff,
    0xff151521
  ],
};

Future<int?> chooseDrawingColor(BuildContext context, int initialColor) async {
  var hsv = HSVColor.fromColor(Color(initialColor));
  final hex = TextEditingController(
      text: initialColor.toRadixString(16).substring(2).toUpperCase());
  void change(HSVColor value) {
    hsv = value;
    hex.text =
        hsv.toColor().toARGB32().toRadixString(16).substring(2).toUpperCase();
  }

  final result = await showDialog<int>(
      context: context,
      builder: (dialog) => StatefulBuilder(
          builder: (context, update) => AlertDialog(
                  scrollable: true,
                  title: const Text('Custom color'),
                  content: SizedBox(
                      width: 360,
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Container(height: 48, color: hsv.toColor()),
                        const Text('Hue'),
                        Slider(
                            value: hsv.hue,
                            max: 360,
                            onChanged: (v) =>
                                update(() => change(hsv.withHue(v)))),
                        const Text('Saturation'),
                        Slider(
                            value: hsv.saturation,
                            onChanged: (v) =>
                                update(() => change(hsv.withSaturation(v)))),
                        const Text('Brightness'),
                        Slider(
                            value: hsv.value,
                            onChanged: (v) =>
                                update(() => change(hsv.withValue(v)))),
                        TextField(
                            controller: hex,
                            maxLength: 6,
                            decoration: const InputDecoration(
                                labelText: 'Hex color', prefixText: '#'),
                            onChanged: (text) {
                              final value = int.tryParse(text, radix: 16);
                              if (text.length == 6 && value != null)
                                update(() => hsv = HSVColor.fromColor(
                                    Color(0xff000000 | value)));
                            }),
                      ])),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(dialog),
                        child: const Text('Cancel')),
                    FilledButton(
                        onPressed: () =>
                            Navigator.pop(dialog, hsv.toColor().toARGB32()),
                        child: const Text('Choose color'))
                  ])));
  // Route removal completes after the closing animation.
  await Future<void>.delayed(const Duration(milliseconds: 300));
  hex.dispose();
  return result;
}
