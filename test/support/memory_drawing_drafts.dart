import 'package:imagineos/features/drawing/drawing_drafts.dart';

class MemoryDrawingDrafts extends DrawingDraftStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value, int session) async {
    if (session == generation) values[key] = value;
  }

  @override
  Future<void> drop(String key, int session) async {
    if (session == generation) values.remove(key);
  }

  @override
  Future<void> invalidate() async {
    generation++;
    values.clear();
  }
}
