import 'dart:convert';

import 'package:flutter/foundation.dart';

class BinaryReader {
  final _utf8Decoder = const Utf8Decoder();
  // Tolerant decoder used only for console spans (readStringWithLength). The
  // console stream carries Luau-produced text and can desync on malformed
  // framing; decoding malformed bytes to U+FFFD keeps a bad span from crashing
  // the Dart VM instead of throwing a FormatException.
  final _utf8DecoderLossy = const Utf8Decoder(allowMalformed: true);
  final ByteData buffer;
  final Endian endian;

  /// TODO: remove setter for readIndex when we remove _readVarInt from
  /// core_double_type.dart
  int readIndex = 0;

  int get position => readIndex;

  int get size => buffer.lengthInBytes;

  BinaryReader(this.buffer, {this.endian = Endian.little});

  BinaryReader.fromList(Uint8List list, {this.endian = Endian.little})
      : buffer =
            ByteData.view(list.buffer, list.offsetInBytes, list.lengthInBytes);

  bool get isEOF => readIndex >= buffer.lengthInBytes;

  double readFloat32() {
    double value = buffer.getFloat32(readIndex, endian);
    readIndex += 4;
    return value;
  }

  double readFloat64() {
    double value = buffer.getFloat64(readIndex, endian);
    readIndex += 8;
    return value;
  }

  int readInt8() {
    int value = buffer.getInt8(readIndex);
    readIndex += 1;
    return value;
  }

  int readUint8() {
    int value = buffer.getUint8(readIndex);
    readIndex += 1;
    return value;
  }

  int readInt16() {
    int value = buffer.getInt16(readIndex, endian);
    readIndex += 2;
    return value;
  }

  int readUint16() {
    int value = buffer.getUint16(readIndex, endian);
    readIndex += 2;
    return value;
  }

  int readInt32() {
    int value = buffer.getInt32(readIndex, endian);
    readIndex += 4;
    return value;
  }

  int readUint32() {
    int value = buffer.getUint32(readIndex, endian);
    readIndex += 4;
    return value;
  }

  int readInt64() {
    int value = buffer.getInt64(readIndex, endian);
    readIndex += 8;
    return value;
  }

  int readUint64() {
    int value = buffer.getUint64(readIndex, endian);
    readIndex += 8;
    return value;
  }

  /// Read a variable length unsigned integer from the buffer encoded as an
  /// LEB128 unsigned integer.
  int readVarUint() {
    int result = 0;
    if (kIsWeb) {
      // Use a double multiplier instead of bit shifting to avoid 32-bit
      // overflow on web platforms. JavaScript bitwise operations truncate to
      // 32-bit signed integers, but floating-point multiplication works
      // correctly for integers up to 2^53.
      double multiplier = 1;
      while (true) {
        int byte = buffer.getUint8(readIndex++) & 0xff;
        result += ((byte & 0x7f) * multiplier).toInt();
        if ((byte & 0x80) == 0) break;
        multiplier *= 128; // 2^7
      }
    } else {
      int shift = 0;
      while (true) {
        int byte = buffer.getUint8(readIndex++) & 0xff;
        result |= (byte & 0x7f) << shift;
        if ((byte & 0x80) == 0) break;
        shift += 7;
      }
    }
    return result;
  }

  /// Read a string encoded into the stream. Strings are encoded with a varuint
  /// integer length written first followed by length number of utf8 encoded
  /// bytes.
  String readString({bool explicitLength = true}) {
    int length = explicitLength ? readVarUint() : buffer.lengthInBytes;
    if (length == 0) {
      return '';
    }
    late Uint8List bytes;
    if (kIsWeb) {
      // This is to workaround SharedArrayBuffer no longer working with methods
      // like Uint8List.view. Details here:
      // https://dart-review.googlesource.com/c/sdk/+/343940/12/sdk/lib/js_interop/js_interop.dart
      // and here https://github.com/dart-lang/sdk/issues/56455
      bytes = Uint8List(length);
      for (int index = 0; index < length; index++) {
        bytes[index] = buffer.getUint8(readIndex++);
      }
    } else {
      bytes = Uint8List.view(
          buffer.buffer, buffer.offsetInBytes + readIndex, length);
      readIndex += length;
    }
    return _utf8Decoder.convert(bytes);
  }

  /// Reads [length] bytes and decodes them as UTF-8, allowing malformed
  /// sequences (invalid bytes become U+FFFD) rather than throwing.
  ///
  /// Unlike [readString], this does NOT enforce strict UTF-8. It is intended
  /// for Luau console spans, where a framing desync can leave a byte range that
  /// isn't valid UTF-8; tolerating that keeps a bad span from crashing the VM.
  /// Do not use it for data where malformed bytes should signal corruption —
  /// prefer [readString] there.
  String readStringWithLength(int length) =>
      _utf8DecoderLossy.convert(read(length, false));

  Uint8List read(int length, [bool allocNew = true]) {
    if (kIsWeb) {
      final bytes = Uint8List(length);
      for (int index = 0; index < length; index++) {
        bytes[index] = buffer.getUint8(readIndex++);
      }
      return bytes; // always new
    } else {
      final bytes = Uint8List.view(
          buffer.buffer, buffer.offsetInBytes + readIndex, length);
      readIndex += length;
      return allocNew ? Uint8List.fromList(bytes) : bytes;
    }
  }
}
