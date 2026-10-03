import 'dart:async';
import 'dart:convert';

import 'package:alpaca_video/models/console_models.dart';
import 'package:alpaca_video/protocol/alpaca_link.dart';
import 'package:alpaca_video/protocol/presentation_client.dart';
import 'package:alpaca_video/protocol/slide_parse.dart';
import 'package:alpaca_video/state/console_controller.dart';
import 'package:alpaca_video/ui/console_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('presentation slides keep cue order and do not invent an image', () {
    final slides = parsePresentationSlides(
      jsonDecode('''
{
  "id": {"uuid": "22222222-2222-4222-8222-222222222222", "name": "Amazing Grace", "index": 1},
  "groups": [
    {
      "name": "Verse 1",
      "slides": [
        {
          "enabled": true,
          "notes": "",
          "text": "Amazing Grace\\nHow sweet the sound",
          "label": ""
        }
      ]
    },
    {
      "name": "Chorus",
      "slides": [
        {
          "enabled": true,
          "notes": "",
          "text": "I once was lost",
          "label": "Acoustic"
        }
      ]
    }
  ],
  "has_timeline": false,
  "destination": "presentation"
}
'''),
    );
    expect(slides.map((slide) => slide.index), [0, 1]);
    expect(slides.map((slide) => slide.label), ['Amazing Grace', 'I once was lost']);
    expect(slides.every((slide) => slide.hadImageField), isFalse);
    expect(slides.every((slide) => slide.embedded == null), isTrue);
    expect(looksLikeImage(_png, 'image/png'), isTrue);
    expect(looksLikeImage(utf8.encode('{"error":"no image"}'), 'application/json'), isFalse);
  });

  test('a non-image thumbnail says the content type and the missing image field', () async {
    final host = _Host(images: false);
    final client = PresentationClient(httpClient: host);
    addTearDown(client.dispose);
    final lists = await client.connect(
      host: '127.0.0.1',
      port: 50001,
      wire: PresentationWire.http,
    );
    final song = lists.single.items[1];
    final loaded = await client.slidesFor(song, playlistId: lists.single.id);
    final missing = loaded.slides.single.missing ?? '';
    expect(loaded.slides.single.bytes, isNull);
    expect(missing, contains('GET /v1/presentation/22222222-2222-4222-8222-222222222222/thumbnail/0'));
    expect(missing, contains('application/json'));
    expect(missing, contains('not an image'));
    expect(missing, contains('no image field'));
    expect(host.hits.where((path) => path.endsWith('/thumbnail/0')).length, 2);

    await client.next();
    await client.previous();
    await client.clear();
    await client.trigger(playlistId: lists.single.id, index: song.index);
    await client.triggerCue(presentationUuid: song.presentationUuid!, cueIndex: 0);
    expect(host.hits, contains('/v1/trigger/next'));
    expect(host.hits, contains('/v1/trigger/previous'));
    expect(host.hits, contains('/v1/clear/layer/slide'));
    expect(host.hits, contains('/v1/playlist/${lists.single.id}/${song.index}/trigger'));
    expect(host.hits, contains('/v1/presentation/${song.presentationUuid}/0/trigger'));
  });

  testWidgets('tapping a host slide image triggers that cue', (tester) async {
    final host = _Host(images: true);
    SharedPreferences.setMockInitialValues({
      'video_run_settings_v1': jsonEncode({
        'presentationHost': '127.0.0.1',
        'presentationPort': 50001,
        'presentationWire': 'http',
      }),
    });
    final prefs = await SharedPreferences.getInstance();
    final controller = ConsoleController(
      link: _QuietLink(),
      presentation: PresentationClient(httpClient: host),
      preferences: prefs,
    );
    addTearDown(controller.dispose);
    await controller.boot();

    expect(controller.presentationSide, LinkSide.live);
    expect(controller.playlists.single.name, 'Sunday');
    expect(controller.playlists.single.items[1].slides.single.bytes, isNotNull);

    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: ConsolePage(controller: controller)));
    await tester.pumpAndSettle();

    expect(find.text('Sunday'), findsWidgets);
    expect(find.text('Walk-in'), findsNothing);
    expect(
      find.byWidgetPredicate((widget) => widget is Image && widget.image is MemoryImage),
      findsOneWidget,
    );
    expect(find.textContaining('no image field'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('slide-1-0')));
    await tester.pumpAndSettle();
    expect(host.hits, contains('/v1/presentation/22222222-2222-4222-8222-222222222222/0/trigger'));

    await controller.nextItem();
    await controller.previousItem();
    await controller.clearSlide();
    await controller.triggerIndex(controller.playlists.single.id, 1);
    expect(host.hits, contains('/v1/trigger/next'));
    expect(host.hits, contains('/v1/trigger/previous'));
    expect(host.hits, contains('/v1/clear/layer/slide'));
    expect(host.hits, contains('/v1/playlist/11111111-1111-4111-8111-111111111111/1/trigger'));
  });
}

const _playlistId = '11111111-1111-4111-8111-111111111111';
const _presentationId = '22222222-2222-4222-8222-222222222222';

const _png = <int>[
  137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, 0, 0, 0, 1, 8, 2, 0, 0, 0, 144, 119, 83, 222, 0, 0, 0, 12, 73, 68, 65, 84, 120, 156, 99, 248, 207, 192, 0, 0, 3, 1, 1, 0, 201, 254, 146, 239, 0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130,
];

class _Host extends http.BaseClient {
  _Host({required this.images});

  final bool images;
  final hits = <String>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    hits.add(path);
    if (path.contains('/thumbnail/')) {
      if (!images) {
        return _response(200, utf8.encode('{"error":"no image"}'), 'application/json');
      }
      return _response(200, _png, 'image/png');
    }
    if (path == '/v1/playlists') {
      return _response(
        200,
        utf8.encode('[{"id":{"uuid":"$_playlistId","name":"Sunday","index":0},"type":"playlist"}]'),
        'application/json',
      );
    }
    if (path == '/v1/playlist/$_playlistId') {
      return _response(200, utf8.encode(_detail), 'application/json');
    }
    if (path == '/v1/presentation/$_presentationId') {
      return _response(200, utf8.encode(_presentation), 'application/json');
    }
    if (path.endsWith('/trigger') || path.startsWith('/v1/trigger/') || path.startsWith('/v1/clear/')) {
      return _response(200, utf8.encode('{}'), 'application/json');
    }
    return _response(404, utf8.encode('{"missing":"$path"}'), 'application/json');
  }
}

http.StreamedResponse _response(int status, List<int> bytes, String type) {
  return http.StreamedResponse(
    Stream<List<int>>.value(bytes),
    status,
    headers: {'content-type': type},
  );
}

const _detail = '''
{
  "id": {"uuid": "$_playlistId", "name": "Sunday", "index": 0},
  "items": [
    {"id": {"index": 0, "name": "Songs", "uuid": ""}, "type": "header", "is_hidden": false, "is_pco": false},
    {
      "id": {"index": 1, "name": "Amazing Grace", "uuid": "33333333-3333-4333-8333-333333333333"},
      "type": "presentation",
      "is_hidden": false,
      "is_pco": false,
      "presentation_info": {"presentation_uuid": "$_presentationId", "arrangement_name": "Default"}
    }
  ]
}
''';

const _presentation = '''
{
  "id": {"uuid": "$_presentationId", "name": "Amazing Grace", "index": 1},
  "groups": [
    {
      "name": "Verse 1",
      "slides": [
        {"enabled": true, "notes": "", "text": "Amazing Grace\\nHow sweet the sound", "label": ""}
      ]
    }
  ],
  "has_timeline": false,
  "destination": "presentation"
}
''';

class _QuietLink implements LinkPort {
  final _incoming = StreamController<LinkEnvelope>.broadcast();

  @override
  int? boundPort = 1;

  @override
  String? lastError;

  @override
  Stream<LinkEnvelope> get incoming => _incoming.stream;

  @override
  Future<void> start({required bool broadcastFallback}) async {}

  @override
  void configure({
    required String instance,
    required String sourceName,
    required String show,
    required bool broadcastFallback,
  }) {}

  @override
  Future<void> stop() async {}

  @override
  void emit({
    required String type,
    required String name,
    Map<String, dynamic> payload = const {},
  }) {}
}
