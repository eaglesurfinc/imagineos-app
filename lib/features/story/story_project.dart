import 'illustration_contract.dart';

/// Formats organize the child's work; they never supply story content.
enum StoryFormat {
  illustrated(
      'Illustrated pages', 'One drawing and your words on each page.', 1),
  comic(
      'Comic pages', 'Up to four panels on a page, read across then down.', 4),
  strip('Comic strips', 'Up to three panels in a row, read from left to right.',
      3);

  const StoryFormat(this.label, this.guide, this.perSheet);
  final String label, guide;
  final int perSheet;
  String get unit => this == illustrated ? 'page' : 'panel';
}

class StoryPanel {
  const StoryPanel(
      {required this.id,
      required this.reference,
      required this.characterName,
      required this.versionNumber,
      this.scene = '',
      this.dialogue = '',
      this.narration = '',
      this.sourceAvailable = true});
  final String id, characterName, scene, dialogue, narration;
  final StoryReference reference;
  final int versionNumber;
  final bool sourceAvailable;

  StoryPanel words({String? scene, String? dialogue, String? narration}) =>
      StoryPanel(
          id: id,
          reference: reference,
          characterName: characterName,
          versionNumber: versionNumber,
          scene: scene ?? this.scene,
          dialogue: dialogue ?? this.dialogue,
          narration: narration ?? this.narration,
          sourceAvailable: sourceAvailable);

  Map<String, dynamic> toJson() => {
        'id': id,
        'reference': reference.toJson(),
        'character_name': characterName,
        'version_number': versionNumber,
        'scene': scene,
        'dialogue': dialogue,
        'narration': narration,
        'source_available': sourceAvailable
      };
  Map<String, dynamic> get saveJson => Map.of(toJson())
    ..remove('character_name')
    ..remove('version_number')
    ..remove('source_available');

  factory StoryPanel.fromJson(Map<String, dynamic> json) => StoryPanel(
      id: json['id'] as String,
      reference: StoryReference.fromJson(
          Map<String, dynamic>.from(json['reference'] as Map)),
      characterName: json['character_name'] as String,
      versionNumber: json['version_number'] as int,
      scene: json['scene'] as String,
      dialogue: json['dialogue'] as String,
      narration: json['narration'] as String,
      sourceAvailable: json['source_available'] as bool? ?? true);
}

class StoryProject {
  StoryProject(
      {required this.id,
      required this.childId,
      this.title = '',
      this.format = StoryFormat.illustrated,
      this.revision = 0,
      List<StoryPanel> panels = const []})
      : panels = List.unmodifiable(panels);
  static const maxPanels = 24;
  final String id, childId, title;
  final StoryFormat format;
  final int revision;
  final List<StoryPanel> panels;
  bool get withinSaveLimits =>
      title.length <= 160 &&
      panels.length <= maxPanels &&
      panels.every((p) =>
          p.scene.length <= 2000 &&
          p.dialogue.length <= 20000 &&
          p.narration.length <= 20000);

  StoryProject copy(
          {String? title,
          StoryFormat? format,
          int? revision,
          List<StoryPanel>? panels}) =>
      StoryProject(
          id: id,
          childId: childId,
          title: title ?? this.title,
          format: format ?? this.format,
          revision: revision ?? this.revision,
          panels: panels ?? this.panels);

  Map<String, dynamic> toJson() => {
        'id': id,
        'child_id': childId,
        'title': title,
        'format': format.name,
        'revision': revision,
        'panels': panels.map((p) => p.toJson()).toList()
      };
  factory StoryProject.fromJson(Map<String, dynamic> json) {
    final story = StoryProject(
        id: json['id'] as String,
        childId: json['child_id'] as String,
        title: json['title'] as String,
        format: StoryFormat.values.byName(json['format']),
        revision: json['revision'] as int,
        panels: (json['panels'] as List)
            .map(
                (p) => StoryPanel.fromJson(Map<String, dynamic>.from(p as Map)))
            .toList());
    if (story.revision < 0 ||
        story.panels.length > maxPanels ||
        story.panels.map((p) => p.id).toSet().length != story.panels.length) {
      throw const FormatException('Invalid story draft');
    }
    return story;
  }
}
