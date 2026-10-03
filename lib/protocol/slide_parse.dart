import 'dart:convert';
import 'dart:typed_data';

class ParsedSlide {
  const ParsedSlide({
    required this.index,
    required this.label,
    required this.hadImageField,
    this.embedded,
  });

  final int index;
  final String label;
  final bool hadImageField;
  final Uint8List? embedded;
}

/// Slides from `GET /v1/presentation/{uuid}`, in cue order.
List<ParsedSlide> parsePresentationSlides(Object? body) {
  if (body is! Map) return const [];
  final groups = body['groups'];
  if (groups is! List) return const [];
  final slides = <ParsedSlide>[];
  for (final group in groups) {
    if (group is! Map) continue;
    final rawSlides = group['slides'];
    if (rawSlides is! List) continue;
    for (final slide in rawSlides) {
      if (slide is! Map) continue;
      final index = slides.length;
      final text = _firstLine(slide['text']);
      final label = _text(slide['label']);
      final embedded = _embeddedImage(slide['image']);
      slides.add(
        ParsedSlide(
          index: index,
          label: text ?? label ?? 'Slide ${index + 1}',
          hadImageField: slide.containsKey('image') && slide['image'] != null && !_blank(slide['image']),
          embedded: embedded,
        ),
      );
    }
  }
  return slides;
}

bool looksLikeImage(List<int> bytes, String? contentType) {
  final type = (contentType ?? '').toLowerCase().split(';').first.trim();
  if (type.startsWith('image/')) return bytes.isNotEmpty;
  return _magic(bytes);
}

Uint8List? _embeddedImage(Object? value) {
  if (value is Uint8List && _magic(value)) return value;
  if (value is List && value.every((item) => item is int)) {
    final bytes = Uint8List.fromList(value.cast<int>());
    return _magic(bytes) ? bytes : null;
  }
  if (value is! String || value.trim().isEmpty) return null;
  var raw = value.trim();
  final comma = raw.indexOf(',');
  if (raw.startsWith('data:image/') && comma != -1) {
    raw = raw.substring(comma + 1);
  }
  try {
    final bytes = base64Decode(raw);
    return _magic(bytes) ? bytes : null;
  } catch (_) {
    return null;
  }
}

bool _magic(List<int> bytes) {
  if (bytes.length >= 3 && bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
    return true;
  }
  return bytes.length >= 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47 &&
      bytes[4] == 0x0D &&
      bytes[5] == 0x0A &&
      bytes[6] == 0x1A &&
      bytes[7] == 0x0A;
}

bool _blank(Object? value) => value is String && value.trim().isEmpty;

String? _text(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

String? _firstLine(Object? value) {
  final text = _text(value);
  if (text == null) return null;
  final line = text.split(RegExp(r'\r?\n')).first.trim();
  return line.isEmpty ? null : line;
}
