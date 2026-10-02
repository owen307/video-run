import '../models/console_models.dart';
import 'atem_packet.dart';

class AtemMemory {
  final Map<int, VideoInput> inputs = {};
  int? programId;
  int? previewId;
  String? productName;

  bool readPayload(List<int> payload) {
    var changed = false;
    for (final command in decodeCommands(payload)) {
      if (_readCommand(command)) changed = true;
    }
    return changed;
  }

  bool _readCommand(AtemCommand command) {
    final data = command.data;
    if ((command.tag == 'PrgI' || command.tag == 'PrvI') && data.length >= 4) {
      final source = (data[2] << 8) | data[3];
      if (command.tag == 'PrgI') {
        if (programId == source) return false;
        programId = source;
        return true;
      }
      if (previewId == source) return false;
      previewId = source;
      return true;
    }
    if (command.tag == 'InPr' && data.length >= 4) {
      final id = (data[0] << 8) | data[1];
      final longName = data.length >= 22 ? _name(data, 2, 20) : '';
      final shortName = data.length >= 26 ? _name(data, 22, 4) : '';
      final input = VideoInput(
        id: id,
        longName: longName.isEmpty ? describeSource(id) : longName,
        shortName: shortName.isEmpty ? shortSource(id) : shortName,
      );
      if (inputs[id] == input) return false;
      inputs[id] = input;
      return true;
    }
    if (command.tag == '_pin' && data.isNotEmpty) {
      final name = _name(data, 0, data.length);
      if (name.isEmpty || name == productName) return false;
      productName = name;
      return true;
    }
    return false;
  }
}

String _name(List<int> data, int offset, int length) {
  final end = offset + length < data.length ? offset + length : data.length;
  final bytes = <int>[];
  for (var i = offset; i < end; i++) {
    final byte = data[i];
    if (byte == 0) break;
    if (byte >= 32 && byte <= 126) bytes.add(byte);
  }
  return String.fromCharCodes(bytes).trim();
}
