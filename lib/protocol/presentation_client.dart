import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/console_models.dart';
import 'playlist_parse.dart';

class PresentationException implements Exception {
  PresentationException(this.message);

  final String message;

  @override
  String toString() => message;
}

class PresentationClient {
  PresentationClient({http.Client? httpClient}) : _http = httpClient ?? http.Client();

  final http.Client _http;
  WebSocketChannel? _socket;
  StreamSubscription<dynamic>? _subscription;
  String _host = '';
  int _port = 50001;
  String _secret = '';
  PresentationWire _wire = PresentationWire.http;

  Future<List<ShowPlaylist>> connect({
    required String host,
    required int port,
    required PresentationWire wire,
    String secret = '',
  }) async {
    await close();
    _host = _normalizeHost(host);
    _port = port;
    _secret = secret.trim();
    _wire = wire;
    if (_host.isEmpty) {
      throw PresentationException('No presentation address');
    }
    if (wire == PresentationWire.http) {
      return _loadHttp();
    }
    return _loadLegacy();
  }

  Future<ShowPlaylist> fetchDetail(String playlistId) async {
    if (_wire != PresentationWire.http) {
      throw PresentationException('Playlist detail is part of the legacy list');
    }
    final body = await _get('/v1/playlist/${Uri.encodeComponent(playlistId)}');
    final parsed = parsePlaylistDocument(body);
    if (parsed.isEmpty) {
      return ShowPlaylist(id: playlistId, name: playlistId, items: const []);
    }
    final playlist = parsed.first;
    return ShowPlaylist(
      id: playlistId,
      name: playlist.name,
      items: playlist.items,
    );
  }

  Future<void> next() => _act(
    httpPath: '/v1/trigger/next',
    legacy: {'action': 'presentationTriggerNext'},
  );

  Future<void> previous() => _act(
    httpPath: '/v1/trigger/previous',
    legacy: {'action': 'presentationTriggerPrevious'},
  );

  Future<void> clear() => _act(
    httpPath: '/v1/clear/layer/slide',
    legacy: {'action': 'clearAll'},
  );

  Future<void> trigger({
    required String playlistId,
    required int index,
    String? path,
  }) {
    return _act(
      httpPath: '/v1/playlist/${Uri.encodeComponent(playlistId)}/$index/trigger',
      legacy: {
        'action': 'presentationTriggerIndex',
        'slideIndex': '0',
        'presentationPath': path ?? playlistId,
      },
    );
  }

  Future<void> close() async {
    await _subscription?.cancel();
    _subscription = null;
    try {
      await _socket?.sink.close();
    } catch (_) {
      // The socket may already be gone.
    }
    _socket = null;
  }

  Future<void> dispose() async {
    await close();
    _http.close();
  }

  Future<void> _act({
    required String httpPath,
    required Map<String, dynamic> legacy,
  }) async {
    if (_host.isEmpty) {
      throw PresentationException('Presentation host is not linked');
    }
    if (_wire == PresentationWire.http) {
      await _get(httpPath);
      return;
    }
    final socket = _socket;
    if (socket == null) {
      throw PresentationException('Presentation socket is closed');
    }
    socket.sink.add(jsonEncode(legacy));
  }

  Future<List<ShowPlaylist>> _loadHttp() async {
    final body = await _get('/v1/playlists');
    final summaries = parsePlaylistDocument(body);
    if (summaries.isEmpty) return const [];
    final detailed = <ShowPlaylist>[];
    final cap = summaries.length < 8 ? summaries.length : 8;
    for (var i = 0; i < summaries.length; i++) {
      final summary = summaries[i];
      if (summary.items.isNotEmpty || i >= cap) {
        detailed.add(summary);
        continue;
      }
      try {
        detailed.add(await fetchDetail(summary.id));
      } catch (_) {
        detailed.add(summary);
      }
    }
    return detailed;
  }

  Future<Object?> _get(String path) async {
    final uri = Uri.parse('http://$_host:$_port$path');
    final headers = <String, String>{
      'Accept': 'application/json',
      'User-Agent': 'VideoRun/1.0',
    };
    if (_secret.isNotEmpty) {
      headers['Authorization'] = 'Bearer $_secret';
    }
    final http.Response response;
    try {
      response = await _http.get(uri, headers: headers).timeout(const Duration(seconds: 3));
    } on TimeoutException {
      throw PresentationException('Presentation host timed out at $_host:$_port');
    } on http.ClientException {
      throw PresentationException('Presentation host did not answer at $_host:$_port');
    } on SocketException {
      throw PresentationException('Presentation host did not answer at $_host:$_port');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw PresentationException(
        'Presentation host returned ${response.statusCode} for $path',
      );
    }
    if (response.bodyBytes.isEmpty) return const <String, dynamic>{};
    try {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw PresentationException(
        'Presentation host did not return JSON. Use the HTTP API port (often 50001), or switch this console to the legacy remote socket.',
      );
    }
  }

  Future<List<ShowPlaylist>> _loadLegacy() async {
    final channel = WebSocketChannel.connect(Uri.parse('ws://$_host:$_port/remote'));
    _socket = channel;
    final ready = Completer<List<ShowPlaylist>>();
    try {
      await channel.ready.timeout(const Duration(seconds: 3));
    } on TimeoutException {
      await close();
      throw PresentationException('Legacy remote socket timed out at $_host:$_port');
    } catch (_) {
      await close();
      throw PresentationException('Legacy remote socket did not answer at $_host:$_port');
    }
    _subscription = channel.stream.listen(
      (message) {
        if (ready.isCompleted) return;
        final Map<String, dynamic> json;
        try {
          final decoded = jsonDecode(message.toString());
          if (decoded is! Map) return;
          json = decoded.map((key, value) => MapEntry(key.toString(), value));
        } catch (_) {
          return;
        }
        final action = json['action']?.toString() ?? '';
        if (action == 'authenticate') {
          final ok = json['authenticated'] == 1 || json['authenticated'] == true;
          if (!ok) {
            final error = json['error']?.toString() ?? '';
            ready.completeError(
              PresentationException(
                error.isEmpty ? 'Remote password was refused' : error,
              ),
            );
            return;
          }
          channel.sink.add(jsonEncode({'action': 'playlistRequestAll'}));
          return;
        }
        if (action == 'playlistRequestAll') {
          ready.complete(parsePlaylistDocument(json));
        }
      },
      onError: (Object _) {
        if (!ready.isCompleted) {
          ready.completeError(
            PresentationException('Legacy remote socket failed at $_host:$_port'),
          );
        }
      },
      onDone: () {
        if (!ready.isCompleted) {
          ready.completeError(
            PresentationException('Legacy remote socket closed at $_host:$_port'),
          );
        }
      },
    );
    channel.sink.add(
      jsonEncode({
        'action': 'authenticate',
        'protocol': '701',
        'password': _secret,
      }),
    );
    try {
      return await ready.future.timeout(const Duration(seconds: 4));
    } on TimeoutException {
      await close();
      throw PresentationException('Legacy remote socket timed out at $_host:$_port');
    } on PresentationException {
      await close();
      rethrow;
    }
  }
}

String _normalizeHost(String raw) {
  var host = raw.trim();
  host = host.replaceFirst(RegExp(r'^https?://'), '');
  host = host.replaceFirst(RegExp(r'^wss?://'), '');
  host = host.replaceFirst(RegExp(r'/.*$'), '');
  return host;
}
