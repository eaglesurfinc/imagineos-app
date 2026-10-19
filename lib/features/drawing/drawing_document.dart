import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

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
  pan
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
      this.filled = false});
  final DrawingTool tool;
  final List<DrawingPoint> points;
  final int color;
  final double width, opacity;
  final bool filled;
  Map<String, dynamic> toJson() => {
        'tool': tool.name,
        'points': points.map((p) => p.toJson()).toList(),
        'color': color,
        'width': width,
        'opacity': opacity,
        'filled': filled
      };
  factory DrawingStroke.fromJson(Map<String, dynamic> json) => DrawingStroke(
      tool: DrawingTool.values.byName(json['tool'] as String),
      points: (json['points'] as List)
          .map((p) => DrawingPoint.fromJson(p as List))
          .toList(),
      color: json['color'] as int,
      width: (json['width'] as num).toDouble(),
      opacity: (json['opacity'] as num).toDouble(),
      filled: json['filled'] as bool);
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
            !s.width.isFinite ||
            s.width < 1 ||
            s.width > 100 ||
            !s.opacity.isFinite ||
            s.opacity < 0 ||
            s.opacity > 1 ||
            s.points.any((p) =>
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
