import 'package:rive_native/rive_text.dart';

// Anything less than ASCII 32 (space) we can consider to be an empty glyph.
// 0x2028 is a line separator without making a paragraph (like on web).
// https://stackoverflow.com/questions/3072152/what-is-unicode-character-2028-ls-line-separator-used-for
// 0x200B is a Zero width space.
bool isWhiteSpace(int c) {
  return c <= 32 || c == 0x2028 || c == 0x200B;
}

/// Stores the glyph index representing the code unit at index i.
///
/// Indices are in UTF-16 code unit space. When the source text contains
/// non-BMP characters (emoji), codepoint indices from shaping are converted
/// to UTF-16 indices during construction. The [toUtf16] method performs the
/// same codepoint-to-UTF-16 conversion for external callers.
class GlyphLookup {
  final List<int> indices;

  /// Mapping from codepoint index to UTF-16 code unit index.
  /// Null when all characters are BMP (1:1 mapping).
  final List<int>? _cpToUtf16;

  GlyphLookup(this.indices, [this._cpToUtf16]);

  /// Build a GlyphLookup from shaped text.
  ///
  /// [codeUnitCount] is the number of indices in the target index space.
  /// When [text] is provided, textIndices from shaping (which are codepoint
  /// indices) are mapped to UTF-16 code unit indices, so the resulting
  /// GlyphLookup works in UTF-16 space. When [text] is null, textIndices are
  /// used as-is (suitable for callers already in codepoint space).
  factory GlyphLookup.fromShape(
    TextShapeResult shape,
    int codeUnitCount, {
    String? text,
  }) {
    // Build codepoint index -> UTF-16 code unit index mapping when text has
    // non-BMP characters (surrogate pairs).
    List<int>? cpToUtf16;
    if (text != null && text.runes.length != text.length) {
      cpToUtf16 = List<int>.filled(text.runes.length + 1, text.length);
      int utf16Index = 0;
      int cpIndex = 0;
      for (final rune in text.runes) {
        cpToUtf16[cpIndex++] = utf16Index;
        utf16Index += rune > 0xFFFF ? 2 : 1;
      }
      cpToUtf16[cpIndex] = utf16Index;
    }

    var glyphIndices = List<int>.filled(codeUnitCount + 1, 0);
    // Build a mapping of code units to glyph indices.
    int glyphIndex = 0;
    int lastTextIndex = 0;
    for (final paragraph in shape.paragraphs) {
      for (final run in paragraph.runs) {
        for (int i = 0; i < run.glyphCount; i++) {
          var textIndex = run.textIndexAt(i);
          // Convert codepoint index to UTF-16 code unit index if needed.
          if (cpToUtf16 != null) {
            textIndex = textIndex < cpToUtf16.length
                ? cpToUtf16[textIndex]
                : codeUnitCount;
          }
          for (int j = lastTextIndex; j < textIndex; j++) {
            glyphIndices[j] = glyphIndex - 1;
          }
          lastTextIndex = textIndex;
          glyphIndex++;
        }
      }
    }
    for (int i = lastTextIndex; i < codeUnitCount; i++) {
      glyphIndices[i] = glyphIndex - 1;
    }
    // Store a fake unreachable glyph at the end to allow selecting the last
    // one.
    glyphIndices[codeUnitCount] =
        codeUnitCount == 0 ? 0 : glyphIndices[codeUnitCount - 1] + 1;
    return GlyphLookup(glyphIndices, cpToUtf16);
  }

  /// Convert a codepoint index (from [TextRun.textIndexAt]) to a UTF-16
  /// code unit index. Returns the index unchanged when all characters are BMP.
  int toUtf16(int codePointIndex) {
    if (_cpToUtf16 == null) return codePointIndex;
    return codePointIndex < _cpToUtf16.length
        ? _cpToUtf16[codePointIndex]
        : indices.length - 1;
  }

  /// How far this code unit index is within the glyph.
  double advanceFactor(int index, bool inv) {
    if (index >= indices.length) {
      return 0;
    }
    var glyphIndex = indices[index];
    int start = index;
    while (start > 0) {
      if (indices[start - 1] != glyphIndex) {
        break;
      }
      start--;
    }
    int end = index;
    while (end < indices.length - 1) {
      if (indices[end + 1] != glyphIndex) {
        break;
      }
      end++;
    }

    var f = (index - start) / (end - start + 1);
    if (inv) {
      return 1.0 - f;
    }
    return f;
  }

  int count(int index) {
    var value = indices[index];
    int count = 1;
    // ignore: parameter_assignments
    while (++index < indices.length && indices[index] == value) {
      count++;
    }
    return count;
  }

  /// Returns the first codeunit index of the glyph cluster containing [index].
  int glyphStart(int index) {
    if (index <= 0 || index >= indices.length) {
      return index;
    }
    var value = indices[index];
    while (index > 0 && indices[index - 1] == value) {
      index--;
    }
    return index;
  }

  /// Whether [index] is at the start of a glyph cluster boundary (i.e. not in
  /// the middle of a multi-codepoint glyph).
  bool isGlyphBoundary(int index) {
    if (index <= 0 || index >= indices.length) {
      return true;
    }
    return indices[index] != indices[index - 1];
  }
}
