import 'dart:convert';

enum LinkSide { connecting, live, mock }

enum PresentationWire { http, legacy }

enum CueActionKind {
  cutToInput,
  previewInput,
  take,
  next,
  previous,
  clear,
  triggerItem,
}

class VideoInput {
  const VideoInput({
    required this.id,
    required this.longName,
    required this.shortName,
  });

  final int id;
  final String longName;
  final String shortName;

  String get slug {
    final raw = shortName.trim().isNotEmpty ? shortName : longName;
    final slug = raw
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return slug.isEmpty ? 'input-$id' : slug;
  }

  @override
  bool operator ==(Object other) =>
      other is VideoInput &&
      other.id == id &&
      other.longName == longName &&
      other.shortName == shortName;

  @override
  int get hashCode => Object.hash(id, longName, shortName);
}

class ShowItem {
  const ShowItem({
    required this.id,
    required this.name,
    required this.index,
    this.triggerPath,
  });

  final String id;
  final String name;
  final int index;
  final String? triggerPath;
}

class ShowPlaylist {
  const ShowPlaylist({
    required this.id,
    required this.name,
    required this.items,
  });

  final String id;
  final String name;
  final List<ShowItem> items;
}

class CueBinding {
  const CueBinding({
    required this.cueName,
    required this.kind,
    this.inputId,
    this.playlistId,
    this.itemIndex,
  });

  final String cueName;
  final CueActionKind kind;
  final int? inputId;
  final String? playlistId;
  final int? itemIndex;

  Map<String, dynamic> toJson() => {
    'cueName': cueName,
    'kind': kind.name,
    'inputId': inputId,
    'playlistId': playlistId,
    'itemIndex': itemIndex,
  };

  static CueBinding? fromJson(Map<String, dynamic> json) {
    final name = json['cueName'];
    final kindName = json['kind'];
    if (name is! String || kindName is! String) return null;
    CueActionKind? kind;
    for (final value in CueActionKind.values) {
      if (value.name == kindName) kind = value;
    }
    if (kind == null || name.trim().isEmpty) return null;
    return CueBinding(
      cueName: name.trim(),
      kind: kind,
      inputId: _asInt(json['inputId']),
      playlistId: json['playlistId'] is String ? json['playlistId'] as String : null,
      itemIndex: _asInt(json['itemIndex']),
    );
  }
}

class LinkSource {
  const LinkSource({required this.app, required this.instance, required this.name});

  final String app;
  final String instance;
  final String name;

  Map<String, dynamic> toJson() => {'app': app, 'instance': instance, 'name': name};
}

class LinkEnvelope {
  const LinkEnvelope({
    required this.version,
    required this.source,
    required this.type,
    required this.name,
    required this.payload,
    required this.timestamp,
    required this.id,
    required this.show,
  });

  final int version;
  final LinkSource source;
  final String type;
  final String name;
  final Map<String, dynamic> payload;
  final String timestamp;
  final String id;
  final String show;

  Map<String, dynamic> toJson() => {
    'version': version,
    'source': source.toJson(),
    'type': type,
    'name': name,
    'payload': payload,
    'timestamp': timestamp,
    'id': id,
    'show': show,
  };

  static LinkEnvelope? tryParse(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    final dynamic decoded;
    try {
      decoded = jsonDecode(trimmed);
    } catch (_) {
      return null;
    }
    if (decoded is! Map) return null;
    final version = decoded['version'];
    final type = decoded['type'];
    final name = decoded['name'];
    final timestamp = decoded['timestamp'];
    final id = decoded['id'];
    final show = decoded['show'];
    final sourceRaw = decoded['source'];
    if (version is! num ||
        type is! String ||
        type.isEmpty ||
        name is! String ||
        timestamp is! String ||
        timestamp.isEmpty ||
        id is! String ||
        id.isEmpty ||
        show is! String ||
        sourceRaw is! Map) {
      return null;
    }
    final app = sourceRaw['app'];
    final instance = sourceRaw['instance'];
    final sourceName = sourceRaw['name'];
    if (app is! String || app.isEmpty || instance is! String || instance.isEmpty || sourceName is! String) {
      return null;
    }
    final payload = <String, dynamic>{};
    final payloadRaw = decoded['payload'];
    if (payloadRaw is Map) {
      payloadRaw.forEach((key, value) {
        payload[key.toString()] = value;
      });
    } else if (decoded.containsKey('payload') && payloadRaw != null) {
      return null;
    }
    return LinkEnvelope(
      version: version.toInt(),
      source: LinkSource(app: app, instance: instance, name: sourceName),
      type: type,
      name: name,
      payload: payload,
      timestamp: timestamp,
      id: id,
      show: show,
    );
  }
}

int? _asInt(Object? value) => value is num ? value.toInt() : null;

String describeSource(int id) {
  if (id == 0) return 'Black';
  if (id >= 1 && id <= 40) return 'Cam $id';
  if (id == 1000) return 'Color Bars';
  if (id == 2001) return 'Color 1';
  if (id == 2002) return 'Color 2';
  if (id == 3010) return 'Media 1';
  if (id == 3011) return 'Media 1 Key';
  if (id == 3020) return 'Media 2';
  if (id == 3021) return 'Media 2 Key';
  return 'Input $id';
}

String shortSource(int id) {
  if (id == 0) return 'BLK';
  if (id >= 1 && id <= 40) return 'C$id';
  if (id == 1000) return 'BARS';
  if (id == 2001) return 'COL1';
  if (id == 2002) return 'COL2';
  if (id == 3010) return 'MP1';
  if (id == 3020) return 'MP2';
  return '$id';
}

int sourceRank(int id) {
  if (id == 0) return 100000;
  if (id >= 1000) return 50000 + id;
  return id;
}

CueBinding? matchCue(List<CueBinding> bindings, String name) {
  final key = name.trim().toLowerCase();
  if (key.isEmpty) return null;
  for (final binding in bindings) {
    if (binding.cueName.trim().toLowerCase() == key) return binding;
  }
  return null;
}

String cueActionLabel(
  CueBinding binding, {
  String Function(int id)? inputName,
  String Function(String id)? playlistName,
}) {
  switch (binding.kind) {
    case CueActionKind.cutToInput:
      final id = binding.inputId;
      return id == null
          ? 'Cut'
          : 'Cut to ${inputName?.call(id) ?? describeSource(id)}';
    case CueActionKind.previewInput:
      final id = binding.inputId;
      return id == null
          ? 'Preview'
          : 'Preview ${inputName?.call(id) ?? describeSource(id)}';
    case CueActionKind.take:
      return 'Auto take';
    case CueActionKind.next:
      return 'Presentation next';
    case CueActionKind.previous:
      return 'Presentation previous';
    case CueActionKind.clear:
      return 'Clear slide';
    case CueActionKind.triggerItem:
      final playlist = binding.playlistId == null
          ? 'playlist'
          : (playlistName?.call(binding.playlistId!) ?? binding.playlistId!);
      final index = binding.itemIndex;
      return index == null ? 'Trigger $playlist' : 'Trigger $playlist #${index + 1}';
  }
}

List<VideoInput> mockInputs() => const [
  VideoInput(id: 1, longName: 'Cam 1', shortName: 'CAM1'),
  VideoInput(id: 2, longName: 'Cam 2', shortName: 'CAM2'),
  VideoInput(id: 3, longName: 'Cam 3', shortName: 'CAM3'),
  VideoInput(id: 4, longName: 'Cam 4', shortName: 'CAM4'),
  VideoInput(id: 5, longName: 'Cam 5', shortName: 'CAM5'),
  VideoInput(id: 6, longName: 'Cam 6', shortName: 'CAM6'),
  VideoInput(id: 3010, longName: 'Media 1', shortName: 'MP1'),
  VideoInput(id: 1000, longName: 'Color Bars', shortName: 'BARS'),
  VideoInput(id: 0, longName: 'Black', shortName: 'BLK'),
];

List<ShowPlaylist> mockPlaylists() => const [
  ShowPlaylist(
    id: 'sunday',
    name: 'Sunday gathering',
    items: [
      ShowItem(id: 'walk', name: 'Walk-in', index: 0),
      ShowItem(id: 'welcome', name: 'Welcome', index: 1),
      ShowItem(id: 'song', name: 'Song', index: 2),
      ShowItem(id: 'message', name: 'Message', index: 3),
      ShowItem(id: 'close', name: 'Close', index: 4),
    ],
  ),
  ShowPlaylist(
    id: 'notices',
    name: 'Announcements',
    items: [
      ShowItem(id: 'week', name: 'This week', index: 0),
      ShowItem(id: 'youth', name: 'Youth night', index: 1),
      ShowItem(id: 'giving', name: 'Giving', index: 2),
    ],
  ),
  ShowPlaylist(
    id: 'rehearsal',
    name: 'Rehearsal',
    items: [
      ShowItem(id: 'slate', name: 'Slate', index: 0),
      ShowItem(id: 'count', name: 'Countdown', index: 1),
      ShowItem(id: 'loop', name: 'Loop', index: 2),
    ],
  ),
];

List<VideoInput> fallbackLiveInputs() => [
  for (var id = 1; id <= 8; id++)
    VideoInput(id: id, longName: 'Input $id', shortName: '$id'),
  const VideoInput(id: 0, longName: 'Black', shortName: 'BLK'),
];
