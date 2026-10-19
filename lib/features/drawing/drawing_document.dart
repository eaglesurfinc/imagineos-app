import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';
import 'drawing_fonts.dart';

enum DrawingTool {
  pen,
  pencil,
  marker,
  highlighter,
  softBrush,
  eraser,
  fill,
  eyedropper,
  line,
  rectangle,
  ellipse,
  cutout,
  backgroundEraser,
  pan,
  select,
  lasso,
  square,
  circle,
  triangle,
  diamond,
  pentagon,
  hexagon,
  star,
  heart,
  arrow,
  text;

  bool get isShape => const {
        line,
        rectangle,
        ellipse,
        square,
        circle,
        triangle,
        diamond,
        pentagon,
        hexagon,
        star,
        heart,
        arrow
      }.contains(this);
  bool get isSelection => this == select || this == lasso;
}

class DrawingPoint {
  const DrawingPoint(this.x, this.y, [this.pressure = 1]);
  final double x, y, pressure;
  Offset get offset => Offset(x, y);
  List<double> toJson() => [x, y, pressure];
  factory DrawingPoint.fromJson(List<dynamic> json) => DrawingPoint(
      (json[0] as num).toDouble(),
      (json[1] as num).toDouble(),
      (json[2] as num).toDouble());
}

class DrawingStroke {
  const DrawingStroke(
      {required this.tool,
      required this.points,
      required this.color,
      required this.width,
      required this.opacity,
      this.filled = false,
      this.text = '',
      this.fontFamily = 'Nunito',
      this.fontSize = 48,
      this.textWidth = 400,
      this.selection = const []});
  final DrawingTool tool;
  final List<DrawingPoint> points;
  final int color;
  final double width, opacity;
  final bool filled;
  final String text, fontFamily;
  final double fontSize, textWidth;
  final List<DrawingPoint> selection;
  Map<String, dynamic> toJson() => {
        'tool': tool.name,
        'points': points.map((p) => p.toJson()).toList(),
        'color': color,
        'width': width,
        'opacity': opacity,
        'filled': filled,
        if (tool == DrawingTool.text) ...{
          'text': text,
          'font_family': fontFamily,
          'font_size': fontSize,
          'text_width': textWidth,
        },
        if (selection.isNotEmpty)
          'selection': selection.map((p) => p.toJson()).toList()
      };
  factory DrawingStroke.fromJson(Map<String, dynamic> json) => DrawingStroke(
      tool: DrawingTool.values.byName(json['tool'] as String),
      points: (json['points'] as List)
          .map((p) => DrawingPoint.fromJson(p as List))
          .toList(),
      color: json['color'] as int,
      width: (json['width'] as num).toDouble(),
      opacity: (json['opacity'] as num).toDouble(),
      filled: json['filled'] as bool,
      text: json['text'] as String? ?? '',
      fontFamily: json['font_family'] as String? ?? 'Nunito',
      fontSize: (json['font_size'] as num?)?.toDouble() ?? 48,
      textWidth: (json['text_width'] as num?)?.toDouble() ?? 400,
      selection: ((json['selection'] as List?) ?? const [])
          .map((p) => DrawingPoint.fromJson(p as List))
          .toList());
}

class DrawingFrame {
  const DrawingFrame({this.base, this.strokes = const [], this.background = 0});
  final Uint8List? base;
  final List<DrawingStroke> strokes;
  // Background is separate from artwork, so erasing never paints white pixels.
  final int background;
  DrawingFrame copyWith({List<DrawingStroke>? strokes, int? background}) =>
      DrawingFrame(
          base: base,
          strokes: strokes ?? this.strokes,
          background: background ?? this.background);
  Map<String, dynamic> toJson() => {
        'base': base == null ? null : base64Encode(base!),
        'strokes': strokes.map((s) => s.toJson()).toList(),
        'background': background
      };
  factory DrawingFrame.fromJson(Map<String, dynamic> json) => DrawingFrame(
      base: json['base'] == null ? null : base64Decode(json['base'] as String),
      strokes: (json['strokes'] as List)
          .map((s) =>
              DrawingStroke.fromJson(Map<String, dynamic>.from(s as Map)))
          .toList(),
      background: json['background'] as int);
}

class DrawingDocument {
  DrawingDocument({this.width = 1024, this.height = 1024, DrawingFrame? frame})
      : _frames = [frame ?? const DrawingFrame()];
  final int width, height;
  final List<DrawingFrame> _frames;
  var _cursor = 0;
  DrawingFrame get frame => _frames[_cursor];
  bool get canUndo => _cursor > 0;
  bool get canRedo => _cursor < _frames.length - 1;
  DrawingFrame get undoFrame => _frames[_cursor - 1];
  DrawingFrame get redoFrame => _frames[_cursor + 1];
  void commit(DrawingFrame frame) {
    _frames.removeRange(_cursor + 1, _frames.length);
    _frames.add(frame);
    // Shared frames reuse immutable base bytes and completed strokes.
    while (_frames.length > 1) {
      final bases = _frames.map((f) => f.base).whereType<Uint8List>().toSet();
      if (_frames.length <= 40 &&
          bases.fold<int>(0, (sum, bytes) => sum + bytes.length) <=
              20 * 1024 * 1024) break;
      _frames.removeAt(0);
    }
    _cursor = _frames.length - 1;
  }

  void undo() {
    if (canUndo) _cursor--;
  }

  void redo() {
    if (canRedo) _cursor++;
  }

  String encode() => jsonEncode(
      {'schema': 1, 'width': width, 'height': height, 'frame': frame.toJson()});
  factory DrawingDocument.decode(String encoded) {
    if (encoded.length > 8 * 1024 * 1024)
      throw const FormatException('Draft is too large.');
    final json = jsonDecode(encoded) as Map<String, dynamic>;
    final width = json['width'] as int, height = json['height'] as int;
    if (json['schema'] != 1 ||
        width < 1 ||
        height < 1 ||
        width > 1536 ||
        height > 1536) {
      throw const FormatException('This drawing draft cannot be opened.');
    }
    final frame =
        DrawingFrame.fromJson(Map<String, dynamic>.from(json['frame'] as Map));
    if (frame.strokes.length > 500 ||
        frame.strokes.any((s) =>
            s.points.length > 20000 ||
            s.selection.length > 6000 ||
            (s.tool == DrawingTool.text &&
                (s.text.length > 2000 ||
                    s.points.length != 1 ||
                    !drawingFonts.containsKey(s.fontFamily) ||
                    !s.fontSize.isFinite ||
                    s.fontSize < 8 ||
                    s.fontSize > 160 ||
                    !s.textWidth.isFinite ||
                    s.textWidth < 1 ||
                    s.textWidth > 1536)) ||
            !s.width.isFinite ||
            s.width < 1 ||
            s.width > 100 ||
            !s.opacity.isFinite ||
            s.opacity < 0 ||
            s.opacity > 1 ||
            [...s.points, ...s.selection].any((p) =>
                !p.x.isFinite ||
                !p.y.isFinite ||
                !p.pressure.isFinite ||
                p.x < 0 ||
                p.y < 0 ||
                p.x > width ||
                p.y > height ||
                p.pressure < 0 ||
                p.pressure > 1))) {
      throw const FormatException('This drawing draft cannot be opened.');
    }
    return DrawingDocument(width: width, height: height, frame: frame);
  }
}
