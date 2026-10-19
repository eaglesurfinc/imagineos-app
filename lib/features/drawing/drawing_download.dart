import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';

typedef SaveDrawing = Future<bool> Function(Uint8List bytes, String name);

/// Browsers choose the destination on the current device (including tablets).
/// Native desktop runners can use their platform save dialog when available.
Future<bool> saveDrawingToDevice(Uint8List bytes, String name) async {
  final file = XFile.fromData(bytes, mimeType: 'image/png', name: name);
  if (kIsWeb) {
    await file.saveTo(name);
    return true; // A download was requested; its destination is browser-owned.
  }
  final location =
      await getSaveLocation(suggestedName: name, acceptedTypeGroups: const [
    XTypeGroup(label: 'PNG drawing', extensions: ['png'])
  ]);
  if (location == null) return false;
  await file.saveTo(location.path);
  return true;
}
