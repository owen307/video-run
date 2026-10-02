import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';

import '../models/console_models.dart';

const alpacaLinkGroup = '239.255.42.77';
const alpacaLinkPort = 44771;
const alpacaLinkTtl = 1;
const linkAppId = 'video-run';
const linkVersion = 1;

abstract class LinkPort {
  Stream<LinkEnvelope> get incoming;
  int? get boundPort;
  String? get lastError;

  Future<void> start({required bool broadcastFallback});

  void configure({
    required String instance,
    required String sourceName,
    required String show,
    required bool broadcastFallback,
  });

  Future<void> stop();

  void emit({
    required String type,
    required String name,
    Map<String, dynamic> payload = const {},
  });
}

class AlpacaLink implements LinkPort {
  final _incoming = StreamController<LinkEnvelope>.broadcast();
  RawDatagramSocket? _socket;
  String _instance = '';
  String _sourceName = 'Video Run';
  String _show = '';
  bool _broadcastFallback = false;

  @override
  Stream<LinkEnvelope> get incoming => _incoming.stream;

  @override
  int? boundPort;

  @override
  String? lastError;

  @override
  void configure({
    required String instance,
    required String sourceName,
    required String show,
    required bool broadcastFallback,
  }) {
    _instance = instance;
    _sourceName = sourceName.trim().isEmpty ? 'Video Run' : sourceName.trim();
    _show = show;
    _broadcastFallback = broadcastFallback;
    final socket = _socket;
    if (socket == null) return;
    try {
      socket.broadcastEnabled = broadcastFallback;
    } catch (_) {
      // Multicast still works when the platform refuses broadcast.
    }
  }

  @override
  Future<void> start({required bool broadcastFallback}) async {
    await stop();
    _broadcastFallback = broadcastFallback;
    await _acquireMulticastLock();
    try {
      final socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        alpacaLinkPort,
        reuseAddress: true,
      );
      socket.multicastLoopback = true;
      socket.multicastHops = alpacaLinkTtl;
      if (broadcastFallback) {
        try {
          socket.broadcastEnabled = true;
        } catch (_) {
          lastError = 'Broadcast fallback is unavailable on this host';
        }
      }
      socket.joinMulticast(InternetAddress(alpacaLinkGroup));
      _socket = socket;
      boundPort = socket.port;
      lastError = broadcastFallback && !socket.broadcastEnabled
          ? 'Broadcast fallback is unavailable on this host'
          : null;
      socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        final datagram = socket.receive();
        if (datagram == null) return;
        final text = utf8.decode(datagram.data, allowMalformed: true);
        final envelope = LinkEnvelope.tryParse(text);
        if (envelope == null || envelope.version != linkVersion) return;
        if (envelope.source.app == linkAppId) return;
        if (!_incoming.isClosed) _incoming.add(envelope);
      });
    } catch (_) {
      boundPort = null;
      lastError = 'Link could not join $alpacaLinkGroup:$alpacaLinkPort';
    }
  }

  @override
  void emit({
    required String type,
    required String name,
    Map<String, dynamic> payload = const {},
  }) {
    final socket = _socket;
    if (socket == null || _instance.isEmpty) return;
    final bytes = utf8.encode(
      jsonEncode(
        LinkEnvelope(
          version: linkVersion,
          source: LinkSource(app: linkAppId, instance: _instance, name: _sourceName),
          type: type,
          name: name,
          payload: payload,
          timestamp: DateTime.now().toUtc().toIso8601String(),
          id: newLinkId(),
          show: _show,
        ).toJson(),
      ),
    );
    final group = InternetAddress(alpacaLinkGroup);
    _send(socket, group, alpacaLinkPort, bytes);
    if (_broadcastFallback) {
      _send(socket, InternetAddress('255.255.255.255'), alpacaLinkPort, bytes);
    }
  }

  void _send(RawDatagramSocket socket, InternetAddress address, int port, List<int> bytes) {
    try {
      socket.send(bytes, address, port);
    } catch (_) {
      // One bad destination should not stop the others.
    }
  }

  @override
  Future<void> stop() async {
    _socket?.close();
    _socket = null;
    boundPort = null;
    await _releaseMulticastLock();
  }

  Future<void> dispose() async {
    await stop();
    await _incoming.close();
  }
}

String newLinkId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

const _multicastChannel = MethodChannel('video.run/multicast');

Future<void> _acquireMulticastLock() async {
  try {
    await _multicastChannel.invokeMethod<void>('acquire');
  } catch (_) {
    // Desktop builds have no multicast lock. Android acquires it in MainActivity.
  }
}

Future<void> _releaseMulticastLock() async {
  try {
    await _multicastChannel.invokeMethod<void>('release');
  } catch (_) {
    // Same as acquire: missing on desktop and in unit tests.
  }
}
