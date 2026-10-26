import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rive_native/src/rive.dart' show RiveProfiler;

void main() {
  late RiveProfiler profiler;

  setUp(() {
    profiler = RiveProfiler.instance;
  });

  tearDown(() {
    // Ensure profiler is stopped after each test
    if (profiler.isActive) {
      profiler.stop();
    }
  });

  test('profiler start/stop lifecycle', () {
    // Should not be active initially
    expect(profiler.isActive, false);

    // Start profiling
    expect(profiler.start(), true);
    expect(profiler.isActive, true);

    // Cannot start twice
    expect(profiler.start(), false);

    // Stop profiling
    expect(profiler.stop(), true);
    expect(profiler.isActive, false);

    // Cannot stop twice
    expect(profiler.stop(), false);
  });

  test('profiler dump after stop returns valid binary data', () {
    // Start profiling
    expect(profiler.start(), true);

    // Stop profiling (data should be retained)
    expect(profiler.stop(), true);

    // Dump profile data after stopping
    final data = profiler.dump();
    expect(data, isNotNull);
    expect(data!.length, greaterThan(0));

    // Verify format
    final byteData = ByteData.sublistView(data);

    // Verify magic number (0x52505246 = "RPRF")
    expect(byteData.getUint32(0, Endian.little), 0x52505246);

    // Verify version is the RPRF format version emitted by the runtime.
    expect(byteData.getUint32(4, Endian.little), 2);
  });

  test('profiler dump clears buffer', () {
    // Start and stop profiling
    profiler.start();
    profiler.stop();

    // First dump gets all data
    final data1 = profiler.dump();
    expect(data1, isNotNull);
    expect(data1!.length, greaterThan(0));

    // Second dump returns null (buffer was cleared)
    final data2 = profiler.dump();
    expect(data2, isNull);
  });

  test('streaming mode: first dump has header, subsequent have frames only',
      () {
    profiler.start();

    // First dump - should have header (dump auto-flushes)
    final data1 = profiler.dump();
    expect(data1, isNotNull);

    final byteData1 = ByteData.sublistView(data1!);
    // First dump starts with magic number (header)
    expect(byteData1.getUint32(0, Endian.little), 0x52505246);

    // Second dump - frames only (no header)
    final data2 = profiler.dump();
    // May be null if no new frames, or non-null with frame data
    if (data2 != null && data2.isNotEmpty) {
      // Should NOT start with magic (no header)
      final byteData2 = ByteData.sublistView(data2);
      expect(byteData2.getUint8(0), anyOf(equals(0x01), equals(0x00)));
    }

    profiler.stop();
  });

  test('endFrame can be called when active and inactive', () {
    // Should not throw when profiling is inactive
    expect(profiler.isActive, false);
    profiler.endFrame(); // No-op when inactive

    // Should not throw when profiling is active
    profiler.start();
    expect(profiler.isActive, true);
    profiler.endFrame(); // Calls MicroProfileFlip()
    profiler.endFrame(); // Can be called multiple times

    profiler.stop();

    // Should not throw after stopping
    profiler.endFrame(); // No-op when inactive
  });
}
