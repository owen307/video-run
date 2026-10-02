import 'dart:async';
import 'dart:io';

import 'package:alpaca_video/protocol/atem_client.dart';
import 'package:alpaca_video/protocol/atem_packet.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('client finishes the handshake and sends cut', () async {
    final server = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    final initAck = Completer<void>();
    final commands = <String>[];
    InternetAddress? clientAddress;
    int? clientPort;
    var dumped = false;

    server.listen((event) {
      if (event != RawSocketEvent.read) return;
      final datagram = server.receive();
      if (datagram == null) return;
      final packet = AtemPacket.decode(datagram.data);
      clientAddress = datagram.address;
      clientPort = datagram.port;
      if (packet.isSyn) {
        final reply = AtemPacket(
          flags: AtemFlags.syn,
          sessionId: packet.sessionId,
          payload: const [0x02, 0, 0, 0, 0, 0, 0, 0],
        );
        server.send(reply.encode(), datagram.address, datagram.port);
        return;
      }
      if (!dumped && packet.isAck) {
        dumped = true;
        final state = AtemPacket(
          flags: AtemFlags.reliable,
          sessionId: 0x7777,
          localSequence: 1,
          payload: [
            ...encodeCommand('PrgI', busCommand(0, 2)),
            ...encodeCommand('PrvI', busCommand(0, 4)),
          ],
        );
        final empty = AtemPacket(
          flags: AtemFlags.reliable,
          sessionId: 0x7777,
          localSequence: 2,
        );
        server.send(state.encode(), datagram.address, datagram.port);
        server.send(empty.encode(), datagram.address, datagram.port);
        return;
      }
      if (packet.isAck && packet.remoteSequence == 0x61 && !initAck.isCompleted) {
        initAck.complete();
        return;
      }
      if (packet.payload.isNotEmpty) {
        commands.addAll(decodeCommands(packet.payload).map((command) => command.tag));
        if (clientAddress != null && clientPort != null) {
          final ack = AtemPacket(
            flags: AtemFlags.ack,
            sessionId: 0x7777,
            ackNumber: packet.localSequence,
          );
          server.send(ack.encode(), clientAddress!, clientPort!);
        }
      }
    });

    final client = AtemClient();
    try {
      await client.connect('127.0.0.1', server.port, timeout: const Duration(seconds: 2));
      expect(client.snapshot.programId, 2);
      expect(client.snapshot.previewId, 4);
      expect(client.autoAvailable, isTrue);
      await initAck.future.timeout(const Duration(seconds: 2));
      await client.cut();
      await _waitFor(() => commands.contains('DCut'));
      await client.auto();
      await _waitFor(() => commands.contains('DAut'));
    } finally {
      await client.dispose();
      server.close();
    }
  });
}

Future<void> _waitFor(bool Function() ready) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (!ready()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for a switcher command');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}
