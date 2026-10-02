import 'dart:async';
import 'dart:io';
import 'dart:math';

import '../models/console_models.dart';
import 'atem_packet.dart';
import 'atem_state.dart';

class AtemLinkException implements Exception {
  AtemLinkException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AtemSnapshot {
  const AtemSnapshot({
    required this.inputs,
    required this.programId,
    required this.previewId,
    required this.productName,
  });

  final List<VideoInput> inputs;
  final int? programId;
  final int? previewId;
  final String? productName;
}

enum _Phase { idle, hello, running }

class AtemClient {
  final _events = StreamController<AtemSnapshot>.broadcast();
  final _memory = AtemMemory();
  final _random = Random();

  RawDatagramSocket? _socket;
  InternetAddress? _remoteAddress;
  int _remotePort = 9910;
  int _sessionId = 0;
  int _localSeq = 0;
  int _lastRemoteSeq = 0;
  bool _haveRemoteSeq = false;
  bool _sentInitAck = false;
  _Phase _phase = _Phase.idle;
  Timer? _keepalive;
  Completer<void>? _ready;
  bool autoAvailable = false;

  Stream<AtemSnapshot> get snapshots => _events.stream;

  AtemSnapshot get snapshot => AtemSnapshot(
    inputs: (_memory.inputs.values.toList()
      ..sort((a, b) => sourceRank(a.id).compareTo(sourceRank(b.id)))),
    programId: _memory.programId,
    previewId: _memory.previewId,
    productName: _memory.productName,
  );

  Future<void> connect(
    String host,
    int port, {
    Duration timeout = const Duration(seconds: 2),
  }) async {
    await close();
    final addresses = await InternetAddress.lookup(
      host,
    ).timeout(const Duration(seconds: 2));
    if (addresses.isEmpty) {
      throw AtemLinkException('Could not resolve $host');
    }
    _remoteAddress = addresses.first;
    _remotePort = port;
    _memory.inputs.clear();
    _memory.programId = null;
    _memory.previewId = null;
    _memory.productName = null;
    _sentInitAck = false;
    _haveRemoteSeq = false;
    _localSeq = 0;
    _sessionId = _random.nextInt(0xFFFE) + 1;
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    _socket = socket;
    _phase = _Phase.hello;
    _ready = Completer<void>();
    socket.listen(_onSocket);
    _sendHello();
    try {
      await _ready!.future.timeout(timeout);
    } on TimeoutException {
      await _shutdown();
      throw AtemLinkException('No reply from $host:$port');
    } on AtemLinkException {
      await _shutdown();
      rethrow;
    }
    autoAvailable = true;
    _keepalive = Timer.periodic(const Duration(seconds: 1), (_) => _keepAlive());
  }

  Future<void> setPreview(int input, {int me = 0}) {
    return _sendCommand('CPvI', busCommand(me, input));
  }

  Future<void> setProgram(int input, {int me = 0}) {
    return _sendCommand('CPgI', busCommand(me, input));
  }

  Future<void> cut({int me = 0}) {
    return _sendCommand('DCut', meCommand(me));
  }

  Future<void> auto({int me = 0}) {
    return _sendCommand('DAut', meCommand(me));
  }

  Future<void> close() async {
    await _shutdown();
    final ready = _ready;
    if (ready != null && !ready.isCompleted) {
      ready.completeError(AtemLinkException('Switcher link closed'));
    }
  }

  Future<void> _shutdown() async {
    _keepalive?.cancel();
    _keepalive = null;
    autoAvailable = false;
    _phase = _Phase.idle;
    _socket?.close();
    _socket = null;
  }

  void _sendHello() {
    _send(
      AtemPacket(
        flags: AtemFlags.syn,
        sessionId: _sessionId,
        payload: const [0x01, 0, 0, 0, 0, 0, 0, 0],
      ),
    );
  }

  void _sendAck(int remoteId, {int remoteSequence = 0}) {
    _send(
      AtemPacket(
        flags: AtemFlags.ack,
        sessionId: _sessionId,
        ackNumber: remoteId,
        remoteSequence: remoteSequence,
      ),
    );
  }

  Future<void> _sendCommand(String tag, List<int> data) async {
    if (_phase != _Phase.running || _socket == null) {
      throw AtemLinkException('Switcher is not linked');
    }
    _localSeq = (_localSeq + 1) & 0x7FFF;
    if (_localSeq == 0) _localSeq = 1;
    _send(
      AtemPacket(
        flags: AtemFlags.reliable,
        sessionId: _sessionId,
        localSequence: _localSeq,
        payload: encodeCommand(tag, data),
      ),
    );
  }

  void _send(AtemPacket packet) {
    final socket = _socket;
    final address = _remoteAddress;
    if (socket == null || address == null) return;
    socket.send(packet.encode(), address, _remotePort);
  }

  void _keepAlive() {
    if (_phase != _Phase.running || !_haveRemoteSeq) return;
    _sendAck(_lastRemoteSeq);
  }

  void _onSocket(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final socket = _socket;
    if (socket == null) return;
    final datagram = socket.receive();
    if (datagram == null) return;
    final AtemPacket packet;
    try {
      packet = AtemPacket.decode(datagram.data);
    } on FormatException {
      return;
    }

    if (_phase == _Phase.hello) {
      if (!packet.isSyn) return;
      final status = packet.payload.isEmpty ? 0 : packet.payload.first;
      if (status == 0x04) {
        _sendHello();
        return;
      }
      if (status != 0x02) return;
      _sendAck(packet.localSequence);
      _phase = _Phase.running;
      return;
    }

    if (packet.sessionId != 0) _sessionId = packet.sessionId;
    _lastRemoteSeq = packet.localSequence;
    _haveRemoteSeq = true;
    if (packet.isReliable) {
      // The first empty packet after the state dump is acknowledged with
      // remote sequence 0x61. That is the only client packet that fills it.
      final firstEmpty = packet.payload.isEmpty && !_sentInitAck;
      _sendAck(packet.localSequence, remoteSequence: firstEmpty ? 0x61 : 0);
      if (firstEmpty) _sentInitAck = true;
    }
    if (packet.payload.isNotEmpty && _memory.readPayload(packet.payload)) {
      _emit();
    }
    final ready = _ready;
    if (ready != null && !ready.isCompleted && _phase == _Phase.running) {
      ready.complete();
    }
  }

  void _emit() {
    if (_events.isClosed) return;
    _events.add(snapshot);
  }

  Future<void> dispose() async {
    await close();
    await _events.close();
  }
}
