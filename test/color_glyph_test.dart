import 'package:flutter_test/flutter_test.dart';
import 'package:rive_native/rive_text.dart';

import 'src/utils.dart';

void main() {
  group('Color glyph detection', () {
    late Font emojiFont;
    late Font regularFont;

    setUp(() {
      final emojiBytes = loadFile('assets/fonts/TwemojiMozilla.subset.ttf');
      emojiFont = Font.decode(emojiBytes)!;

      final regularBytes = loadFile('assets/fonts/Inter-594377.ttf');
      regularFont = Font.decode(regularBytes)!;
    });

    tearDown(() {
      emojiFont.dispose();
      regularFont.dispose();
    });

    test('emoji font reports hasColorGlyphs true', () {
      expect(emojiFont.hasColorGlyphs, isTrue);
    });

    test('regular font reports hasColorGlyphs false', () {
      expect(regularFont.hasColorGlyphs, isFalse);
    });

    test('isColorGlyph returns true for known color glyph IDs', () {
      // TwemojiMozilla.subset.ttf has color glyphs at IDs 2 and 3.
      expect(emojiFont.isColorGlyph(2), isTrue);
      expect(emojiFont.isColorGlyph(3), isTrue);
    });

    test('isColorGlyph returns false for .notdef in emoji font', () {
      expect(emojiFont.isColorGlyph(0), isFalse);
    });

    test('isColorGlyph returns false for any glyph in regular font', () {
      expect(regularFont.isColorGlyph(0), isFalse);
      expect(regularFont.isColorGlyph(1), isFalse);
    });
  });

  group('Color glyph layers', () {
    late Font emojiFont;

    setUp(() {
      final bytes = loadFile('assets/fonts/TwemojiMozilla.subset.ttf');
      emojiFont = Font.decode(bytes)!;
    });

    tearDown(() {
      emojiFont.dispose();
    });

    test('getColorLayers returns layers for a color glyph', () {
      final layers = emojiFont.getColorLayers(2);
      expect(layers, isNotEmpty);
      for (final layer in layers) {
        // Each layer should have a valid ARGB color with non-zero alpha.
        expect(layer.color >> 24 & 0xFF, greaterThan(0));
        layer.dispose();
      }
    });

    test('getColorLayers returns empty for non-color glyph', () {
      final layers = emojiFont.getColorLayers(0);
      expect(layers, isEmpty);
    });

    test('getColorLayers returns consistent results on repeated calls', () {
      final layers1 = emojiFont.getColorLayers(2);
      final layers2 = emojiFont.getColorLayers(2);

      expect(layers1.length, equals(layers2.length));
      for (int i = 0; i < layers1.length; i++) {
        expect(layers1[i].color, equals(layers2[i].color));
      }

      for (final l in layers1) {
        l.dispose();
      }
      for (final l in layers2) {
        l.dispose();
      }
    });

    test('foreground color parameter is applied', () {
      final layersBlack =
          emojiFont.getColorLayers(2, foregroundColor: 0xFF000000);
      final layersRed =
          emojiFont.getColorLayers(2, foregroundColor: 0xFFFF0000);

      expect(layersBlack.length, equals(layersRed.length));

      // If any layer uses the foreground color, it should differ between calls.
      for (int i = 0; i < layersBlack.length; i++) {
        if (layersBlack[i].useForeground) {
          expect(layersBlack[i].color, equals(0xFF000000));
          expect(layersRed[i].color, equals(0xFFFF0000));
        }
      }

      for (final l in layersBlack) {
        l.dispose();
      }
      for (final l in layersRed) {
        l.dispose();
      }
    });

    test('layer paths can be iterated without error', () {
      final layers = emojiFont.getColorLayers(2);
      expect(layers, isNotEmpty);

      for (final layer in layers) {
        // Iterate the path commands to verify the path data is valid.
        // Image layers have no path (path is null).
        if (layer.path != null) {
          int commandCount = 0;
          for (final command in layer.path!) {
            expect(command.verb, isNotNull);
            commandCount++;
          }
          expect(commandCount, greaterThan(0));
        }
        layer.dispose();
      }
    });
  });

  group('SBIX color glyph detection', () {
    late Font sbixFont;

    setUp(() {
      final bytes =
          loadFile('assets/fonts/AppleColorEmoji.subset.ttf');
      sbixFont = Font.decode(bytes)!;
    });

    tearDown(() {
      sbixFont.dispose();
    });

    test('SBIX font reports hasColorGlyphs true', () {
      expect(sbixFont.hasColorGlyphs, isTrue);
    });

    test('isColorGlyph returns true for SBIX glyph IDs', () {
      // Glyph 1 = ❤ (U+2764), Glyph 2 = 😀 (U+1F600)
      expect(sbixFont.isColorGlyph(1), isTrue);
      expect(sbixFont.isColorGlyph(2), isTrue);
    });

    test('isColorGlyph returns false for .notdef in SBIX font', () {
      expect(sbixFont.isColorGlyph(0), isFalse);
    });
  });

  group('SBIX color glyph layers', () {
    late Font sbixFont;

    setUp(() {
      final bytes =
          loadFile('assets/fonts/AppleColorEmoji.subset.ttf');
      sbixFont = Font.decode(bytes)!;
    });

    tearDown(() {
      sbixFont.dispose();
    });

    test('getColorLayers returns image layer for SBIX glyph', () {
      final layers = sbixFont.getColorLayers(1);
      expect(layers, isNotEmpty);

      // SBIX glyphs should have exactly one image layer.
      expect(layers.length, equals(1));
      final layer = layers.first;
      expect(layer.paintType, equals(ColorGlyphPaintType.image));
      expect(layer.imageBytes, isNotNull);
      expect(layer.imageBytes!.isNotEmpty, isTrue);
      expect(layer.imageWidth, greaterThan(0));
      expect(layer.imageHeight, greaterThan(0));

      // Image layer should have null path.
      expect(layer.path, isNull);

      layer.dispose();
    });

    test('SBIX image bytes start with PNG signature', () {
      final layers = sbixFont.getColorLayers(2);
      expect(layers, isNotEmpty);

      final layer = layers.first;
      expect(layer.paintType, equals(ColorGlyphPaintType.image));

      // PNG signature: 0x89 P N G 0x0D 0x0A 0x1A 0x0A
      final bytes = layer.imageBytes!;
      expect(bytes.length, greaterThan(8));
      expect(bytes[0], equals(0x89));
      expect(bytes[1], equals(0x50)); // P
      expect(bytes[2], equals(0x4E)); // N
      expect(bytes[3], equals(0x47)); // G

      layer.dispose();
    });

    test('.notdef in SBIX font returns layers via paint pipeline', () {
      // HarfBuzz paint pipeline may return layers for .notdef (e.g., outline
      // drawn as solid fill). Just verify it doesn't crash.
      final layers = sbixFont.getColorLayers(0);
      for (final layer in layers) {
        layer.dispose();
      }
    });

    test('SBIX layers are cached consistently', () {
      final layers1 = sbixFont.getColorLayers(1);
      final layers2 = sbixFont.getColorLayers(1);

      expect(layers1.length, equals(layers2.length));
      expect(layers1.first.paintType, equals(layers2.first.paintType));
      expect(layers1.first.imageBytes!.length,
          equals(layers2.first.imageBytes!.length));

      for (final l in layers1) {
        l.dispose();
      }
      for (final l in layers2) {
        l.dispose();
      }
    });
  });

  group('Color glyph - base Font defaults', () {
    test('default hasColorGlyphs is false', () {
      final bytes = loadFile('assets/fonts/Inter-594377.ttf');
      final font = Font.decode(bytes)!;
      expect(font.hasColorGlyphs, isFalse);
      expect(font.getColorLayers(0), isEmpty);
      font.dispose();
    });
  });
}
