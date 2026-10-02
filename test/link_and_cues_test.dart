import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:alpaca_video/models/console_models.dart';
import 'package:alpaca_video/protocol/alpaca_link.dart';
import 'package:alpaca_video/protocol/playlist_parse.dart';
import 'package:alpaca_video/state/console_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('envelope uses the locked Alpaca Link fields', () {
    const envelope = LinkEnvelope(
      version: 1,
      source: LinkSource(app: 'video-run', instance: 'instance-1', name: 'Video Run'),
      type: 'video.cut',
      name: 'cam-2',
      payload: {'input': 2, 'label': 'Cam 2', 'me': 0},
      timestamp: '2026-10-02T22:40:00.000Z',
      id: '3c2b1a09-8877-4665-9abc-def012345678',
      show: 'Sunday',
    );
    final parsed = LinkEnvelope.tryParse(jsonEncode(envelope.toJson()));
    expect(parsed?.version, 1);
    expect(parsed?.source.app, 'video-run');
    expect(parsed?.source.instance, 'instance-1');
    expect(parsed?.source.name, 'Video Run');
    expect(parsed?.type, 'video.cut');
    expect(parsed?.name, 'cam-2');
    expect(parsed?.payload['input'], 2);
    expect(parsed?.timestamp, '2026-10-02T22:40:00.000Z');
    expect(parsed?.id, '3c2b1a09-8877-4665-9abc-def012345678');
    expect(parsed?.show, 'Sunday');
    expect(LinkEnvelope.tryParse('{"v":1,"from":"video-run","type":"video.cut","name":"cam-2"}'), isNull);
    expect(LinkEnvelope.tryParse('not json'), isNull);
  });

  test('multicast carries video.cut and drops this app on input', () async {
    final link = AlpacaLink();
    await link.start(broadcastFallback: false);
    link.configure(
      instance: 'listener',
      sourceName: 'Video Run',
      show: '',
      broadcastFallback: false,
    );
    final heard = <LinkEnvelope>[];
    final sub = link.incoming.listen(heard.add);
    final poke = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    poke.multicastLoopback = true;
    poke.multicastHops = alpacaLinkTtl;
    poke.send(_bytes(_sample(app: 'show-cues', type: 'cue.fire', name: 'wide')), InternetAddress(alpacaLinkGroup), alpacaLinkPort);
    poke.send(_bytes(_sample(app: linkAppId, type: 'cue.fire', name: 'wide')), InternetAddress(alpacaLinkGroup), alpacaLinkPort);
    await _waitFor(() => heard.isNotEmpty);
    expect(heard.single.source.app, 'show-cues');
    expect(heard.single.type, 'cue.fire');

    final sniff = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      alpacaLinkPort,
      reuseAddress: true,
    );
    sniff.multicastLoopback = true;
    sniff.joinMulticast(InternetAddress(alpacaLinkGroup));
    final seen = Completer<Map<String, dynamic>>();
    sniff.listen((event) {
      if (event != RawSocketEvent.read || seen.isCompleted) return;
      final datagram = sniff.receive();
      if (datagram == null) return;
      final decoded = jsonDecode(utf8.decode(datagram.data));
      if (decoded is Map && decoded['type'] == 'video.cut') {
        seen.complete(decoded.map((key, value) => MapEntry('$key', value)));
      }
    });
    await Future<void>.delayed(const Duration(milliseconds: 40));
    link.configure(instance: 'sender-1', sourceName: 'Video Run', show: 'Sunday', broadcastFallback: false);
    link.emit(type: 'video.cut', name: 'cam-2', payload: const {'input': 2, 'me': 0});
    final message = await seen.future.timeout(const Duration(seconds: 2));
    expect(message['version'], 1);
    expect((message['source'] as Map)['app'], linkAppId);
    expect(message['show'], 'Sunday');
    expect(message['name'], 'cam-2');
    await sub.cancel();
    poke.close();
    sniff.close();
    await link.dispose();
  });

  test('follow and send stay off until enabled, and own app is ignored', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final link = _MemoryLink();
    final off = ConsoleController(link: link, preferences: prefs);
    await off.boot();
    expect(off.followCues, isFalse);
    expect(off.sendLinkEvents, isFalse);
    expect(off.broadcastFallback, isFalse);
    await off.fireCue('close');
    await Future<void>.delayed(Duration.zero);
    expect(off.programId, 1);
    expect(off.lastCueResult, 'Follow is off');
    expect(link.sent, isEmpty);
    off.dispose();

    final followed = _MemoryLink();
    final on = ConsoleController(link: followed, preferences: prefs);
    await on.boot();
    await on.loadRehearsalMap();
    await on.setFollowCues(true);
    await on.fireCue('close');
    await Future<void>.delayed(Duration.zero);
    expect(on.programId, 2);
    expect(on.lastCueResult, 'Followed');
    expect(followed.sent, isEmpty);

    await on.setSendLinkEvents(true);
    await on.fireCue('wide');
    await Future<void>.delayed(Duration.zero);
    expect(
      followed.sent.any((envelope) => envelope.type == 'video.cut' && envelope.name == 'cam1'),
      isTrue,
    );
    expect(followed.sent.any((envelope) => envelope.type == 'cue.fire' && envelope.name == 'wide'), isTrue);
    expect(followed.sent.every((envelope) => envelope.version == 1), isTrue);
    expect(followed.sent.every((envelope) => envelope.source.app == linkAppId), isTrue);

    final before = on.programId;
    followed.inject(_sample(app: linkAppId, type: 'cue.fire', name: 'close'));
    await Future<void>.delayed(Duration.zero);
    expect(on.programId, before);
    on.dispose();
  });

  test('playlist documents cover the HTTP list and the legacy tree', () {
    final http = parsePlaylistDocument({
      'playlists': [
        {
          'id': {'uuid': 'sunday', 'name': 'Sunday gathering', 'index': 0},
          'items': [
            {
              'id': {'uuid': 'welcome', 'name': 'Welcome', 'index': 1},
            },
          ],
        },
      ],
    });
    expect(http.single.name, 'Sunday gathering');
    expect(http.single.items.single.name, 'Welcome');
    expect(http.single.items.single.index, 1);
  });
}

LinkEnvelope _sample({required String app, required String type, required String name}) {
  return LinkEnvelope(
    version: 1,
    source: LinkSource(app: app, instance: 'instance-$app', name: app),
    type: type,
    name: name,
    payload: const {},
    timestamp: '2026-10-02T22:40:00.000Z',
    id: '$app-$type-$name',
    show: '',
  );
}

List<int> _bytes(LinkEnvelope envelope) => utf8.encode(jsonEncode(envelope.toJson()));

Future<void> _waitFor(bool Function() ready) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (!ready()) {
    if (DateTime.now().isAfter(deadline)) fail('Timed out waiting for a link datagram');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

class _MemoryLink implements LinkPort {
  final _incoming = StreamController<LinkEnvelope>.broadcast();
  final sent = <LinkEnvelope>[];
  String instance = 'memory';
  String sourceName = 'Video Run';
  String show = '';

  @override
  int? boundPort = 44771;

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
  }) {
    this.instance = instance;
    this.sourceName = sourceName;
    this.show = show;
  }

  @override
  Future<void> stop() async {}

  @override
  void emit({
    required String type,
    required String name,
    Map<String, dynamic> payload = const {},
  }) {
    sent.add(
      LinkEnvelope(
        version: linkVersion,
        source: LinkSource(app: linkAppId, instance: instance, name: sourceName),
        type: type,
        name: name,
        payload: payload,
        timestamp: '2026-10-02T22:40:00.000Z',
        id: '$type-$name-${sent.length}',
        show: show,
      ),
    );
  }

  void inject(LinkEnvelope envelope) => _incoming.add(envelope);
}
