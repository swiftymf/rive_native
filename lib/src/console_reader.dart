import 'package:rive_native/rive_luau.dart';
import 'package:rive_native/utilities.dart';

bool readConsoleEntries(BinaryReader reader, List<ConsoleEntry> entries) {
  bool added = false;
  while (!reader.isEOF) {
    final List<String> spans = [];
    final type = reader.readUint8();
    final scriptName = reader.readString();
    final lineNumber = reader.readVarUint();
    while (true) {
      final spanLength = reader.readVarUint();
      if (spanLength == 0) {
        break;
      }
      final spanText = reader.readStringWithLength(spanLength);
      spans.add(spanText);
    }
    entries.add(
      ConsoleEntry(
        type: ConsoleEntryType.values[type],
        scriptName: scriptName,
        lineNumber: lineNumber,
        spans: spans,
      ),
    );
    added = true;
  }
  return added;
}
