import 'package:alpaca_video/protocol/atem_packet.dart';
import 'package:alpaca_video/protocol/atem_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('handshake and cut packets match the UDP layout', () {
    final hello = AtemPacket(
      flags: AtemFlags.syn,
      sessionId: 0x53AB,
      payload: const [0x01, 0, 0, 0, 0, 0, 0, 0],
    );
    expect(hello.encode(), [
      0x10, 0x14, 0x53, 0xAB, //
      0, 0, 0, 0, 0, 0, 0, 0, //
      1, 0, 0, 0, 0, 0, 0, 0,
    ]);

    final ack = AtemPacket(flags: AtemFlags.ack, sessionId: 0x1234, ackNumber: 1);
    expect(ack.encode(), [0x80, 0x0C, 0x12, 0x34, 0x00, 0x01, 0, 0, 0, 0, 0, 0]);

    final special = AtemPacket(
      flags: AtemFlags.ack,
      sessionId: 0x0001,
      ackNumber: 2,
      remoteSequence: 0x61,
    );
    expect(special.encode().sublist(8, 10), [0x00, 0x61]);

    final cut = AtemPacket(
      flags: AtemFlags.reliable,
      sessionId: 0x1234,
      localSequence: 1,
      payload: encodeCommand('DCut', meCommand(0)),
    );
    final bytes = cut.encode();
    expect(bytes.sublist(0, 12), [0x08, 0x18, 0x12, 0x34, 0, 0, 0, 0, 0, 0, 0, 1]);
    expect(bytes.sublist(12), [0x00, 0x0C, 0x00, 0x00, 0x44, 0x43, 0x75, 0x74, 0, 0, 0, 0]);
    expect(AtemPacket.decode(bytes).localSequence, 1);
  });

  test('state dump reads program, preview, and input names', () {
    final memory = AtemMemory();
    final longName = List<int>.filled(20, 0);
    final shortName = List<int>.filled(4, 0);
    for (var i = 0; i < 'Cam 1'.length; i++) {
      longName[i] = 'Cam 1'.codeUnitAt(i);
    }
    for (var i = 0; i < 'CAM1'.length; i++) {
      shortName[i] = 'CAM1'.codeUnitAt(i);
    }
    final inPr = <int>[0x00, 0x01, ...longName, ...shortName];
    final payload = [
      ...encodeCommand('InPr', inPr),
      ...encodeCommand('PrgI', busCommand(0, 2)),
      ...encodeCommand('PrvI', busCommand(0, 4)),
    ];
    expect(memory.readPayload(payload), isTrue);
    expect(memory.programId, 2);
    expect(memory.previewId, 4);
    expect(memory.inputs[1]?.longName, 'Cam 1');
    expect(memory.inputs[1]?.shortName, 'CAM1');
  });
}
