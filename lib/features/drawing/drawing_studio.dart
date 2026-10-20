import '../../core/creation_permissions.dart';
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../library/character_store.dart' show OriginalFile, maxOriginalBytes;
import 'drawing_document.dart';
import 'drawing_canvas.dart';
import 'drawing_tools.dart';
import 'extraction_review.dart';
import 'drawing_drafts.dart';
import 'drawing_pixels.dart';
import 'drawing_renderer.dart';
import 'drawing_shapes.dart';
import 'drawing_input.dart';
import 'pen_setup.dart';
import 'drawing_download.dart';
import 'drawing_text_editor.dart';
import 'drawing_selection.dart';
import 'drawing_raster_selection.dart';
import 'drawing_selection_toolbar.dart';

Future<OriginalFile?> openDrawingStudio(BuildContext context,
        {required String draftKey,
        Uint8List? source,
        DrawingDraftStore? drafts}) =>
    Navigator.of(context).push<OriginalFile>(MaterialPageRoute(
        builder: (_) =>
            DrawingStudio(draftKey: draftKey, source: source, drafts: drafts)));

class DrawingStudio extends StatefulWidget {
  const DrawingStudio(
      {super.key,
      this.source,
      required this.draftKey,
      this.drafts,
      this.saveDrawing = saveDrawingToDevice});
  final Uint8List? source;
  final String draftKey;
  final DrawingDraftStore? drafts;
  final SaveDrawing saveDrawing;
  @override
  State<DrawingStudio> createState() => _DrawingStudioState();
}

class _DrawingStudioState extends State<DrawingStudio> {
  late final _drafts = widget.drafts ?? DrawingDraftStore.shared;
  late final int _session = _drafts.generation;
  final _transform = TransformationController();
  final _focus = FocusNode(debugLabel: 'Drawing canvas');
  DrawingDocument? _document;
  ui.Image? _base;
  Map<Uint8List, ui.Image> _images = {};
  DrawingTool _tool = DrawingTool.pen;
  String _kit = 'Paint';
  int _color = 0xff7959c3;
  double _width = 10, _opacity = 1, _tolerance = 30;
  bool _filled = false, _busy = true, _showCursor = false;
  bool _dialogOpen = false;
  String _status = 'Opening your workspace…';
  List<DrawingPoint> _points = [];
  int? _pointer;
  bool _inverted = false, _penOnly = false;
  String _input = 'Draw with a finger, mouse, or compatible pen.';
  List<DrawingPoint> _selection = [];
  Set<int> _selectedItems = {};
  DrawingRasterSelection? _selectedRaster;
  ui.Image? _selectionBase;
  Map<Uint8List, ui.Image> _selectionImages = {};
  DrawingFrame? _previewFrame, _gestureFrame;
  Set<int> _gestureItems = {};
  Rect? _gestureBounds;
  Offset? _gestureStart, _resizePivot;
  bool _gestureChanged = false;
  bool get _hasItems => _selectedItems.isNotEmpty || _selectedRaster != null;
  DrawingFrame get _selectionFrame => _selectedRaster == null
      ? _document!.frame
      : DrawingFrame(
          base: _selectedRaster!.remaining,
          background: _document!.frame.background,
          strokes: [_selectedRaster!.item, ..._document!.frame.strokes]);
  Set<int> get _selectionItems => _selectedRaster == null
      ? _selectedItems
      : {0, ..._selectedItems.map((i) => i + 1)};
  Rect? get _itemBounds => _previewFrame != null
      ? drawingSelectionBounds(_previewFrame!.strokes, _gestureItems)
      : _hasItems
          ? drawingSelectionBounds(_selectionFrame.strokes, _selectionItems)
          : null;
  DrawingTool get _activeTool => _inverted ? DrawingTool.eraser : _tool;
  List<List<double>> get _selectionPolygon =>
      _selection.map((p) => [p.x, p.y]).toList();
  Offset _cursor = const Offset(512, 512);
  Timer? _checkpoint;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _checkpoint?.cancel();
    _transform.dispose();
    _focus.dispose();
    _base?.dispose();
    for (final image in _images.values) {
      image.dispose();
    }
    _clearSelection();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _busy = true);
    String? saved;
    ui.Image? base;
    Map<Uint8List, ui.Image> images = {};
    try {
      saved = await _drafts.read(widget.draftKey);
    } catch (_) {}
    try {
      DrawingDocument document;
      if (saved != null) {
        document = DrawingDocument.decode(saved);
      } else if (widget.source != null) {
        final image =
            await compute(processDrawingPixels, RasterRequest(widget.source!));
        document = DrawingDocument(
            width: image.width,
            height: image.height,
            frame: DrawingFrame(base: image.bytes));
      } else {
        document = DrawingDocument();
      }
      base = await decodeDrawingBase(document.frame.base);
      images = await decodeDrawingItems(document.frame);
      if (!mounted) {
        base?.dispose();
        for (final image in images.values) {
          image.dispose();
        }
        return;
      }
      setState(() {
        _document = document;
        _base = base;
        _images = images;
        _busy = false;
        _cursor = Offset(document.width / 2, document.height / 2);
        _status = saved == null
            ? 'Your canvas is ready.'
            : 'Device draft restored. Undo history starts here.';
      });
    } catch (_) {
      base?.dispose();
      for (final image in images.values) {
        image.dispose();
      }
      if (mounted)
        setState(() {
          _busy = false;
          _status =
              'Could not open this workspace. Your saved source is unchanged. Retry opening it.';
        });
    }
  }

  void _checkpointDraft() {
    _checkpoint?.cancel();
    _checkpoint =
        Timer(const Duration(milliseconds: 250), () => unawaited(_saveDraft()));
  }

  Future<bool> _saveDraft() async {
    final document = _document;
    if (document == null || _session != _drafts.generation) return false;
    try {
      await _drafts.write(widget.draftKey, document.encode(), _session);
      if (mounted)
        setState(() => _status =
            'Draft kept on this device. Use drawing, then save it to your library.');
      return true;
    } catch (_) {
      if (mounted)
        setState(() => _status =
            'Device recovery is unavailable or full. Keep this tab open and save your drawing.');
      return false;
    }
  }

  Future<bool> _frame(DrawingFrame frame,
      {bool? redo, Set<int>? selected}) async {
    setState(() => _busy = true);
    ui.Image? base;
    Map<Uint8List, ui.Image> images = {};
    try {
      if (frame.strokes.length > 500 ||
          DrawingDocument(
                      width: _document!.width,
                      height: _document!.height,
                      frame: frame)
                  .encode()
                  .length >
              8 * 1024 * 1024) {
        throw const FormatException(
            'Merge paint before adding more editable items.');
      }
      base = await decodeDrawingBase(frame.base);
      images = await decodeDrawingItems(frame);
      if (!mounted || _session != _drafts.generation) {
        base?.dispose();
        for (final image in images.values) {
          image.dispose();
        }
        return false;
      }
      setState(() {
        _base?.dispose();
        for (final image in _images.values) {
          image.dispose();
        }
        _base = base;
        _images = images;
        _clearSelection();
        _selectedItems = selected ?? {};
        if (redo == null)
          _document!.commit(frame);
        else if (redo)
          _document!.redo();
        else
          _document!.undo();
        _busy = false;
      });
      _checkpointDraft();
      if (selected != null) _focus.requestFocus();
      return true;
    } catch (error) {
      base?.dispose();
      for (final image in images.values) {
        image.dispose();
      }
      if (mounted)
        setState(() {
          _busy = false;
          _cancelSelectionGesture();
          _status = error is FormatException
              ? error.message
              : 'Could not apply that change. Your previous drawing is kept.';
        });
      return false;
    }
  }

  void _cancelSelectionGesture() {
    _previewFrame = null;
    _gestureFrame = null;
    _gestureItems = {};
    _gestureBounds = null;
    _gestureStart = null;
    _resizePivot = null;
    _gestureChanged = false;
  }

  void _clearSelection({bool region = true}) {
    if (region) _selection = [];
    _selectedItems = {};
    _selectedRaster = null;
    _selectionBase?.dispose();
    _selectionBase = null;
    for (final image in _selectionImages.values) {
      image.dispose();
    }
    _selectionImages = {};
    _cancelSelectionGesture();
  }

  Future<void> _selectItems(List<DrawingPoint> points) async {
    final tap = points.length == 1 ||
        (_tool == DrawingTool.select &&
            (points.first.offset - points.last.offset).distance < 3);
    final polygon = tap
        ? <DrawingPoint>[]
        : _tool == DrawingTool.select
            ? selectionRectangle(points.first, points.last)
            : points;
    if (!tap &&
        (polygon.length < 3 || drawingPolygon(polygon).getBounds().isEmpty))
      return;
    final strokes = _document!.frame.strokes;
    final hit = tap ? hitDrawingItem(strokes, points.first.offset) : null;
    final selected = tap
        ? <int>{if (hit != null) hit}
        : drawingItemsInArea(strokes, polygon);
    setState(() => _busy = true);
    ui.Image? base;
    Map<Uint8List, ui.Image> images = {};
    try {
      final bytes = _document!.frame.base;
      final raster = bytes != null && (!tap || hit == null)
          ? await compute(
              selectDrawingRaster,
              DrawingRasterSelectionRequest(bytes, polygon,
                  tap: tap ? points.first.offset : null))
          : null;
      if (raster != null) {
        base = await decodeDrawingBase(raster.remaining);
        images = await decodeDrawingItems(DrawingFrame(strokes: [raster.item]));
      }
      if (!mounted || _session != _drafts.generation) {
        base?.dispose();
        for (final image in images.values) {
          image.dispose();
        }
        return;
      }
      setState(() {
        _clearSelection();
        _selection = polygon;
        _selectedItems = selected;
        _selectedRaster = raster;
        _selectionBase = base;
        _selectionImages = images;
        _busy = false;
        _status = _hasItems
            ? 'Items selected. Drag to move, use a corner or Smaller/Larger to resize, reorder, or delete. Undo restores changes.'
            : 'No artwork selected. Tap an item or drag around artwork. An empty area can still limit painting and cleanup.';
      });
    } catch (_) {
      base?.dispose();
      for (final image in images.values) {
        image.dispose();
      }
      if (mounted)
        setState(() {
          _busy = false;
          _status = 'Could not select that area. Your drawing is kept.';
        });
    }
  }

  Future<void> _deleteSelection() async {
    if (_busy || _document == null) return;
    if (!_hasItems) {
      if (_selection.isNotEmpty)
        await _pixel(
            DrawingPixelOperation.clearSelection, const DrawingPoint(0, 0));
      return;
    }
    final frame = _selectionFrame, selected = _selectionItems;
    await _frame(frame.copyWith(strokes: [
      for (var i = 0; i < frame.strokes.length; i++)
        if (!selected.contains(i)) frame.strokes[i]
    ]));
  }

  Future<void> _resizeItems(double factor, {Offset delta = Offset.zero}) async {
    if (_busy || !_hasItems || _document == null) return;
    final selected = _selectionItems;
    final frame = transformDrawingItems(_selectionFrame, selected, _itemBounds!,
        Size(_document!.width.toDouble(), _document!.height.toDouble()),
        factor: factor, delta: delta);
    await _frame(frame, selected: selected);
  }

  Future<void> _reorderItems(DrawingLayerOrder order) async {
    if (_busy || !_hasItems) return;
    var frame = _selectionFrame;
    var selected = _selectionItems;
    // Make the existing photo/merged layer participate in ordering, so a
    // selected shape can go behind it without flattening or redrawing anything.
    if (frame.base != null) {
      setState(() => _busy = true);
      try {
        final base = await compute(selectDrawingRaster,
            DrawingRasterSelectionRequest(frame.base!, const []));
        if (!mounted || _session != _drafts.generation) return;
        frame = DrawingFrame(
            background: frame.background,
            strokes: [if (base != null) base.item, ...frame.strokes]);
        if (base != null) selected = selected.map((i) => i + 1).toSet();
      } catch (_) {
        if (mounted)
          setState(() {
            _busy = false;
            _status = 'Could not reorder those items. Your drawing is kept.';
          });
        return;
      }
    }
    final result = reorderDrawingItems(frame, selected, order);
    await _frame(result.frame, selected: result.selected);
  }

  void _history(bool redo) {
    if (_busy || _document == null) return;
    final document = _document!;
    if (redo ? document.canRedo : document.canUndo) {
      _frame(redo ? document.redoFrame : document.undoFrame, redo: redo);
    }
  }

  DrawingStroke _stroke(List<DrawingPoint> points) => DrawingStroke(
      tool: _activeTool,
      points: List.of(points),
      color: _color,
      width: _width,
      opacity: _opacity,
      filled: _filled,
      selection: List.of(_selection));
  bool get _shape => _activeTool.isShape;
  bool get _rasterTool => const {
        DrawingTool.fill,
        DrawingTool.eyedropper,
        DrawingTool.backgroundEraser
      }.contains(_activeTool);
  List<DrawingPoint> get _outline =>
      _activeTool == DrawingTool.select && _points.length > 1
          ? selectionRectangle(_points.first, _points.last)
          : (_activeTool.isSelection || _activeTool == DrawingTool.cutout)
              ? _points
              : const [];
  DrawingPoint _point(Offset position, Size size, double pressure) =>
      DrawingPoint(
          (position.dx / size.width * _document!.width)
              .clamp(0, _document!.width.toDouble()),
          (position.dy / size.height * _document!.height)
              .clamp(0, _document!.height.toDouble()),
          pressure.isFinite && pressure >= 0 ? pressure.clamp(0, 1) : 1);
  void _down(PointerEvent event, Offset position, Size size) {
    if (_busy || _tool == DrawingTool.pan || _pointer != null) return;
    _focus.requestFocus();
    _inverted = event.kind == ui.PointerDeviceKind.invertedStylus;
    _pointer = event.pointer;
    final point = _point(position, size, drawingPressure(event));
    final bounds = _itemBounds;
    if (_activeTool.isSelection && bounds != null) {
      final radius = 20 *
          _document!.width /
          size.width /
          _transform.value.getMaxScaleOnAxis();
      Offset? corner;
      for (final candidate in [
        bounds.topLeft,
        bounds.topRight,
        bounds.bottomLeft,
        bounds.bottomRight
      ]) {
        if ((candidate - point.offset).distance <= radius) {
          corner = candidate;
          break;
        }
      }
      if (corner != null || bounds.contains(point.offset)) {
        setState(() {
          _gestureFrame = _selectionFrame;
          _gestureItems = Set.of(_selectionItems);
          _gestureBounds = bounds;
          _gestureStart = point.offset;
          _resizePivot = corner == null ? null : bounds.center * 2 - corner;
          _gestureChanged = false;
        });
        return;
      }
    }
    setState(() {
      _input = event.kind == ui.PointerDeviceKind.stylus || _inverted
          ? 'Pen input received - pressure ${(drawingPressure(event) * 100).round()}%'
          : event.kind == ui.PointerDeviceKind.touch
              ? 'Touch input received'
              : 'Mouse input received';
      _points = [point];
      _cursor = point.offset;
      _showCursor = false;
    });
  }

  void _move(PointerEvent event, Offset position, Size size) {
    if (_pointer == event.pointer && !_busy && _gestureFrame != null) {
      final point = _point(position, size, 1).offset;
      final start = _gestureStart!, pivot = _resizePivot;
      if ((point - start).distance < .5) return;
      final vector = pivot == null ? Offset.zero : start - pivot;
      final factor = pivot == null
          ? 1.0
          : ((point - pivot).dx * vector.dx + (point - pivot).dy * vector.dy) /
              math.max(.001, vector.distanceSquared);
      setState(() {
        _gestureChanged = true;
        _previewFrame = transformDrawingItems(
            _gestureFrame!,
            _gestureItems,
            _gestureBounds!,
            Size(_document!.width.toDouble(), _document!.height.toDouble()),
            delta: pivot == null ? point - start : Offset.zero,
            factor: factor,
            pivot: pivot);
      });
      return;
    }
    if (_pointer != event.pointer || _busy || _rasterTool || _points.isEmpty)
      return;
    final point = _point(position, size, drawingPressure(event));
    if ((point.offset - _points.last.offset).distance < 1) return;
    setState(() {
      if (_shape || _activeTool == DrawingTool.select)
        _points = [_points.first, point];
      else if (_points.length < 6000) _points = [..._points, point];
      _cursor = point.offset;
      if (event.kind == ui.PointerDeviceKind.stylus || _inverted) {
        _input =
            'Pen input received - pressure ${(drawingPressure(event) * 100).round()}%';
      }
    });
  }

  Future<void> _finish() async {
    if (_gestureFrame != null) {
      final frame = _previewFrame, selected = Set<int>.of(_gestureItems);
      final changed = _gestureChanged;
      setState(() {
        _pointer = null;
        _inverted = false;
        _points = [];
      });
      if (changed && frame != null) {
        await _frame(frame, selected: selected);
      } else {
        setState(_cancelSelectionGesture);
      }
      return;
    }
    final points = List<DrawingPoint>.of(_points);
    final tool = _activeTool, raster = _rasterTool;
    final stroke = _stroke(points);
    setState(() {
      _points = [];
      _pointer = null;
      _inverted = false;
    });
    if (points.isEmpty || _busy) return;
    if (tool == DrawingTool.text) {
      await _textAt(points.first);
      return;
    }
    if (tool.isSelection) {
      await _selectItems(points);
      return;
    }
    if (raster) {
      await _pixel(
          tool == DrawingTool.fill
              ? DrawingPixelOperation.fill
              : tool == DrawingTool.eyedropper
                  ? DrawingPixelOperation.pick
                  : DrawingPixelOperation.remove,
          points.first);
      return;
    }
    if (tool == DrawingTool.cutout) {
      if (points.length < 3) {
        setState(() => _status =
            'Draw a closed outline around the artwork, then release.');
        return;
      }
      await _pixel(DrawingPixelOperation.cutout, points.first,
          polygon: points.map((p) => [p.x, p.y]).toList());
      return;
    }
    if (_document!.frame.strokes.length >= 500) {
      setState(() => _status =
          'Merge paint to continue drawing, or use this drawing and save it.');
      return;
    }
    setState(() => _document!.commit(_document!.frame
        .copyWith(strokes: [..._document!.frame.strokes, stroke])));
    _checkpointDraft();
  }

  Future<void> _pixel(DrawingPixelOperation operation, DrawingPoint point,
      {List<List<double>> polygon = const []}) async {
    if (_busy || _document == null) return;
    setState(() => _busy = true);
    try {
      final bytes = await exportDrawing(_document!, _base,
          background: operation == DrawingPixelOperation.pick);
      if (!mounted) return;
      final request = RasterRequest(bytes,
          operation: operation,
          x: point.x.floor(),
          y: point.y.floor(),
          color: Color(_color).withValues(alpha: _opacity).toARGB32(),
          tolerance:
              operation == DrawingPixelOperation.paper ? 100 : _tolerance,
          polygon: polygon,
          selection: _selectionPolygon);
      var result = await compute(processDrawingPixels, request);
      if (!mounted) return;
      if (operation == DrawingPixelOperation.pick) {
        setState(() {
          _busy = false;
          if ((result.color! >> 24) > 0)
            _color = 0xff000000 | (result.color! & 0xffffff);
          _status = 'Color picked. Choose a drawing tool to use it.';
        });
        return;
      }
      if (operation.extractsArtwork) {
        setState(() => _dialogOpen = true);
        RasterResult? preview;
        try {
          preview = await reviewDrawingExtraction(context, request, result);
        } finally {
          if (mounted) setState(() => _dialogOpen = false);
        }
        if (!mounted) return;
        if (preview == null) {
          setState(() => _busy = false);
          return;
        }
        result = preview;
      }
      setState(() => _busy = false);
      await _frame(DrawingFrame(
          base: result.bytes,
          background:
              operation.extractsArtwork ? 0 : _document!.frame.background));
    } on FormatException catch (error) {
      if (mounted)
        setState(() {
          _busy = false;
          _status = error.message;
        });
    } catch (_) {
      if (mounted)
        setState(() {
          _busy = false;
          _status =
              'Could not finish that change. Your drawing is kept. Try a smaller selection.';
        });
    }
  }

  Future<void> _textAt(DrawingPoint point) async {
    if (_busy || _document == null) return;
    final strokes = _document!.frame.strokes;
    var index = -1;
    for (var i = strokes.length - 1; i >= 0; i--) {
      if (strokes[i].tool == DrawingTool.text &&
          drawingItemBounds(strokes[i]).contains(point.offset)) {
        index = i;
        break;
      }
    }
    if (index < 0 && strokes.length >= 500) {
      setState(() => _status =
          'Merge paint or save this drawing before adding more items.');
      return;
    }
    final initial = index >= 0
        ? strokes[index]
        : DrawingStroke(
            tool: DrawingTool.text,
            points: [point],
            color: _color,
            width: _width,
            opacity: _opacity,
            textWidth: math.max(1, _document!.width - point.x),
            selection: List.of(_selection));
    setState(() {
      _busy = true;
      _dialogOpen = true;
    });
    try {
      final updated = await editDrawingText(context,
          initial: initial,
          maxHeight: (_document!.height -
                  initial.placement.apply(initial.points.first.offset).dy) /
              initial.placement.scale);
      if (!mounted || _session != _drafts.generation) return;
      if (updated != null) {
        final next = List<DrawingStroke>.of(strokes);
        if (index < 0) {
          next.add(updated);
        } else {
          next[index] = updated;
        }
        setState(() {
          _document!.commit(_document!.frame.copyWith(strokes: next));
          _status =
              'Text placed. Tap it with Text to edit, or use Select area to move, resize, reorder or delete it.';
        });
        _checkpointDraft();
      }
    } finally {
      if (mounted)
        setState(() {
          _busy = false;
          _dialogOpen = false;
        });
    }
  }

  Future<void> _clear() async {
    final yes = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                scrollable: true,
                title: const Text('Clear this canvas?'),
                content: const Text(
                    'The saved original stays in your library. You can undo this clear while this workspace stays open.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Clear canvas'))
                ]));
    if (yes == true && mounted)
      await _frame(DrawingFrame(background: _document!.frame.background));
  }

  Future<void> _merge() async {
    setState(() => _busy = true);
    try {
      final bytes = await exportDrawing(_document!, _base, background: false);
      if (!mounted) return;
      setState(() => _busy = false);
      await _frame(
          DrawingFrame(base: bytes, background: _document!.frame.background));
    } catch (_) {
      if (mounted)
        setState(() {
          _busy = false;
          _status = 'Could not merge paint. Your drawing is kept.';
        });
    }
  }

  Future<void> _use() async {
    setState(() => _busy = true);
    try {
      _checkpoint?.cancel();
      await _saveDraft();
      final bytes = await exportDrawing(_document!, _base);
      if (bytes.length > maxOriginalBytes)
        throw const FormatException(
            'Drawing exceeds 5 MB. Try removing unused photo areas.');
      if (mounted) Navigator.pop(context, OriginalFile(bytes, 'image/png'));
    } on FormatException catch (error) {
      if (mounted)
        setState(() {
          _busy = false;
          _status = error.message;
        });
    } catch (_) {
      if (mounted)
        setState(() {
          _busy = false;
          _status =
              'Could not prepare the drawing. Your draft is kept; try again.';
        });
    }
  }

  Future<void> _saveLocal() async {
    if (_busy || _document == null) return;
    setState(() => _busy = true);
    try {
      final permissions = CreationPermissions.of(context);
      await permissions.requireExport();
      final bytes = await exportDrawing(_document!, _base);
      if (!mounted) return;
      await permissions.requireExport();
      final stamp =
          DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
      final saved =
          await widget.saveDrawing(bytes, 'imagineos-drawing-$stamp.png');
      if (mounted)
        setState(() => _status = saved
            ? 'PNG ready to save. Check this device\'s Downloads or save prompt. Save to your library separately to keep it online.'
            : 'Device save cancelled. Your drawing is still here.');
    } catch (_) {
      if (mounted)
        setState(() => _status =
            'Could not save to this device. Your drawing is kept; check download permissions and retry.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _leave() async {
    if (_busy) return;
    _checkpoint?.cancel();
    final saved = await _saveDraft();
    if (!mounted) return;
    if (!saved) {
      final leave = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
                  scrollable: true,
                  title: const Text('Leave without device recovery?'),
                  content: const Text(
                      'Save to your library to keep permanent artwork. Unsaved changes may be lost if you leave now.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Keep drawing')),
                    TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Leave workspace'))
                  ]));
      if (!mounted || leave != true) return;
    }
    Navigator.pop(context);
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (_busy || event is KeyUpEvent || _document == null)
      return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.delete ||
        key == LogicalKeyboardKey.backspace) {
      if ((!_hasItems && _selection.isEmpty) ||
          _points.isNotEmpty ||
          _gestureFrame != null ||
          event is! KeyDownEvent) {
        return KeyEventResult.ignored;
      }
      unawaited(_deleteSelection());
      return KeyEventResult.handled;
    }
    var movement = Offset.zero;
    if (key == LogicalKeyboardKey.arrowLeft) movement = const Offset(-8, 0);
    if (key == LogicalKeyboardKey.arrowRight) movement = const Offset(8, 0);
    if (key == LogicalKeyboardKey.arrowUp) movement = const Offset(0, -8);
    if (key == LogicalKeyboardKey.arrowDown) movement = const Offset(0, 8);
    if (movement != Offset.zero) {
      if (_hasItems && _tool.isSelection && _points.isEmpty) {
        unawaited(_resizeItems(1, delta: movement));
        return KeyEventResult.handled;
      }
      setState(() {
        _showCursor = true;
        _cursor = Offset(
            (_cursor.dx + movement.dx).clamp(0, _document!.width.toDouble()),
            (_cursor.dy + movement.dy).clamp(0, _document!.height.toDouble()));
        if (_points.isNotEmpty) {
          final point = DrawingPoint(_cursor.dx, _cursor.dy);
          _points = _shape || _tool == DrawingTool.select
              ? [_points.first, point]
              : [..._points, point];
        }
      });
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.space || key == LogicalKeyboardKey.enter) {
      if (_tool == DrawingTool.pan) return KeyEventResult.ignored;
      if (_points.isEmpty) {
        setState(() => _points = [DrawingPoint(_cursor.dx, _cursor.dy)]);
      } else {
        _finish();
      }
      if (_rasterTool) _finish();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      setState(() {
        _points = [];
        _pointer = null;
        _clearSelection();
      });
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _customColor() async {
    final color = await chooseDrawingColor(context, _color);
    if (mounted && color != null) setState(() => _color = color);
  }

  Widget _toolChoices({required bool shapes}) => Wrap(
      spacing: 6,
      runSpacing: 4,
      children: drawingToolNames.entries
          .where((tool) => tool.key.isShape == shapes)
          .map((tool) => ChoiceChip(
              avatar: Icon(drawingToolIcons[tool.key], size: 18),
              label: Text(tool.value),
              selected: _tool == tool.key,
              onSelected: _busy
                  ? null
                  : (_) => setState(() {
                        _tool = tool.key;
                        if (!tool.key.isSelection)
                          _clearSelection(region: false);
                        _opacity = tool.key == DrawingTool.highlighter
                            ? .3
                            : tool.key == DrawingTool.softBrush
                                ? .7
                                : 1;
                        _points = [];
                        _pointer = null;
                        _inverted = false;
                      })))
          .toList());

  Widget _controls() =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Drawing kits', style: Theme.of(context).textTheme.titleMedium),
        Wrap(
            spacing: 6,
            children: drawingPalettes.keys
                .map((kit) => ChoiceChip(
                    label: Text(kit),
                    selected: _kit == kit,
                    onSelected: _busy
                        ? null
                        : (_) => setState(() {
                              _kit = kit;
                              _clearSelection(region: false);
                              _points = [];
                              _pointer = null;
                              _inverted = false;
                              _tool = kit == 'Sketch'
                                  ? DrawingTool.pencil
                                  : kit == 'Ink'
                                      ? DrawingTool.pen
                                      : kit == 'Paint'
                                          ? DrawingTool.softBrush
                                          : DrawingTool.marker;
                              _width = kit == 'Sketch'
                                  ? 4
                                  : kit == 'Ink'
                                      ? 7
                                      : 24;
                              _opacity = kit == 'Paint' ? 0.7 : 1;
                            })))
                .toList()),
        const SizedBox(height: 12),
        Text('Tools', style: Theme.of(context).textTheme.titleMedium),
        _toolChoices(shapes: false),
        const SizedBox(height: 12),
        Text('Shapes', style: Theme.of(context).textTheme.titleMedium),
        _toolChoices(shapes: true),
        if (_tool.isSelection)
          const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                  'Tap an item or drag a box; Lasso traces an area. Drag selected items to move, or drag a corner to resize. Delete removes selected items; Undo restores them. Uploaded and merged artwork is selected as pixels.')),
        const SizedBox(height: 12),
        Text('Colors', style: Theme.of(context).textTheme.titleMedium),
        Wrap(
            spacing: 2,
            runSpacing: 2,
            children: drawingPalettes[_kit]!
                .map((color) => Tooltip(
                    message:
                        '#${color.toRadixString(16).substring(2).toUpperCase()}',
                    child: Semantics(
                        selected: _color == color,
                        label:
                            'Color #${color.toRadixString(16).substring(2).toUpperCase()}',
                        button: true,
                        child: SizedBox.square(
                            dimension: 48,
                            child: IconButton(
                                onPressed: _busy
                                    ? null
                                    : () => setState(() => _color = color),
                                icon: Container(
                                    width: 30,
                                    height: 30,
                                    decoration: BoxDecoration(
                                        color: Color(color),
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                            color: _color == color
                                                ? Theme.of(context)
                                                    .colorScheme
                                                    .primary
                                                : Colors.black26,
                                            width:
                                                _color == color ? 4 : 1))))))))
                .toList()),
        OutlinedButton.icon(
            onPressed: _busy ? null : _customColor,
            icon: Icon(Icons.palette, color: Color(_color)),
            label: const Text('Custom color')),
        Text('Brush size: ${_width.round()}'),
        Slider(
            value: _width,
            min: 1,
            max: 80,
            divisions: 79,
            label: '${_width.round()} pixels',
            onChanged: _busy ? null : (v) => setState(() => _width = v)),
        Text('Opacity: ${(_opacity * 100).round()}%'),
        Slider(
            value: _opacity,
            min: .05,
            max: 1,
            divisions: 19,
            onChanged: _busy ? null : (v) => setState(() => _opacity = v)),
        if (_shape)
          SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Filled shape'),
              value: _filled,
              onChanged: _busy ? null : (v) => setState(() => _filled = v)),
        Text('Fill / area tolerance: ${_tolerance.round()}'),
        Slider(
            value: _tolerance,
            max: 100,
            divisions: 100,
            onChanged: _busy ? null : (v) => setState(() => _tolerance = v)),
        const Divider(),
        SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Pen only'),
            subtitle: const Text(
                'Pen draws; fingers move the canvas. Two fingers pinch to zoom.'),
            value: _penOnly,
            onChanged: _busy
                ? null
                : (value) => setState(() {
                      _penOnly = value;
                      _points = [];
                      _pointer = null;
                    })),
        Text(_input),
        TextButton.icon(
            onPressed: () => showPenSetup(context),
            icon: const Icon(Icons.bluetooth),
            label: const Text('Connect a pen')),
        const Divider(),
        Text('Extract artwork', style: Theme.of(context).textTheme.titleMedium),
        const Text(
            'Paper cleanup protects faint lines. Select an area to limit cleanup. For busy photos, outline the drawing and refine with Remove area. Pinch with two fingers to zoom.'),
        OutlinedButton.icon(
            onPressed: _busy
                ? null
                : () => _pixel(
                    DrawingPixelOperation.paper, const DrawingPoint(0, 0)),
            icon: const Icon(Icons.content_cut),
            label: const Text('Remove paper background')),
        const Divider(),
        DropdownButtonFormField<int>(
            isExpanded: true,
            initialValue: _document!.frame.background,
            key: ValueKey(_document!.frame.background),
            decoration: const InputDecoration(labelText: 'Canvas background'),
            items: const [
              DropdownMenuItem(value: 0, child: Text('Transparent')),
              DropdownMenuItem(value: 0xffffffff, child: Text('White')),
              DropdownMenuItem(value: 0xfffff6e5, child: Text('Warm paper')),
              DropdownMenuItem(value: 0xff172235, child: Text('Dark'))
            ],
            onChanged: _busy
                ? null
                : (value) {
                    if (value != null)
                      _frame(_document!.frame.copyWith(background: value));
                  }),
        const SizedBox(height: 12),
        Wrap(spacing: 8, children: [
          TextButton(
              onPressed: _busy ? null : _merge,
              child: const Text('Merge paint')),
          TextButton(
              onPressed: _busy ? null : _clear,
              child: const Text('Clear canvas'))
        ]),
      ]);
  void _zoom(double multiplier) {
    final scale = _transform.value.getMaxScaleOnAxis();
    final factor = (scale * multiplier).clamp(.5, 5) / scale;
    _transform.value = Matrix4.copy(_transform.value)
      ..scaleByDouble(factor, factor, 1, 1);
  }

  Widget _canvas() => LayoutBuilder(builder: (context, constraints) {
        final document = _document!;
        final ratio = document.width / document.height;
        final width = math.min(
            constraints.maxWidth - 24, (constraints.maxHeight - 24) * ratio);
        final size = Size(width, width / ratio);
        return Center(
            child: SizedBox(
                width: size.width,
                height: size.height,
                child: CallbackShortcuts(
                    bindings: {
                      const SingleActivator(LogicalKeyboardKey.keyZ,
                          control: true): () => _history(false),
                      const SingleActivator(LogicalKeyboardKey.keyZ,
                          meta: true): () => _history(false),
                      const SingleActivator(LogicalKeyboardKey.keyZ,
                          control: true, shift: true): () => _history(true),
                      const SingleActivator(LogicalKeyboardKey.keyZ,
                          meta: true, shift: true): () => _history(true),
                      const SingleActivator(LogicalKeyboardKey.keyY,
                          control: true): () => _history(true),
                    },
                    child: Focus(
                        focusNode: _focus,
                        onKeyEvent: _key,
                        onFocusChange: (value) {
                          if (mounted) setState(() => _showCursor = value);
                        },
                        child: Semantics(
                            label:
                                'Drawing canvas. Tap or surround items to select. Drag selected items to move; corners resize. Arrow keys move selected items or the cursor. Delete or Backspace deletes the selection. Escape cancels. Two fingers zoom.',
                            child: MouseRegion(
                                cursor: _tool.isSelection
                                    ? SystemMouseCursors.basic
                                    : _tool == DrawingTool.pan
                                        ? SystemMouseCursors.grab
                                        : SystemMouseCursors.precise,
                                child: DrawingInputSurface(
                                    controller: _transform,
                                    pan: _tool == DrawingTool.pan,
                                    penOnly: _penOnly,
                                    onStart: (event, position) =>
                                        _down(event, position, size),
                                    onMove: (event, position) =>
                                        _move(event, position, size),
                                    onEnd: _finish,
                                    onCancel: () => setState(() {
                                          _points = [];
                                          _pointer = null;
                                          _inverted = false;
                                          _cancelSelectionGesture();
                                        }),
                                    child: CustomPaint(
                                        key: const ValueKey('drawing-canvas'),
                                        painter: DrawingCanvasPainter(
                                            DrawingDocument(
                                                width: document.width,
                                                height: document.height,
                                                frame: _previewFrame ??
                                                    document.frame),
                                            _previewFrame != null &&
                                                    _selectedRaster != null
                                                ? _selectionBase
                                                : _base,
                                            _points.isNotEmpty &&
                                                    !_rasterTool &&
                                                    !_activeTool.isSelection &&
                                                    _activeTool !=
                                                        DrawingTool.cutout
                                                ? _stroke(_points)
                                                : null,
                                            _outline,
                                            _showCursor ? _cursor : null,
                                            images: {
                                              ..._images,
                                              if (_previewFrame != null)
                                                ..._selectionImages
                                            },
                                            selection: _previewFrame == null
                                                ? _selection
                                                : const [],
                                            itemBounds: _itemBounds,
                                            handleRadius: 6 * document.width / size.width / _transform.value.getMaxScaleOnAxis()),
                                        child: const SizedBox.expand()))))))));
      });
  @override
  Widget build(BuildContext context) {
    final document = _document;
    return PopScope<OriginalFile>(
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) {
            _checkpoint?.cancel();
            unawaited(_saveDraft());
          }
        },
        child: Scaffold(
            backgroundColor: const Color(0xffeef5f4),
            appBar: AppBar(
                leading: IconButton(
                    onPressed: _busy ? null : _leave,
                    tooltip: 'Keep draft and return',
                    icon: const Icon(Icons.arrow_back)),
                title: const Text('Drawing studio'),
                actions: [
                  Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: FilledButton(
                          onPressed: _busy || document == null ? null : _use,
                          child: const Text('Use drawing')))
                ]),
            body: SafeArea(
                child: document == null
                    ? Center(
                        child: _busy
                            ? const CircularProgressIndicator()
                            : Padding(
                                padding: const EdgeInsets.all(24),
                                child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(_status),
                                      TextButton(
                                          onPressed: () async {
                                            try {
                                              await _drafts.drop(
                                                  widget.draftKey, _session);
                                            } catch (_) {}
                                            if (mounted) _load();
                                          },
                                          child: const Text(
                                              'Discard unreadable device draft and retry'))
                                    ])))
                    : Column(children: [
                        Material(
                            color: Colors.white,
                            child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 6),
                                child: Wrap(
                                    spacing: 4,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      IconButton(
                                          onPressed: _busy || !document.canUndo
                                              ? null
                                              : () => _history(false),
                                          tooltip: 'Undo',
                                          icon: const Icon(Icons.undo)),
                                      IconButton(
                                          onPressed: _busy || !document.canRedo
                                              ? null
                                              : () => _history(true),
                                          tooltip: 'Redo',
                                          icon: const Icon(Icons.redo)),
                                      const SizedBox(width: 12),
                                      Text(
                                          '${document.width} × ${document.height}',
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelMedium),
                                      IconButton(
                                          tooltip: 'Zoom in',
                                          onPressed:
                                              _busy ? null : () => _zoom(1.25),
                                          icon: const Icon(Icons.zoom_in)),
                                      IconButton(
                                          tooltip: 'Zoom out',
                                          onPressed:
                                              _busy ? null : () => _zoom(.8),
                                          icon: const Icon(Icons.zoom_out)),
                                      TextButton(
                                          onPressed: _busy
                                              ? null
                                              : () => setState(() => _transform
                                                  .value = Matrix4.identity()),
                                          child: const Text('Fit canvas')),
                                      TextButton.icon(
                                          onPressed:
                                              !CreationPermissions.of(context)
                                                          .export ||
                                                      _busy ||
                                                      _points.isNotEmpty
                                                  ? null
                                                  : _saveLocal,
                                          icon: const Icon(Icons.download),
                                          label: const Text('Save to device')),
                                      Text(drawingToolNames[_tool]!,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.bold)),
                                    ]))),
                        if (_hasItems || _selection.isNotEmpty)
                          DrawingSelectionToolbar(
                              count: _selectionItems.length,
                              busy: _busy || _pointer != null,
                              hasArea: _selection.isNotEmpty,
                              onDeselect: () => setState(_clearSelection),
                              onDelete: _deleteSelection,
                              onResize: _resizeItems,
                              onReorder: _reorderItems,
                              onKeepArea: () => _pixel(
                                  DrawingPixelOperation.cutout,
                                  const DrawingPoint(0, 0),
                                  polygon: _selectionPolygon)),
                        if (_busy && !_dialogOpen)
                          const LinearProgressIndicator(
                              semanticsLabel: 'Preparing drawing'),
                        Expanded(
                            child: LayoutBuilder(builder: (context, space) {
                          if (space.maxWidth >= 1000)
                            return Row(children: [
                              SizedBox(
                                  width: 288,
                                  child: Material(
                                      color: Colors.white,
                                      child: SingleChildScrollView(
                                          padding: const EdgeInsets.all(16),
                                          child: _controls()))),
                              Expanded(child: _canvas())
                            ]);
                          return ListView(children: [
                            SizedBox(
                                height: math
                                    .min(440, space.maxHeight * .72)
                                    .clamp(200, 440)
                                    .toDouble(),
                                child: _canvas()),
                            Padding(
                                padding: const EdgeInsets.all(16),
                                child: Material(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(16),
                                    child: Padding(
                                        padding: const EdgeInsets.all(16),
                                        child: _controls())))
                          ]);
                        })),
                        Material(
                            color: Colors.white,
                            child: Padding(
                                padding: const EdgeInsets.all(10),
                                child: Semantics(
                                    liveRegion: true,
                                    child: Text(_status,
                                        maxLines: 3,
                                        overflow: TextOverflow.ellipsis)))),
                      ]))));
  }
}
