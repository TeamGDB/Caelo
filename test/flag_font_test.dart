import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

/// The flags font is a subset cut by hand (#168), so the test reads the file
/// itself: a wrong cut would leave Windows with letters again, and no widget
/// test can see glyphs.
void main() {
  final bytes = File('assets/fonts/CaeloFlags.ttf').readAsBytesSync();
  final data = ByteData.sublistView(bytes);

  Map<String, int> tables() {
    final count = data.getUint16(4);
    return {
      for (var i = 0; i < count; i++)
        String.fromCharCodes(bytes.sublist(12 + i * 16, 16 + i * 16)): data
            .getUint32(12 + i * 16 + 8),
    };
  }

  /// Code points the font maps, from its format 12 cmap subtable.
  Set<int> mapped() {
    final cmap = tables()['cmap']!;
    final subtables = data.getUint16(cmap + 2);
    for (var i = 0; i < subtables; i++) {
      final at = cmap + data.getUint32(cmap + 4 + i * 8 + 4);
      if (data.getUint16(at) != 12) continue;
      final groups = data.getUint32(at + 12);
      return {
        for (var g = 0; g < groups; g++)
          for (
            var c = data.getUint32(at + 16 + g * 12);
            c <= data.getUint32(at + 20 + g * 12);
            c++
          )
            c,
      };
    }
    return {};
  }

  test('is a colour font that joins pairs into flags', () {
    // COLR and CPAL carry the colours; GSUB turns a pair of letters into a
    // flag. Without any of them a flag is two coloured letters at best.
    expect(tables().keys, containsAll(['COLR', 'CPAL', 'GSUB', 'cmap']));
  });

  test('covers every regional indicator letter', () {
    expect(mapped(), containsAll([for (var c = 0x1F1E6; c <= 0x1F1FF; c++) c]));
  });

  test('stays small: only the flags were kept', () {
    expect(bytes.length, lessThan(256 * 1024));
  });

  test('is declared in pubspec under the family the theme asks for', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('- family: CaeloFlags'));
    expect(pubspec, contains('- asset: assets/fonts/CaeloFlags.ttf'));
  });
}
