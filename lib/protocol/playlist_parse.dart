import '../models/console_models.dart';

/// Reads a ProPresenter playlist document.
///
/// `GET /v1/playlists` is a JSON array of playlist and group objects. Some
/// hosts wrap that same array in `{ "playlists": [...] }`. Groups nest further
/// playlists under `playlists` or `children`. `GET /v1/playlist/{id}` is one
/// object whose item names and indexes live on `id`, not beside it.
List<ShowPlaylist> parsePlaylistDocument(Object? body) {
  if (body is List) return _collectPlaylists(body);
  if (body is! Map) return const [];
  final legacy = body['playlistAll'];
  if (legacy is List) return _parseLegacy(List<Object?>.from(legacy));
  if (_isGroup(body)) {
    return _collectPlaylists(_nestedPlaylists(body) ?? const []);
  }
  final one = _parsePlaylist(body);
  if (one == null) return const [];
  return [one];
}

List<ShowPlaylist> _collectPlaylists(List<dynamic> nodes) {
  final playlists = <ShowPlaylist>[];
  for (final node in nodes) {
    if (node is! Map) continue;
    if (_isGroup(node)) {
      playlists.addAll(_collectPlaylists(_nestedPlaylists(node) ?? const []));
      continue;
    }
    final parsed = _parsePlaylist(node);
    if (parsed != null) playlists.add(parsed);
  }
  return playlists;
}

bool _isGroup(Map<dynamic, dynamic> node) {
  final type = node['type']?.toString().trim().toLowerCase() ?? '';
  if (type == 'group' || type == 'playlisttypegroup' || type == '0') return true;
  if (type == 'playlist' || type == 'playlisttypeplaylist' || type == '1') {
    return false;
  }
  final nested = _nestedPlaylists(node);
  if (nested == null) return false;
  return node['items'] is! List &&
      node['playlist'] is! List &&
      node['presentations'] is! List &&
      node['cues'] is! List;
}

List<dynamic>? _nestedPlaylists(Map<dynamic, dynamic> node) {
  for (final key in const ['playlists', 'children']) {
    final value = node[key];
    if (value is List) return value;
  }
  final type = node['type']?.toString().trim().toLowerCase() ?? '';
  if (type == 'group' || type == 'playlisttypegroup' || type == '0') {
    final playlist = node['playlist'];
    if (playlist is List) return playlist;
  }
  return null;
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
    itemType: _string(node['type']),
    presentationUuid: _presentationUuid(node),
  );
}

String? _presentationUuid(Map<dynamic, dynamic> node) {
  final info = node['presentation_info'];
  if (info is Map) {
    final uuid = _string(info['presentation_uuid']);
    if (uuid != null) return uuid;
  }
  return _string(node['target_uuid']);
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
  if (id is num) return '${id.toInt()}';
  if (id is Map) {
    final nested = _string(id['uuid']);
    if (nested != null) return nested;
    final name = _string(id['name']);
    if (name != null) return name;
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

int? _asInt(Object? value) {
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim());
  return null;
}
