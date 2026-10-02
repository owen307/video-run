import '../models/console_models.dart';

List<ShowPlaylist> parsePlaylistDocument(Object? body) {
  if (body is! Map) return const [];
  final legacy = body['playlistAll'];
  if (legacy is List) return _parseLegacy(legacy);
  final lists = body['playlists'];
  if (lists is List) {
    return [
      for (final entry in lists) _parsePlaylist(entry),
    ].whereType<ShowPlaylist>().toList();
  }
  final one = _parsePlaylist(body);
  if (one == null) return const [];
  if (one.items.isEmpty && body['items'] == null && body['playlist'] == null) {
    return const [];
  }
  return [one];
}

ShowPlaylist? _parsePlaylist(Object? node) {
  if (node is! Map) return null;
  final name = _readName(node);
  final id = _readId(node);
  if (name == null && id == null) return null;
  final items = <ShowItem>[];
  for (final key in ['items', 'playlist', 'presentations', 'cues']) {
    final raw = node[key];
    if (raw is! List) continue;
    var fallback = 0;
    for (final child in raw) {
      final item = _parseItem(child, fallback);
      if (item != null) {
        items.add(item);
        fallback += 1;
      }
    }
    break;
  }
  return ShowPlaylist(
    id: id ?? name ?? 'playlist',
    name: name ?? id ?? 'Playlist',
    items: items,
  );
}

ShowItem? _parseItem(Object? node, int fallbackIndex) {
  if (node is! Map) return null;
  final name = _readName(node) ?? _string(node['playlistItemName']);
  if (name == null || name.isEmpty) return null;
  final nestedIndex = node['id'] is Map ? _asInt((node['id'] as Map)['index']) : null;
  final index = _asInt(node['index']) ?? nestedIndex ?? fallbackIndex;
  return ShowItem(
    id: _readId(node) ?? '$index',
    name: name,
    index: index,
    triggerPath: _string(node['playlistItemLocation']),
  );
}

List<ShowPlaylist> _parseLegacy(List<Object?> nodes) {
  final playlists = <ShowPlaylist>[];
  void walk(Object? node) {
    if (node is! Map) return;
    final type = node['playlistType']?.toString() ?? '';
    final children = node['playlist'];
    if (type == 'playlistTypeGroup' && children is List) {
      for (final child in children) {
        walk(child);
      }
      return;
    }
    final name = _string(node['playlistName']);
    if (name != null && children is List) {
      final items = <ShowItem>[];
      for (final child in children) {
        if (child is! Map || child['playlistItemName'] == null) continue;
        final location = _string(child['playlistItemLocation']);
        items.add(
          ShowItem(
            id: location ?? '${items.length}',
            name: child['playlistItemName'].toString(),
            index: items.length,
            triggerPath: location,
          ),
        );
      }
      playlists.add(
        ShowPlaylist(
          id: _string(node['playlistLocation']) ?? name,
          name: name,
          items: items,
        ),
      );
      return;
    }
    if (children is List) {
      for (final child in children) {
        walk(child);
      }
    }
  }

  for (final node in nodes) {
    walk(node);
  }
  return playlists;
}

String? _readName(Map<dynamic, dynamic> node) {
  final direct = _string(node['name']) ?? _string(node['playlistName']);
  if (direct != null) return direct;
  final id = node['id'];
  if (id is Map) return _string(id['name']);
  return null;
}

String? _readId(Map<dynamic, dynamic> node) {
  final uuid = _string(node['uuid']);
  if (uuid != null) return uuid;
  final id = node['id'];
  if (id is String && id.isNotEmpty) return id;
  if (id is Map) {
    final nested = _string(id['uuid']);
    if (nested != null) return nested;
    final index = _asInt(id['index']);
    if (index != null) return '$index';
  }
  return null;
}

String? _string(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

int? _asInt(Object? value) => value is num ? value.toInt() : null;
