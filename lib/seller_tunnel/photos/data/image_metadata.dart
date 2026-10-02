import 'dart:typed_data';

/// Privacy: removes the metadata (EXIF: GPS position, device, date; XMP;
/// IPTC; comments) of an image imported as a document, losslessly — the
/// pixels are never re-encoded:
///
/// - JPEG: the APP1 (EXIF, XMP), APP13 (IPTC), other application segments
///   and comments are dropped (JFIF, ICC colour profile and Adobe segments
///   kept), as well as anything after the image (multi-picture data); the
///   EXIF orientation, when not upright, is kept in a minimal EXIF segment
///   so that the image still shows the right way up;
/// - PNG: the `eXIf`, `tEXt`, `zTXt`, `iTXt` and `tIME` chunks are dropped
///   (an orientation is kept in a minimal `eXIf` chunk);
/// - HEIC / HEIF: the EXIF item is overwritten with an empty EXIF block
///   and the XMP item with spaces (the file keeps its structure; the
///   orientation of a HEIF image is not stored in its EXIF);
/// - anything else (PDF…) is returned as is.
///
/// Returns [bytes] itself when there is nothing to remove. Throws a
/// [FormatException] when an image cannot be parsed safely (truncated,
/// unusual HEIF layout).
Uint8List stripImageMetadata(Uint8List bytes) {
  if (!isMetadataImage(bytes)) return bytes;
  if (_isJpeg(bytes)) return _stripJpeg(bytes);
  if (_isPng(bytes)) return _stripPng(bytes);
  if (_isHeif(bytes)) return _stripHeif(bytes);
  return bytes;
}

/// Whether [bytes] are an image [stripImageMetadata] cleans (JPEG, PNG,
/// HEIF), from their first bytes.
bool isMetadataImage(Uint8List bytes) =>
    _isJpeg(bytes) || _isPng(bytes) || _isHeif(bytes);

// ---------------------------------------------------------------------------
// Reading helpers.
// ---------------------------------------------------------------------------

Never _malformed(String what) => throw FormatException('Malformed $what');

int _u16(Uint8List b, int at, {bool little = false}) {
  if (at < 0 || at + 2 > b.length) _malformed('image');
  return little ? b[at] | (b[at + 1] << 8) : (b[at] << 8) | b[at + 1];
}

int _u32(Uint8List b, int at, {bool little = false}) {
  if (at < 0 || at + 4 > b.length) _malformed('image');
  return little
      ? b[at] | (b[at + 1] << 8) | (b[at + 2] << 16) | (b[at + 3] << 24)
      : (b[at] << 24) | (b[at + 1] << 16) | (b[at + 2] << 8) | b[at + 3];
}

/// The unsigned big-endian integer of [size] bytes (0, 4 or 8) at [at].
int _uint(Uint8List b, int at, int size) => switch (size) {
  0 => 0,
  4 => _u32(b, at),
  8 => (_u32(b, at) << 32) | _u32(b, at + 4),
  _ => _malformed('HEIF item location'),
};

bool _startsWith(Uint8List b, int at, List<int> prefix) {
  if (at + prefix.length > b.length) return false;
  for (var i = 0; i < prefix.length; i++) {
    if (b[at + i] != prefix[i]) return false;
  }
  return true;
}

List<int> _ascii(String text) => text.codeUnits;

/// The EXIF orientation (1–8) of the TIFF block at [start] of [b], or 1.
int _tiffOrientation(Uint8List b, int start) {
  try {
    final little = _startsWith(b, start, _ascii('II'));
    if (!little && !_startsWith(b, start, _ascii('MM'))) return 1;
    final ifd = start + _u32(b, start + 4, little: little);
    final count = _u16(b, ifd, little: little);
    for (var i = 0; i < count; i++) {
      final entry = ifd + 2 + i * 12;
      if (_u16(b, entry, little: little) == 0x0112) {
        final value = _u16(b, entry + 8, little: little);
        return value >= 1 && value <= 8 ? value : 1;
      }
    }
  } on FormatException {
    // An unreadable EXIF block: the image is shown as stored.
  }
  return 1;
}

/// A TIFF block holding only the [orientation] (big-endian, one IFD
/// entry).
List<int> _orientationTiff(int orientation) => [
  ..._ascii('MM'), 0, 42, 0, 0, 0, 8, // header, IFD at 8
  0, 1, // one entry
  0x01, 0x12, 0, 3, 0, 0, 0, 1, 0, orientation, 0, 0, // SHORT orientation
  0, 0, 0, 0, // no next IFD
];

// ---------------------------------------------------------------------------
// JPEG.
// ---------------------------------------------------------------------------

bool _isJpeg(Uint8List b) =>
    b.length > 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF;

Uint8List _stripJpeg(Uint8List b) {
  final kept = <Uint8List>[];
  var orientation = 1;
  var changed = false;
  var at = 2;
  while (true) {
    if (at + 2 > b.length || b[at] != 0xFF) _malformed('JPEG');
    final marker = b[at + 1];
    if (marker == 0xFF) {
      // Fill byte.
      at++;
      continue;
    }
    if (marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7)) {
      kept.add(Uint8List.sublistView(b, at, at + 2));
      at += 2;
      continue;
    }
    if (marker == 0xD9) _malformed('JPEG');
    final length = _u16(b, at + 2);
    final end = at + 2 + length;
    if (length < 2 || end > b.length) _malformed('JPEG');
    final segment = Uint8List.sublistView(b, at, end);
    if (marker == 0xDA) {
      // Start of scan: the image data runs to the end of image marker.
      final imageEnd = _jpegEnd(b, end);
      kept.add(Uint8List.sublistView(b, at, imageEnd));
      if (imageEnd < b.length) changed = true;
      break;
    }
    if (_dropsJpegSegment(marker, segment)) {
      changed = true;
      if (marker == 0xE1 && _startsWith(segment, 4, _ascii('Exif\x00\x00'))) {
        orientation = _tiffOrientation(segment, 10);
      }
    } else {
      kept.add(segment);
    }
    at = end;
  }
  if (!changed) return b;
  final out = BytesBuilder(copy: false)..add(const [0xFF, 0xD8]);
  // The orientation segment goes after a JFIF segment, else first.
  var exifAt = kept.isNotEmpty && kept.first[1] == 0xE0 ? 1 : 0;
  for (final segment in kept) {
    if (exifAt == 0 && orientation != 1) {
      final payload = [
        ..._ascii('Exif\x00\x00'),
        ..._orientationTiff(orientation),
      ];
      out.add([
        0xFF,
        0xE1,
        (payload.length + 2) >> 8,
        (payload.length + 2) & 0xFF,
        ...payload,
      ]);
    }
    exifAt--;
    out.add(segment);
  }
  return out.takeBytes();
}

/// Index just after the end of image marker that follows [from] (image
/// data byte-stuffs 0xFF, so 0xFF 0xD9 only appears there), or the end of
/// [b] for a file without it.
int _jpegEnd(Uint8List b, int from) {
  for (var i = from; i + 1 < b.length; i++) {
    if (b[i] == 0xFF && b[i + 1] == 0xD9) return i + 2;
  }
  return b.length;
}

bool _dropsJpegSegment(int marker, Uint8List segment) => switch (marker) {
  // JFIF (APP0): kept, other APP0 extensions dropped.
  0xE0 => !_startsWith(segment, 4, _ascii('JFIF\x00')),
  // APP2: the ICC colour profile is kept, multi-picture data dropped.
  0xE2 => !_startsWith(segment, 4, _ascii('ICC_PROFILE\x00')),
  // APP14 (Adobe colour transform) is needed to decode the image.
  0xEE => false,
  // APP1 (EXIF, XMP), APP3–APP13 (IPTC…), APP15, comments.
  final m when (m >= 0xE1 && m <= 0xEF) || m == 0xFE => true,
  _ => false,
};

// ---------------------------------------------------------------------------
// PNG.
// ---------------------------------------------------------------------------

const _pngSignature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

bool _isPng(Uint8List b) => _startsWith(b, 0, _pngSignature);

const _pngMetadataChunks = {'eXIf', 'tEXt', 'zTXt', 'iTXt', 'tIME'};

Uint8List _stripPng(Uint8List b) {
  final kept = <Uint8List>[];
  var orientation = 1;
  var changed = false;
  var at = 8;
  while (true) {
    final length = _u32(b, at);
    final end = at + 12 + length;
    if (end > b.length) _malformed('PNG');
    final type = String.fromCharCodes(b, at + 4, at + 8);
    if (_pngMetadataChunks.contains(type)) {
      changed = true;
      if (type == 'eXIf') orientation = _tiffOrientation(b, at + 8);
    } else {
      kept.add(Uint8List.sublistView(b, at, end));
    }
    at = end;
    if (type == 'IEND') break;
  }
  if (at < b.length) changed = true;
  if (!changed) return b;
  final out = BytesBuilder(copy: false)..add(_pngSignature);
  for (final (index, chunk) in kept.indexed) {
    out.add(chunk);
    // The orientation chunk goes right after IHDR (before the image data).
    if (index == 0 && orientation != 1) {
      out.add(_pngChunk('eXIf', _orientationTiff(orientation)));
    }
  }
  return out.takeBytes();
}

Uint8List _pngChunk(String type, List<int> data) {
  final body = [..._ascii(type), ...data];
  final crc = _crc32(body);
  return Uint8List.fromList([..._be32(data.length), ...body, ..._be32(crc)]);
}

List<int> _be32(int v) => [
  (v >> 24) & 0xFF,
  (v >> 16) & 0xFF,
  (v >> 8) & 0xFF,
  v & 0xFF,
];

int _crc32(List<int> data) {
  var crc = 0xFFFFFFFF;
  for (final byte in data) {
    crc ^= byte;
    for (var k = 0; k < 8; k++) {
      crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1;
    }
  }
  return crc ^ 0xFFFFFFFF;
}

// ---------------------------------------------------------------------------
// HEIF (ISO base media file format).
// ---------------------------------------------------------------------------

const _heifBrands = {'heic', 'heix', 'heim', 'heis', 'mif1', 'msf1', 'hevc'};

bool _isHeif(Uint8List b) =>
    b.length >= 12 &&
    _startsWith(b, 4, _ascii('ftyp')) &&
    _heifBrands.contains(String.fromCharCodes(b, 8, 12));

/// A box of the file: its type, where its content starts and its end.
typedef _Box = ({String type, int content, int end});

List<_Box> _boxes(Uint8List b, int start, int end) {
  final boxes = <_Box>[];
  var at = start;
  while (at + 8 <= end) {
    var size = _u32(b, at);
    var header = 8;
    if (size == 1) {
      size = _uint(b, at + 8, 8);
      header = 16;
    } else if (size == 0) {
      size = end - at;
    }
    if (size < header || at + size > end) _malformed('HEIF');
    boxes.add((
      type: String.fromCharCodes(b, at + 4, at + 8),
      content: at + header,
      end: at + size,
    ));
    at += size;
  }
  return boxes;
}

_Box? _child(List<_Box> boxes, String type) {
  for (final box in boxes) {
    if (box.type == type) return box;
  }
  return null;
}

/// The null-terminated string at [at] and the index after it.
(String, int) _cString(Uint8List b, int at, int end) {
  var i = at;
  while (i < end && b[i] != 0) {
    i++;
  }
  if (i >= end) _malformed('HEIF item');
  return (String.fromCharCodes(b, at, i), i + 1);
}

Uint8List _stripHeif(Uint8List b) {
  final meta = _child(_boxes(b, 0, b.length), 'meta');
  if (meta == null) return b;
  // `meta` is a full box: version and flags first.
  final children = _boxes(b, meta.content + 4, meta.end);
  final infos = _child(children, 'iinf');
  final locations = _child(children, 'iloc');
  if (infos == null || locations == null) return b;
  final exif = <int>{};
  final xmp = <int>{};
  final infoVersion = b[infos.content];
  final firstEntry = infos.content + (infoVersion == 0 ? 6 : 8);
  for (final entry in _boxes(b, firstEntry, infos.end)) {
    if (entry.type != 'infe') continue;
    final version = b[entry.content];
    if (version < 2) continue;
    var at = entry.content + 4;
    final id = version == 2 ? _u16(b, at) : _u32(b, at);
    at += (version == 2 ? 2 : 4) + 2;
    final type = String.fromCharCodes(b, at, at + 4);
    if (type == 'Exif') exif.add(id);
    if (type == 'mime') {
      final (_, afterName) = _cString(b, at + 4, entry.end);
      final (contentType, _) = _cString(b, afterName, entry.end);
      if (contentType.contains('xmp') || contentType.contains('rdf')) {
        xmp.add(id);
      }
    }
  }
  if (exif.isEmpty && xmp.isEmpty) return b;
  final idat = _child(children, 'idat');
  final out = Uint8List.fromList(b);
  for (final (id, start, length) in _itemExtents(b, locations, idat)) {
    if (exif.contains(id)) {
      out.fillRange(start, start + length, 0);
      if (length >= _emptyExif.length) {
        out.setRange(start, start + _emptyExif.length, _emptyExif);
      }
    } else if (xmp.contains(id)) {
      out.fillRange(start, start + length, 0x20);
    }
  }
  return out;
}

/// An empty EXIF item: offset 0 to the TIFF header, then a big-endian
/// TIFF header and an IFD without entries.
// dart format off
const _emptyExif = [
  0, 0, 0, 0,
  0x4D, 0x4D, 0, 42, 0, 0, 0, 8,
  0, 0, 0, 0, 0, 0,
];
// dart format on

/// Every extent of the items of the `iloc` box: item id, file offset,
/// length.
List<(int, int, int)> _itemExtents(Uint8List b, _Box iloc, _Box? idat) {
  final version = b[iloc.content];
  if (version > 2) _malformed('HEIF item location');
  var at = iloc.content + 4;
  final offsetSize = b[at] >> 4;
  final lengthSize = b[at] & 0xF;
  final baseOffsetSize = b[at + 1] >> 4;
  final indexSize = version == 0 ? 0 : b[at + 1] & 0xF;
  at += 2;
  final count = version < 2 ? _u16(b, at) : _u32(b, at);
  at += version < 2 ? 2 : 4;
  final extents = <(int, int, int)>[];
  for (var i = 0; i < count; i++) {
    final id = version < 2 ? _u16(b, at) : _u32(b, at);
    at += version < 2 ? 2 : 4;
    var method = 0;
    if (version > 0) {
      method = _u16(b, at) & 0xF;
      at += 2;
    }
    at += 2; // data reference index
    final base = _uint(b, at, baseOffsetSize);
    at += baseOffsetSize;
    final extentCount = _u16(b, at);
    at += 2;
    for (var e = 0; e < extentCount; e++) {
      at += indexSize;
      final offset = _uint(b, at, offsetSize);
      at += offsetSize;
      final length = _uint(b, at, lengthSize);
      at += lengthSize;
      final origin = switch (method) {
        0 => 0,
        1 when idat != null => idat.content,
        _ => _malformed('HEIF item location'),
      };
      final start = origin + base + offset;
      final limit = method == 0 ? b.length : idat!.end;
      if (length == 0 || start < origin || start + length > limit) {
        _malformed('HEIF item extent');
      }
      extents.add((id, start, length));
    }
  }
  return extents;
}
