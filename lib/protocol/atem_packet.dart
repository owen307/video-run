import 'dart:typed_data';

class AtemFlags {
  const AtemFlags._();

  static const int reliable = 0x01;
  static const int syn = 0x02;
  static const int retransmit = 0x04;
  static const int requestRetransmit = 0x08;
  static const int ack = 0x10;
}

class AtemPacket {
  const AtemPacket({
    required this.flags,
    required this.sessionId,
    this.ackNumber = 0,
    this.unknown = 0,
    this.remoteSequence = 0,
    this.localSequence = 0,
    this.payload = const [],
  });

  final int flags;
  final int sessionId;
  final int ackNumber;
  final int unknown;
  final int remoteSequence;
  final int localSequence;
  final List<int> payload;

  bool get isSyn => flags & AtemFlags.syn != 0;
  bool get isAck => flags & AtemFlags.ack != 0;
  bool get isReliable => flags & AtemFlags.reliable != 0;

  Uint8List encode() {
    final length = 12 + payload.length;
    final word0 = ((flags & 0x1F) << 11) | (length & 0x7FF);
    final out = Uint8List(length);
    out[0] = (word0 >> 8) & 0xFF;
    out[1] = word0 & 0xFF;
    out[2] = (sessionId >> 8) & 0xFF;
    out[3] = sessionId & 0xFF;
    out[4] = (ackNumber >> 8) & 0xFF;
    out[5] = ackNumber & 0xFF;
    out[6] = (unknown >> 8) & 0xFF;
    out[7] = unknown & 0xFF;
    out[8] = (remoteSequence >> 8) & 0xFF;
    out[9] = remoteSequence & 0xFF;
    out[10] = (localSequence >> 8) & 0xFF;
    out[11] = localSequence & 0xFF;
    out.setRange(12, length, payload);
    return out;
  }

  static AtemPacket decode(List<int> data) {
    if (data.length < 12) {
      throw const FormatException('Short switcher packet');
    }
    final word0 = (data[0] << 8) | data[1];
    final declared = word0 & 0x7FF;
    final end = declared >= 12 && declared <= data.length ? declared : data.length;
    return AtemPacket(
      flags: (word0 >> 11) & 0x1F,
      sessionId: (data[2] << 8) | data[3],
      ackNumber: (data[4] << 8) | data[5],
      unknown: (data[6] << 8) | data[7],
      remoteSequence: (data[8] << 8) | data[9],
      localSequence: (data[10] << 8) | data[11],
      payload: data.sublist(12, end),
    );
  }
}

class AtemCommand {
  const AtemCommand(this.tag, this.data);

  final String tag;
  final List<int> data;
}

Uint8List encodeCommand(String tag, List<int> data) {
  if (tag.length != 4) {
    throw ArgumentError.value(tag, 'tag', 'Switcher commands are 4 characters');
  }
  final blockLen = 8 + data.length;
  final out = Uint8List(blockLen);
  out[0] = (blockLen >> 8) & 0xFF;
  out[1] = blockLen & 0xFF;
  out[4] = tag.codeUnitAt(0);
  out[5] = tag.codeUnitAt(1);
  out[6] = tag.codeUnitAt(2);
  out[7] = tag.codeUnitAt(3);
  out.setRange(8, blockLen, data);
  return out;
}

List<int> meCommand(int me) => [me & 0xFF, 0, 0, 0];

List<int> busCommand(int me, int input) => [
  me & 0xFF,
  0,
  (input >> 8) & 0xFF,
  input & 0xFF,
];

List<AtemCommand> decodeCommands(List<int> payload) {
  final commands = <AtemCommand>[];
  var offset = 0;
  while (offset + 8 <= payload.length) {
    final blockLen = (payload[offset] << 8) | payload[offset + 1];
    if (blockLen < 8 || offset + blockLen > payload.length) break;
    final tag = String.fromCharCodes(payload.sublist(offset + 4, offset + 8));
    commands.add(AtemCommand(tag, payload.sublist(offset + 8, offset + blockLen)));
    offset += blockLen;
  }
  return commands;
}
