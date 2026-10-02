import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mobileapp/seller_tunnel/photos/data/image_metadata.dart';

List<int> _ascii(String text) => latin1.encode(text);

List<int> _be16(int v) => [(v >> 8) & 0xFF, v & 0xFF];

List<int> _be32(int v) => [
  (v >> 24) & 0xFF,
  (v >> 16) & 0xFF,
  (v >> 8) & 0xFF,
  v & 0xFF,
];

List<int> _le16(int v) => [v & 0xFF, (v >> 8) & 0xFF];

List<int> _le32(int v) => [
  v & 0xFF,
  (v >> 8) & 0xFF,
  (v >> 16) & 0xFF,
  (v >> 24) & 0xFF,
];

/// A TIFF block with the [orientation] (when given), a `Make` and a GPS
/// latitude reference (big-endian, or little-endian with [little]).
List<int> _tiff({int? orientation, bool little = false}) {
  final u16 = little ? _le16 : _be16;
  final u32 = little ? _le32 : _be32;
  final entries = <List<int>>[
    if (orientation != null)
      [...u16(0x0112), ...u16(3), ...u32(1), ...u16(orientation), 0, 0],
    // Make: "Lea\0" inline.
    [...u16(0x010F), ...u16(2), ...u32(4), ..._ascii('Lea'), 0],
    // GPS IFD pointer, filled below.
    [...u16(0x8825), ...u16(4), ...u32(1), ...u32(0)],
  ];
  final ifd0Length = 2 + entries.length * 12 + 4;
  final gpsAt = 8 + ifd0Length;
  entries.last.setRange(8, 12, u32(gpsAt));
  return [
    ...(little ? _ascii('II') : _ascii('MM')),
    ...u16(42),
    ...u32(8),
    ...u16(entries.length),
    for (final entry in entries) ...entry,
    ...u32(0),
    // GPS IFD: GPSLatitudeRef "N".
    ...u16(1),
    ...u16(1), ...u16(2), ...u32(2), ..._ascii('N'), 0, 0, 0,
    ...u32(0),
  ];
}

List<int> _segment(int marker, List<int> payload) => [
  0xFF,
  marker,
  ..._be16(payload.length + 2),
  ...payload,
];

/// A small JPEG: SOI, [segments], then the encoder's segments (without
/// its JFIF segment unless [jfif]) and data, then [trailer].
Uint8List _jpeg({
  List<List<int>> segments = const [],
  List<int> trailer = const [],
  bool jfif = true,
}) {
  final image = img.Image(width: 6, height: 4);
  for (final pixel in image) {
    pixel
      ..r = pixel.x * 40
      ..g = pixel.y * 60
      ..b = 128;
  }
  final plain = img.encodeJpg(image);
  // The encoder starts with a JFIF segment.
  expect(plain.sublist(2, 4), [0xFF, 0xE0]);
  final afterJfif = 4 + ((plain[4] << 8) | plain[5]);
  return Uint8List.fromList([
    ...plain.sublist(0, 2),
    for (final segment in segments) ...segment,
    ...plain.sublist(jfif ? 2 : afterJfif),
    ...trailer,
  ]);
}

bool _contains(Uint8List bytes, String text) =>
    latin1.decode(bytes, allowInvalid: true).contains(text);

/// The CRC-32 of [data] (PNG chunks).
int _crc(List<int> data) {
  var crc = 0xFFFFFFFF;
  for (final byte in data) {
    crc ^= byte;
    for (var k = 0; k < 8; k++) {
      crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1;
    }
  }
  return crc ^ 0xFFFFFFFF;
}

List<int> _chunk(String type, List<int> data) => [
  ..._be32(data.length),
  ..._ascii(type),
  ...data,
  ..._be32(_crc([..._ascii(type), ...data])),
];

/// The chunks of a PNG: type → data.
List<(String, List<int>, bool)> _chunks(Uint8List png) {
  final chunks = <(String, List<int>, bool)>[];
  var at = 8;
  while (at < png.length) {
    final length = ByteData.sublistView(png, at, at + 4).getUint32(0);
    final type = latin1.decode(png.sublist(at + 4, at + 8));
    final data = png.sublist(at + 8, at + 8 + length);
    final crc = ByteData.sublistView(
      png,
      at + 8 + length,
      at + 12 + length,
    ).getUint32(0);
    chunks.add((type, data, crc == _crc([..._ascii(type), ...data])));
    at += 12 + length;
  }
  return chunks;
}

Uint8List _png({
  List<List<int>> extra = const [],
  List<int> trailer = const [],
}) {
  final plain = img.encodePng(img.Image(width: 3, height: 2));
  // Signature + IHDR (8 + 25 bytes), then the extra chunks.
  return Uint8List.fromList([
    ...plain.sublist(0, 33),
    for (final chunk in extra) ...chunk,
    ...plain.sublist(33),
    ...trailer,
  ]);
}

// ---------------------------------------------------------------------------
// HEIF.
// ---------------------------------------------------------------------------

List<int> _box(String type, List<int> content) => [
  ..._be32(content.length + 8),
  ..._ascii(type),
  ...content,
];

List<int> _fullBox(String type, int version, List<int> content) =>
    _box(type, [version, 0, 0, 0, ...content]);

List<int> _infe(int version, int id, String type, {String? contentType}) =>
    _fullBox('infe', version, [
      ...(version == 2 ? _be16(id) : _be32(id)),
      0, 0, // protection index
      ..._ascii(type),
      0, // empty name
      if (contentType != null) ...[..._ascii(contentType), 0],
    ]);

const _image = 'IMAGEDATA';
const _xmp = '<x:xmpmeta>GPS 48.85 secret</x:xmpmeta>';

List<int> get _exifPayload => [0, 0, 0, 6, ..._ascii('Exif'), 0, 0, ..._tiff()];

/// A HEIF file with an image, an EXIF and an XMP item in `mdat` (or, with
/// [inIdat], the EXIF in `idat`).
Uint8List _heif({
  int ilocVersion = 1,
  int iinfVersion = 0,
  int infeVersion = 2,
  int baseOffsetSize = 0,
  int baseOffsetByte = 0,
  int constructionMethod = 0,
  bool inIdat = false,
  bool withMetadata = true,
  bool largeMdat = false,
  int lengthOverride = -1,
}) {
  final ftyp = _box('ftyp', [..._ascii('heic'), 0, 0, 0, 0, ..._ascii('mif1')]);
  final items = <(int, String, String?, List<int>)>[
    (1, 'hvc1', null, _ascii(_image)),
    if (withMetadata) (2, 'Exif', null, _exifPayload),
    if (withMetadata) (3, 'mime', 'application/rdf+xml', _ascii(_xmp)),
    (4, 'mime', 'text/plain', _ascii('note')),
  ];
  bool inIdatItem(String type) => inIdat && type == 'Exif';
  final count = items.length + 1;
  final iinf = _fullBox('iinf', iinfVersion, [
    ...(iinfVersion == 0 ? _be16(count) : _be32(count)),
    ..._fullBox('infe', 1, [0, 9, 0, 0]),
    for (final (id, type, contentType, _) in items)
      ..._infe(infeVersion, id, type, contentType: contentType),
    ..._box('free', const []),
  ]);
  List<int> iloc(Map<int, int> offsets) => _fullBox('iloc', ilocVersion, [
    (4 << 4) | 4,
    baseOffsetSize << 4,
    ...(ilocVersion < 2 ? _be16(items.length) : _be32(items.length)),
    for (final (id, type, _, data) in items) ...[
      ...(ilocVersion < 2 ? _be16(id) : _be32(id)),
      if (ilocVersion > 0)
        ..._be16(
          inIdatItem(type)
              ? 1
              : type == 'Exif'
              ? constructionMethod
              : 0,
        ),
      0, 0, // data reference index
      ...List.filled(baseOffsetSize, baseOffsetByte),
      ..._be16(1),
      ..._be32(offsets[id]!),
      ..._be32(
        inIdatItem(type) && lengthOverride >= 0 ? lengthOverride : data.length,
      ),
    ],
  ]);
  final idat = inIdat ? _box('idat', _exifPayload) : const <int>[];
  List<int> head(Map<int, int> offsets) => [
    ...ftyp,
    ..._fullBox('meta', 0, [
      ..._fullBox('hdlr', 0, [0, 0, 0, 0, ..._ascii('pict')]),
      ...iinf,
      ...iloc(offsets),
      ...idat,
    ]),
  ];
  final mdatHeader = largeMdat ? 16 : 8;
  var at = head({for (final (id, _, _, _) in items) id: 0}).length + mdatHeader;
  final offsets = <int, int>{};
  final mdatContent = <int>[];
  for (final (id, type, _, data) in items) {
    if (inIdatItem(type)) {
      offsets[id] = 0;
      continue;
    }
    offsets[id] = at;
    at += data.length;
    mdatContent.addAll(data);
  }
  return Uint8List.fromList([
    ...head(offsets),
    if (largeMdat) ...[
      ..._be32(1),
      ..._ascii('mdat'),
      ..._be32(0),
      ..._be32(mdatContent.length + 16),
    ] else ...[
      ..._be32(mdatContent.length + 8),
      ..._ascii('mdat'),
    ],
    ...mdatContent,
  ]);
}

int _indexOf(Uint8List bytes, List<int> pattern) {
  outer:
  for (var i = 0; i + pattern.length <= bytes.length; i++) {
    for (var j = 0; j < pattern.length; j++) {
      if (bytes[i + j] != pattern[j]) continue outer;
    }
    return i;
  }
  return -1;
}

void main() {
  group('stripImageMetadata', () {
    test('returns anything that is not an image as is', () {
      final pdf = Uint8List.fromList(_ascii('%PDF-1.7 GPS secret'));
      expect(stripImageMetadata(pdf), same(pdf));
      expect(isMetadataImage(pdf), isFalse);
      expect(isMetadataImage(Uint8List(2)), isFalse);
    });

    group('JPEG', () {
      test('removes EXIF, XMP, IPTC, comments and trailing data, keeping '
          'the pixels', () {
        final source = _jpeg(
          segments: [
            _segment(0xE1, [..._ascii('Exif'), 0, 0, ..._tiff()]),
            _segment(0xE1, _ascii('http://ns.adobe.com/xap/1.0/\x00$_xmp')),
            _segment(0xED, _ascii('Photoshop 3.0\x00IPTC secret')),
            _segment(0xFE, _ascii('secret comment')),
            _segment(0xE2, _ascii('MPF\x00secret')),
            _segment(0xE2, _ascii('ICC_PROFILE\x00profile')),
            _segment(0xEE, _ascii('Adobe')),
          ],
          trailer: [0xFF, 0xD8, ..._ascii('secret second image')],
        );
        expect(isMetadataImage(source), isTrue);
        final stripped = stripImageMetadata(source);
        for (final secret in ['secret', 'Lea', 'xmpmeta', 'Exif']) {
          expect(_contains(stripped, secret), isFalse, reason: secret);
        }
        expect(_contains(stripped, 'ICC_PROFILE'), isTrue);
        expect(_contains(stripped, 'Adobe'), isTrue);
        expect(
          img.decodeJpg(stripped)!.getPixel(3, 2),
          img.decodeJpg(source)!.getPixel(3, 2),
        );
        expect(stripped.sublist(stripped.length - 2), [0xFF, 0xD9]);
      });

      test('keeps the orientation in a minimal EXIF segment', () {
        for (final little in [false, true]) {
          final source = _jpeg(
            segments: [
              _segment(0xE0, [..._ascii('JFIF'), 0, 1, 1, 0, 0, 1, 0, 1, 0, 0]),
              _segment(0xE1, [
                ..._ascii('Exif'),
                0,
                0,
                ..._tiff(orientation: 6, little: little),
              ]),
            ],
          );
          final stripped = stripImageMetadata(source);
          expect(_contains(stripped, 'Lea'), isFalse);
          final exif = img.decodeJpgExif(stripped)!;
          expect(exif.imageIfd.orientation, 6);
          expect(exif.gpsIfd.isEmpty, isTrue);
          // After the JFIF segment.
          expect(stripped.sublist(2, 4), [0xFF, 0xE0]);
          final upright = img.bakeOrientation(img.decodeJpg(stripped)!);
          expect([upright.width, upright.height], [4, 6]);
        }
        // Without JFIF: first.
        final first = stripImageMetadata(
          _jpeg(
            jfif: false,
            segments: [
              _segment(0xE1, [
                ..._ascii('Exif'),
                0,
                0,
                ..._tiff(orientation: 3),
              ]),
            ],
          ),
        );
        expect(first.sublist(2, 4), [0xFF, 0xE1]);
        expect(img.decodeJpgExif(first)!.imageIfd.orientation, 3);
      });

      test('an upright or unreadable orientation adds no EXIF', () {
        for (final tiff in [
          _tiff(orientation: 1),
          _tiff(orientation: 9),
          _tiff(),
          _ascii('XX'),
          [..._ascii('MM'), 0, 42, 0, 0, 0, 99],
        ]) {
          final stripped = stripImageMetadata(
            _jpeg(
              segments: [
                _segment(0xE1, [..._ascii('Exif'), 0, 0, ...tiff]),
              ],
            ),
          );
          expect(_contains(stripped, 'Exif'), isFalse);
        }
      });

      test('keeps the orientation of the first EXIF segment', () {
        List<int> exif(int orientation) => _segment(0xE1, [
          ..._ascii('Exif'),
          0,
          0,
          ..._tiff(orientation: orientation),
        ]);
        final stripped = stripImageMetadata(
          _jpeg(segments: [exif(6), exif(3)]),
        );
        expect(img.decodeJpgExif(stripped)!.imageIfd.orientation, 6);
      });

      test('drops metadata found between the scans of the image', () {
        final source = _jpeg();
        // Insert a comment and an XMP segment right before the end marker,
        // after the image data (as between two progressive scans).
        final at = source.length - 2;
        final withLate = Uint8List.fromList([
          ...source.sublist(0, at),
          ..._segment(0xFE, _ascii('late secret')),
          ..._segment(
            0xE1,
            _ascii('http://ns.adobe.com/xap/1.0/\x00late secret'),
          ),
          0xFF, 0xFF, // fill byte
          ...source.sublist(at),
        ]);
        final stripped = stripImageMetadata(withLate);
        expect(_contains(stripped, 'secret'), isFalse);
        expect(stripped, source);
      });

      test('returns a clean JPEG as is', () {
        final source = _jpeg(
          segments: [
            _segment(0xE0, [..._ascii('JFIF'), 0, 1, 1, 0, 0, 1, 0, 1, 0, 0]),
            [
              0xFF,
              0xFF,
              ..._segment(0xDD, [0, 0]),
            ],
          ],
        );
        expect(stripImageMetadata(source), same(source));
      });

      test('drops other APP0 extensions and keeps standalone markers', () {
        final source = _jpeg(
          segments: [
            _segment(0xE0, _ascii('JFXX\x00secret thumbnail')),
            [0xFF, 0x01],
            [0xFF, 0xD0],
          ],
        );
        final stripped = stripImageMetadata(source);
        expect(_contains(stripped, 'secret'), isFalse);
        expect(_indexOf(stripped, [0xFF, 0x01]), 2);
      });

      test('keeps the data of an image without end marker', () {
        final source = _jpeg(segments: [_segment(0xFE, _ascii('secret'))]);
        final cut = source.sublist(0, source.length - 2);
        final stripped = stripImageMetadata(cut);
        expect(_contains(stripped, 'secret'), isFalse);
        expect(
          stripped.sublist(stripped.length - 4),
          cut.sublist(cut.length - 4),
        );
      });

      test('throws a FormatException on a malformed JPEG', () {
        for (final bytes in [
          [0xFF, 0xD8, 0xFF, 0xE1, 0, 40, 1, 2],
          [0xFF, 0xD8, 0xFF, 0xE1, 0, 1, 1, 2],
          [0xFF, 0xD8, 0xFF, 0xD9],
          [0xFF, 0xD8, 0xFF, 0xFE, 0, 2, 0x12, 0x34],
          [0xFF, 0xD8, 0xFF, 0xFE, 0, 2],
          [0xFF, 0xD8, 0xFF, 0xFE],
        ]) {
          expect(
            () => stripImageMetadata(Uint8List.fromList(bytes)),
            throwsFormatException,
            reason: '$bytes',
          );
        }
      });
    });

    group('PNG', () {
      test('removes the text, time and EXIF chunks and trailing data', () {
        final source = _png(
          extra: [
            _chunk('tEXt', _ascii('Comment\x00secret')),
            _chunk('zTXt', _ascii('Author\x00\x00secret')),
            _chunk(
              'iTXt',
              _ascii('XML:com.adobe.xmp\x00\x00\x00\x00\x00$_xmp'),
            ),
            _chunk('tIME', [7, 234, 10, 2, 12, 0, 0]),
            _chunk('eXIf', _tiff()),
          ],
          trailer: _ascii('secret'),
        );
        expect(isMetadataImage(source), isTrue);
        final stripped = stripImageMetadata(source);
        expect(_contains(stripped, 'secret'), isFalse);
        expect(
          [for (final (type, _, _) in _chunks(stripped)) type],
          ['IHDR', 'IDAT', 'IEND'],
        );
        expect(img.decodePng(stripped)!.width, 3);
      });

      test('keeps the orientation in a minimal eXIf chunk', () {
        final stripped = stripImageMetadata(
          _png(extra: [_chunk('eXIf', _tiff(orientation: 8, little: true))]),
        );
        final chunks = _chunks(stripped);
        expect(
          [for (final (type, _, _) in chunks) type],
          ['IHDR', 'eXIf', 'IDAT', 'IEND'],
        );
        final (_, data, crcOk) = chunks[1];
        expect(crcOk, isTrue);
        expect(_contains(Uint8List.fromList(data), 'Lea'), isFalse);
        expect(data.sublist(0, 2), _ascii('MM'));
        expect(data[19], 8);
      });

      test('returns a clean PNG as is', () {
        final source = _png();
        expect(stripImageMetadata(source), same(source));
      });

      test('throws a FormatException on a truncated PNG', () {
        final source = _png(extra: [_chunk('tEXt', _ascii('a\x00b'))]);
        expect(
          () => stripImageMetadata(source.sublist(0, source.length - 6)),
          throwsFormatException,
        );
        expect(
          () => stripImageMetadata(source.sublist(0, 10)),
          throwsFormatException,
        );
      });
    });

    group('HEIF', () {
      void expectClean(Uint8List source, Uint8List stripped) {
        expect(stripped.length, source.length);
        expect(_contains(stripped, _image), isTrue);
        expect(_contains(stripped, 'note'), isTrue);
        expect(_contains(stripped, 'secret'), isFalse);
        expect(_contains(stripped, 'Lea'), isFalse);
        final exifAt = _indexOf(source, _exifPayload);
        expect(stripped.sublist(exifAt, exifAt + 18), [
          0, 0, 0, 0, 0x4D, 0x4D, 0, 42, 0, 0, 0, 8, 0, 0, 0, 0, 0, 0, //
        ]);
        expect(
          stripped.sublist(exifAt + 18, exifAt + _exifPayload.length).toSet(),
          {0},
        );
      }

      test('empties the EXIF and XMP items', () {
        final source = _heif();
        expect(isMetadataImage(source), isTrue);
        final stripped = stripImageMetadata(source);
        expectClean(source, stripped);
        final xmpAt = _indexOf(source, _ascii(_xmp));
        expect(stripped.sublist(xmpAt, xmpAt + _xmp.length).toSet(), {0x20});
      });

      test('reads every version of the item boxes', () {
        for (final source in [
          _heif(ilocVersion: 0),
          _heif(ilocVersion: 2, iinfVersion: 1, infeVersion: 3),
          _heif(baseOffsetSize: 4),
          _heif(baseOffsetSize: 8),
          _heif(largeMdat: true),
          _heif(inIdat: true),
        ]) {
          expectClean(source, stripImageMetadata(source));
        }
      });

      test('returns a HEIF without metadata as is', () {
        final source = _heif(withMetadata: false);
        expect(stripImageMetadata(source), same(source));
        final noMeta = Uint8List.fromList([
          ..._box('ftyp', [..._ascii('heic'), 0, 0, 0, 0]),
          ..._box('mdat', _ascii(_image)),
        ]);
        expect(stripImageMetadata(noMeta), same(noMeta));
        final noItems = Uint8List.fromList([
          ..._box('ftyp', [..._ascii('mif1'), 0, 0, 0, 0]),
          ..._fullBox('meta', 0, _fullBox('hdlr', 0, [0, 0, 0, 0])),
          // A last box running to the end of the file.
          ..._be32(0), ..._ascii('mdat'), ..._ascii(_image),
        ]);
        expect(stripImageMetadata(noItems), same(noItems));
      });

      test('throws a FormatException on an unusual layout', () {
        for (final source in [
          _heif(ilocVersion: 3),
          _heif(constructionMethod: 2),
          _heif(inIdat: true, lengthOverride: 9999),
          _heif(inIdat: true, lengthOverride: 0),
          _heif(baseOffsetSize: 2),
          // A negative, then a huge 64-bit base offset.
          _heif(baseOffsetSize: 8, baseOffsetByte: 0xFF),
          _heif(baseOffsetSize: 8, baseOffsetByte: 0x7F),
        ]) {
          expect(() => stripImageMetadata(source), throwsFormatException);
        }
        final source = _heif();
        expect(
          () => stripImageMetadata(source.sublist(0, 60)),
          throwsFormatException,
        );
        final badName = _heif();
        // The content type of the XMP item without its terminating zero.
        final at = _indexOf(badName, _ascii('application/rdf+xml'));
        badName.fillRange(at, at + 20, 0x61);
        expect(() => stripImageMetadata(badName), throwsFormatException);
      });

      test('throws a FormatException on boxes shorter than their fields', () {
        final ftyp = _box('ftyp', [..._ascii('heic'), 0, 0, 0, 0]);
        final exifInfe = _infe(2, 2, 'Exif');
        final iloc = _fullBox('iloc', 1, [0x44, 0, 0, 0]);
        for (final children in [
          // Item information without its count.
          [
            ..._box('iinf', [0, 0, 0, 0]),
            ...iloc,
          ],
          // Item location without its sizes and count.
          [
            ..._fullBox('iinf', 0, [0, 1, ...exifInfe]),
            ..._box('iloc', [1, 0, 0, 0, 0x44]),
          ],
          // An item entry cut in its type.
          [
            ..._fullBox('iinf', 0, [
              0,
              1,
              ..._box('infe', [2, 0, 0, 0, 0, 2, 0, 0, ..._ascii('Ex')]),
            ]),
            ...iloc,
          ],
          // An empty item entry.
          [
            ..._fullBox('iinf', 0, [0, 1, ..._box('infe', const [])]),
            ...iloc,
          ],
        ]) {
          final source = Uint8List.fromList([
            ...ftyp,
            ..._fullBox('meta', 0, children),
          ]);
          expect(() => stripImageMetadata(source), throwsFormatException);
        }
      });

      test('ignores other brands', () {
        final avif = Uint8List.fromList(
          _box('ftyp', [..._ascii('avif'), 0, 0, 0, 0]),
        );
        expect(isMetadataImage(avif), isFalse);
      });
    });
  });
}
