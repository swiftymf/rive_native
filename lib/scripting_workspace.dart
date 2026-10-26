import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';
import 'dart:ui' show Color;

import 'package:meta/meta.dart';
import 'package:rive_native/rive_native.dart' show RenderTexture;
import 'package:rive_native/src/utilities/utilities.dart';

import 'package:rive_native/src/ffi/scripting_workspace_ffi.dart'
    if (dart.library.js_interop) 'package:rive_native/src/web/scripting_workspace_web.dart';
import 'package:rive_native/utilities.dart';

/// An error thrown when attempting to use a [ScriptingWorkspace] that has
/// been closed or is in the process of closing.
class ScriptingWorkspaceClosedError extends StateError {
  ScriptingWorkspaceClosedError()
    : super('Cannot request work on a closed ScriptingWorkspace');
}

enum HighlightScope {
  none,
  keyword,
  type,
  literal,
  number,
  operator,
  punctuation,
  property,
  string,
  comment,
  boolean,
  nil,
  interpString,
  function,
}

class HighlightScopeStyle {
  final Color color;
  final double? weight;

  const HighlightScopeStyle(this.color, {this.weight});
}

class FormatOp {
  final ScriptPosition position;
  FormatOp({required this.position});
}

class FormatOpInsert extends FormatOp {
  final String text;

  FormatOpInsert({required super.position, required this.text});
}

class FormatOpErase extends FormatOp {
  final ScriptPosition positionEnd;

  FormatOpErase({required super.position, required this.positionEnd});
}

class FormatResult {
  final List<FormatOp> operations;

  FormatResult({required this.operations});

  static final empty = FormatResult(operations: const []);

  static FormatResult read(BinaryReader reader) {
    final List<FormatOp> operations = [];
    while (!reader.isEOF) {
      switch (reader.readUint8()) {
        case 1:
          final line = reader.readVarUint();
          final column = reader.readVarUint();
          final text = reader.readString();
          operations.add(
            FormatOpInsert(
              position: ScriptPosition(line: line, column: column),
              text: text,
            ),
          );
          break;
        case 0:
          final lineFrom = reader.readVarUint();
          final columnFrom = reader.readVarUint();
          final lineTo = reader.readVarUint();
          final columnTo = reader.readVarUint();
          operations.add(
            FormatOpErase(
              position: ScriptPosition(line: lineFrom, column: columnFrom),
              positionEnd: ScriptPosition(line: lineTo, column: columnTo),
            ),
          );
          break;
      }
    }
    return FormatResult(operations: operations);
  }
}

class ScriptPosition implements Comparable<ScriptPosition> {
  final int line;
  final int column;

  const ScriptPosition({required this.line, required this.column});
  static ScriptPosition read(BinaryReader reader) {
    var line = reader.readVarUint();
    var column = reader.readVarUint();
    return ScriptPosition(line: line, column: column);
  }

  @override
  int get hashCode => szudzik(line, column);

  @override
  bool operator ==(Object other) =>
      other is ScriptPosition && other.line == line && other.column == column;

  @override
  String toString() => '${line + 1}:${column + 1}';

  @override
  int compareTo(ScriptPosition other) {
    if (line < other.line) {
      return -1;
    }
    if (line > other.line) {
      return 1;
    }
    if (column < other.column) {
      return -1;
    }
    if (column > other.column) {
      return 1;
    }
    return 0;
  }
}

class ScriptRange {
  final ScriptPosition begin;
  final ScriptPosition end;

  const ScriptRange({required this.begin, required this.end});
  static ScriptRange read(BinaryReader reader) {
    final begin = ScriptPosition.read(reader);
    final end = ScriptPosition.read(reader);

    return ScriptRange(begin: begin, end: end);
  }

  bool get isCollapsed => begin == end;

  @override
  String toString() => '$begin -> $end';

  @override
  int get hashCode =>
      Object.hash(begin.line, begin.column, end.line, end.column);

  @override
  bool operator ==(Object other) =>
      other is ScriptRange && other.begin == begin && other.end == end;
}

enum ScriptProblemType {
  unknown,

  linterUnknownGlobal,
  linterDeprecatedGlobal,
  linterGlobalUsedAsLocal,
  linterLocalShadow,
  linterSameLineStatement,
  linterMultiLineStatement,
  linterLocalUnused,
  linterFunctionUnused,
  linterImportUnused,
  linterBuiltinGlobalWrite,
  linterPlaceholderRead,
  linterUnreachableCode,
  linterUnknownType,
  linterForRange,
  linterUnbalancedAssignment,
  linterImplicitReturn,
  linterDuplicateLocal,
  linterFormatString,
  linterTableLiteral,
  linterUninitializedLocal,
  linterDuplicateFunction,
  linterDeprecatedApi,
  linterTableOperations,
  linterDuplicateCondition,
  linterMisleadingAndOr,
  linterCommentDirective,
  linterIntegerParsing,
  linterComparisonPrecedence,

  typeError,
  syntaxError,

  wgslParseError,
  wgslValidationError,

  requireQualification,
}

class ScriptProblemResult {
  final String scriptName;
  final List<ScriptProblem> errors;
  final List<ScriptProblem> lintErrors;
  final List<ScriptProblem> lintWarnings;

  ScriptProblemResult({
    required this.scriptName,
    required this.errors,
    required this.lintErrors,
    required this.lintWarnings,
  });

  static final empty = ScriptProblemResult(
    scriptName: '',
    errors: const [],
    lintErrors: const [],
    lintWarnings: const [],
  );

  bool get isEmpty =>
      errors.isEmpty && lintErrors.isEmpty && lintWarnings.isEmpty;

  static ScriptProblemResult read(BinaryReader reader) {
    final scriptName = reader.readString();
    final errorCount = reader.readVarUint();
    final lintErrorCount = reader.readVarUint();
    final lintWarningCount = reader.readVarUint();

    var errors = <ScriptProblem>[];
    for (int i = 0; i < errorCount; i++) {
      errors.add(ScriptProblem.read(reader));
    }

    var lintErrors = <ScriptProblem>[];
    for (int i = 0; i < lintErrorCount; i++) {
      lintErrors.add(ScriptProblem.read(reader));
    }

    var lintWarnings = <ScriptProblem>[];
    for (int i = 0; i < lintWarningCount; i++) {
      lintWarnings.add(ScriptProblem.read(reader));
    }

    return ScriptProblemResult(
      scriptName: scriptName,
      errors: errors,
      lintErrors: lintErrors,
      lintWarnings: lintWarnings,
    );
  }
}

class ScriptProblem {
  final ScriptRange range;
  final String message;
  final ScriptProblemType type;

  ScriptProblem({
    required this.range,
    required this.message,
    required this.type,
  });

  @override
  String toString() => 'ScriptProblem($type:$range) - $message';

  @override
  int get hashCode => Object.hash(range, message, type);

  @override
  bool operator ==(Object other) =>
      other is ScriptProblem &&
      other.type == type &&
      other.range == range &&
      other.message == message;

  static ScriptProblem read(BinaryReader reader) {
    return ScriptProblem(
      type: ScriptProblemType.values[reader.readUint8()],
      range: ScriptRange.read(reader),
      message: reader.readString(),
    );
  }
}

class AutocompleteResult {
  final List<AutocompleteEntry> entries;

  AutocompleteResult({required this.entries});

  static final empty = AutocompleteResult(entries: const []);

  static AutocompleteResult read(BinaryReader reader) {
    final entries = <AutocompleteEntry>[];
    while (!reader.isEOF) {
      entries.add(AutocompleteEntry.read(reader));
    }
    return AutocompleteResult(entries: entries);
  }
}

class AutocompleteEntry {
  final ScriptRange range;
  final String text;
  final Uint32List matchedIndices;
  AutocompleteEntry({
    required this.range,
    required this.text,
    required this.matchedIndices,
  });

  static AutocompleteEntry read(BinaryReader reader) {
    final range = ScriptRange.read(reader);
    final text = reader.readString();
    final matchedIndices = Uint32List(reader.readVarUint());
    for (int i = 0; i < matchedIndices.length; i++) {
      matchedIndices[i] = reader.readVarUint();
    }
    return AutocompleteEntry(
      range: range,
      text: text,
      matchedIndices: matchedIndices,
    );
  }
}

class DefinitionResult {
  final bool found;
  final String moduleName;
  final ScriptRange definitionRange;
  final ScriptRange tokenRange;
  final String preview;
  final String documentationSymbol;
  final String documentation;

  DefinitionResult({
    required this.found,
    required this.moduleName,
    required this.definitionRange,
    required this.tokenRange,
    required this.preview,
    required this.documentationSymbol,
    required this.documentation,
  });

  static final notFound = DefinitionResult(
    found: false,
    moduleName: '',
    definitionRange: const ScriptRange(
      begin: ScriptPosition(line: 0, column: 0),
      end: ScriptPosition(line: 0, column: 0),
    ),
    tokenRange: const ScriptRange(
      begin: ScriptPosition(line: 0, column: 0),
      end: ScriptPosition(line: 0, column: 0),
    ),
    preview: '',
    documentationSymbol: '',
    documentation: '',
  );

  static DefinitionResult read(BinaryReader reader) {
    final found = reader.readUint8() != 0;
    if (!found) {
      return notFound;
    }

    final moduleName = reader.readString();
    final beginLine = reader.readVarUint();
    final beginColumn = reader.readVarUint();
    final endLine = reader.readVarUint();
    final endColumn = reader.readVarUint();
    final tokenBeginLine = reader.readVarUint();
    final tokenBeginColumn = reader.readVarUint();
    final tokenEndLine = reader.readVarUint();
    final tokenEndColumn = reader.readVarUint();
    final preview = reader.readString();
    final documentationSymbol = reader.readString();
    final documentation = reader.readString();

    return DefinitionResult(
      found: true,
      moduleName: moduleName,
      definitionRange: ScriptRange(
        begin: ScriptPosition(line: beginLine, column: beginColumn),
        end: ScriptPosition(line: endLine, column: endColumn),
      ),
      tokenRange: ScriptRange(
        begin: ScriptPosition(line: tokenBeginLine, column: tokenBeginColumn),
        end: ScriptPosition(line: tokenEndLine, column: tokenEndColumn),
      ),
      preview: preview,
      documentationSymbol: documentationSymbol,
      documentation: documentation,
    );
  }
}

enum HighlightResultType { unknown, computed }

enum HighlightDiffChangeType {
  removed, // Line exists only in source (removed in destination)
  added, // Line exists only in destination (added in destination)
}

class HighlightDiffEntry {
  final HighlightDiffChangeType changeType;
  final int lineIndex;
  final int lineCount;

  /// For removed entries: the line in the destination where this removed
  /// content should be displayed. For added entries: same as lineIndex.
  final int destLineIndex;

  HighlightDiffEntry({
    required this.changeType,
    required this.lineIndex,
    required this.lineCount,
    required this.destLineIndex,
  });
}

class HighlightResult {
  final HighlightResultType type;
  final List<HighlightDiffEntry> diffs;

  const HighlightResult(this.type, {this.diffs = const []});

  static const HighlightResult unknown = HighlightResult(
    HighlightResultType.unknown,
  );
  static const HighlightResult computed = HighlightResult(
    HighlightResultType.computed,
  );

  static HighlightResult read(BinaryReader reader) {
    if (reader.isEOF) {
      return HighlightResult(HighlightResultType.unknown);
    }
    final diffs = <HighlightDiffEntry>[];
    final diffCount = reader.readVarUint();
    for (int i = 0; i < diffCount; i++) {
      final changeTypeValue = reader.readUint8();
      final changeType = changeTypeValue < HighlightDiffChangeType.values.length
          ? HighlightDiffChangeType.values[changeTypeValue]
          : HighlightDiffChangeType.removed;
      final lineIndex = reader.readVarUint();
      final lineCount = reader.readVarUint();
      // destLineIndex is only serialized for removed entries
      final destLineIndex = changeType == HighlightDiffChangeType.removed
          ? reader.readVarUint()
          : lineIndex;
      diffs.add(
        HighlightDiffEntry(
          changeType: changeType,
          lineIndex: lineIndex,
          lineCount: lineCount,
          destLineIndex: destLineIndex,
        ),
      );
    }
    return HighlightResult(HighlightResultType.computed, diffs: diffs);
  }
}

enum InsertionCompletion { none, end, doEnd, until, thenEnd }

enum PropertyType { number, string, boolean, color, trigger, artboard, other }

class ImplementedTypeProperty {
  final PropertyType type;
  final String name;

  /// Only applies when [type] == [PropertyType.other] or [type] ==
  /// [PropertyType.artboard] and the typeName is the viewmodel bound to the
  /// artboard.
  final String typeName;

  ImplementedTypeProperty({
    required this.type,
    required this.typeName,
    required this.name,
  });

  static ImplementedTypeProperty? read(BinaryReader reader) {
    if (reader.isEOF) {
      return null;
    }
    final typeValue = reader.readUint8();
    if (reader.isEOF) {
      return null;
    }
    final typeName = reader.readString();
    if (reader.isEOF) {
      return null;
    }
    final name = reader.readString();

    if (typeValue >= PropertyType.values.length) {
      return null;
    }
    return ImplementedTypeProperty(
      type: PropertyType.values[typeValue],
      typeName: typeName,
      name: name,
    );
  }
}

class ImplementedType {
  final String scriptName;
  final String interfaceTypeName;
  final List<ImplementedTypeProperty> inputs;
  final List<ImplementedTypeProperty> outputs;
  final List<String> userTypeNames;

  /// Direct dependencies (requires) for this module.
  final List<String> dependencies;

  /// Optional script methods (init/draw/drawCanvas/advance/...) present on the
  /// generator's returned table, detected by the workspace executing the
  /// generator and probing the returned table. Empty if the generator could
  /// not be executed.
  final List<String> implementedMethods;
  ImplementedType({
    required this.scriptName,
    required this.interfaceTypeName,
    required this.inputs,
    required this.outputs,
    required this.userTypeNames,
    required this.dependencies,
    required this.implementedMethods,
  });

  static ImplementedType? read(BinaryReader reader) {
    if (reader.isEOF) {
      return null;
    }
    final scriptName = reader.readString();
    if (reader.isEOF) {
      return null;
    }
    final interfaceName = reader.readString();
    if (reader.isEOF) {
      return null;
    }

    final userTypesNames = <String>[];
    final userTypesCount = reader.readVarUint();
    for (int i = 0; i < userTypesCount; i++) {
      final userTypeName = reader.readString();
      userTypesNames.add(userTypeName);
    }

    if (reader.isEOF) {
      return null;
    }

    final inputCount = reader.readVarUint();
    final inputs = <ImplementedTypeProperty>[];
    for (int i = 0; i < inputCount; i++) {
      final argument = ImplementedTypeProperty.read(reader);
      if (argument == null) {
        return null;
      }
      inputs.add(argument);
    }

    final outputCount = reader.readVarUint();
    final outputs = <ImplementedTypeProperty>[];
    for (int i = 0; i < outputCount; i++) {
      final argument = ImplementedTypeProperty.read(reader);
      if (argument == null) {
        return null;
      }
      outputs.add(argument);
    }

    // Read direct dependencies (requireSet)
    final dependencies = <String>[];
    if (!reader.isEOF) {
      final dependencyCount = reader.readVarUint();
      for (int i = 0; i < dependencyCount; i++) {
        dependencies.add(reader.readString());
      }
    }

    // Read execution-detected implemented method names (appended last for
    // backward-compatibility with older payloads that end at dependencies).
    final implementedMethods = <String>[];
    if (!reader.isEOF) {
      final methodCount = reader.readVarUint();
      for (int i = 0; i < methodCount; i++) {
        implementedMethods.add(reader.readString());
      }
    }

    return ImplementedType(
      scriptName: scriptName,
      interfaceTypeName: interfaceName,
      inputs: inputs,
      outputs: outputs,
      userTypeNames: userTypesNames,
      dependencies: dependencies,
      implementedMethods: implementedMethods,
    );
  }
}

abstract class ScriptingWorkspaceResponseResult {
  bool get available;
  BinaryReader? get reader;
}

class CompiledModule {
  final String name;
  final Uint8List bytecode;
  CompiledModule({required this.bytecode, required this.name});
}

/// A per-source shader-bake failure reported by [ScriptingWorkspace.compileAndSign]
/// (e.g. a shader that requested an HLSL variant but failed to compile it). When
/// present, the corresponding shader was NOT embedded for that backend.
class ShaderCompileError {
  /// The shader source (script) name the failure is for.
  final String scriptName;

  /// Human-readable reason the shader variant was not produced.
  final String message;

  ShaderCompileError({required this.scriptName, required this.message});

  @override
  String toString() => '$scriptName: $message';
}

class CompileAndSignResult {
  final List<CompiledModule> modules;
  final Uint8List signature;

  /// Non-fatal shader-bake failures. Empty on success. A non-empty list means
  /// one or more shaders were exported missing a requested backend variant.
  final List<ShaderCompileError> shaderErrors;

  CompileAndSignResult({
    required this.modules,
    required this.signature,
    this.shaderErrors = const [],
  });

  static CompileAndSignResult? read(BinaryReader reader) {
    final moduleCount = reader.readVarUint();

    final modules = <CompiledModule>[];
    for (int i = 0; i < moduleCount; i++) {
      final name = reader.readString();
      final length = reader.readVarUint();
      final bytecode = reader.read(length);
      modules.add(CompiledModule(bytecode: bytecode, name: name));
    }

    final signatureLength = reader.readVarUint();
    Uint8List signature = reader.read(signatureLength);

    // Trailing shader-error section (written after the signature). Absent in
    // older responses, in which case the reader is already at EOF.
    final shaderErrors = <ShaderCompileError>[];
    if (!reader.isEOF) {
      final errorCount = reader.readVarUint();
      for (int i = 0; i < errorCount; i++) {
        final scriptName = reader.readString();
        final message = reader.readString();
        shaderErrors
            .add(ShaderCompileError(scriptName: scriptName, message: message));
      }
    }

    return CompileAndSignResult(
      modules: modules,
      signature: signature,
      shaderErrors: shaderErrors,
    );
  }
}

class FindInFilesMatch {
  final int line;
  final String beforeMatch;
  final String matchText;
  final String afterMatch;

  FindInFilesMatch({
    required this.line,
    required this.beforeMatch,
    required this.matchText,
    required this.afterMatch,
  });
}

class ScriptFindResults {
  final String scriptId;
  final List<FindInFilesMatch> matches;

  ScriptFindResults({required this.scriptId, required this.matches});
}

class FindInFilesResult {
  final List<ScriptFindResults> results;

  FindInFilesResult({required this.results});

  static final empty = FindInFilesResult(results: const []);

  static FindInFilesResult? read(BinaryReader reader) {
    final scriptCount = reader.readVarUint();
    final results = <ScriptFindResults>[];

    for (int i = 0; i < scriptCount; i++) {
      final scriptId = reader.readString();
      final matchCount = reader.readVarUint();
      final matches = <FindInFilesMatch>[];

      for (int j = 0; j < matchCount; j++) {
        final line = reader.readVarUint();
        final beforeMatch = reader.readString();
        final matchText = reader.readString();
        final afterMatch = reader.readString();
        matches.add(
          FindInFilesMatch(
            line: line,
            beforeMatch: beforeMatch,
            matchText: matchText,
            afterMatch: afterMatch,
          ),
        );
      }

      results.add(ScriptFindResults(scriptId: scriptId, matches: matches));
    }

    return FindInFilesResult(results: results);
  }
}

class RegisteredModule {
  final String scriptId;
  final String moduleName;
  final bool isUtility;
  final int generatorRef;
  final String error;
  final List<String> dependencies;

  RegisteredModule({
    required this.scriptId,
    required this.moduleName,
    required this.isUtility,
    required this.generatorRef,
    required this.error,
    required this.dependencies,
  });

  bool get hasError => error.isNotEmpty;
}

class VMResult {
  /// Pointer to ScriptingVM* (owns both lua_State and context)
  final int vmPointer;

  /// Deprecated: Context is now owned by VM, this is always 0
  @Deprecated('Context is now owned by VM, use vmPointer instead')
  int get contextPointer => 0;

  final List<RegisteredModule> modules;

  /// Total time spent compiling scripts (in microseconds)
  final int compileTimeUs;

  /// Total time spent loading scripts into the VM (in microseconds)
  final int loadTimeUs;

  /// Total time spent executing scripts (in microseconds)
  final int executeTimeUs;

  /// Total time spent compiling WGSL shaders via naga (in microseconds)
  final int wgslCompileTimeUs;

  /// Console output from script execution (buffered during requestVM)
  final Uint8List consoleData;

  VMResult({
    required this.vmPointer,
    required this.modules,
    required this.compileTimeUs,
    required this.loadTimeUs,
    required this.executeTimeUs,
    required this.wgslCompileTimeUs,
    required this.consoleData,
  });

  static VMResult? read(BinaryReader reader) {
    if (reader.isEOF) {
      return null;
    }
    final vmPointer = reader.readVarUint();
    final moduleCount = reader.readVarUint();
    final modules = <RegisteredModule>[];
    for (int i = 0; i < moduleCount; i++) {
      final scriptId = reader.readString();
      final moduleName = reader.readString();
      final isUtility = reader.readUint8() != 0;
      final generatorRef = reader.readVarUint();
      final error = reader.readString();
      // Read dependencies
      final depCount = reader.readVarUint();
      final dependencies = <String>[];
      for (int j = 0; j < depCount; j++) {
        dependencies.add(reader.readString());
      }
      modules.add(
        RegisteredModule(
          scriptId: scriptId,
          moduleName: moduleName,
          isUtility: isUtility,
          generatorRef: generatorRef,
          error: error,
          dependencies: dependencies,
        ),
      );
    }

    // Read timing data (in microseconds)
    final compileTimeUs = reader.isEOF ? 0 : reader.readVarUint();
    final loadTimeUs = reader.isEOF ? 0 : reader.readVarUint();
    final executeTimeUs = reader.isEOF ? 0 : reader.readVarUint();
    final wgslCompileTimeUs = reader.isEOF ? 0 : reader.readVarUint();

    // Read console data from script execution
    Uint8List consoleData = Uint8List(0);
    if (!reader.isEOF) {
      final consoleSize = reader.readVarUint();
      if (consoleSize > 0) {
        consoleData = reader.read(consoleSize);
      }
    }

    return VMResult(
      vmPointer: vmPointer,
      modules: modules,
      compileTimeUs: compileTimeUs,
      loadTimeUs: loadTimeUs,
      executeTimeUs: executeTimeUs,
      wgslCompileTimeUs: wgslCompileTimeUs,
      consoleData: consoleData,
    );
  }
}

class CompileResult {
  final Uint8List bytecode;
  final Iterable<CompiledModule> dependencies;
  final Iterable<String> dependents;

  CompileResult({
    required this.bytecode,
    this.dependencies = const Iterable.empty(),
    this.dependents = const Iterable.empty(),
  });

  static CompileResult? read(BinaryReader reader) {
    if (reader.isEOF) {
      return null;
    }
    final length = reader.readVarUint();
    final bytecode = reader.read(length);
    if (reader.isEOF) {
      return CompileResult(bytecode: bytecode);
    }
    final dependencies = <CompiledModule>[];
    final count = reader.readVarUint();
    for (int i = 0; i < count; i++) {
      final name = reader.readString();
      final length = reader.readVarUint();
      final bytecode = reader.read(length);
      dependencies.add(CompiledModule(bytecode: bytecode, name: name));
    }
    final dependents = <String>[];
    while (!reader.isEOF) {
      dependents.add(reader.readString());
    }
    return CompileResult(
      bytecode: bytecode,
      dependencies: dependencies,
      dependents: dependents,
    );
  }
}

enum OptimizationLevel {
  /// no optimization
  none,

  /// baseline optimization level that doesn't prevent debuggability
  medium,

  /// includes optimizations that harm debuggability such as inlining
  max,
}

enum DebugLevel {
  /// no debugging support
  none,

  /// line info & function names only; sufficient for backtraces
  medium,

  /// full debug info with local & upvalue names; necessary for debugger
  max,
}

/// A workspace represents a collection of files that are likely related
/// (usually part of a single Rive file).
abstract class ScriptingWorkspace {
  Future<HighlightResult> setSystemGeneratedSource(
    String scriptName,
    String prefix,
    String source,
  );

  /// Set the [source] code for the script with [scriptId]. [libraryId] and
  /// [libraryVersionId] scope it to a library version, zero scope is the
  /// host file.
  Future<HighlightResult> setScriptSource(
    String scriptId,
    String scriptName,
    String source, {
    bool highlight = false,
    int libraryId = 0,
    int libraryVersionId = 0,
  });

  /// Scope for [scriptId] without a source push. Proxies stamp before their
  /// text hydrates, an empty source push would register a dead scoped module.
  void setScriptScope(String scriptId, int libraryId, int libraryVersionId);

  /// One import edge: the caller scope pins [name] to a target library
  /// version. Root caller is (0,0). Labels live on edges, so `lib:` requires
  /// resolve per caller.
  void setLibraryImport(
    int callerLibraryId,
    int callerLibraryVersionId,
    String name,
    int targetLibraryId,
    int targetLibraryVersionId,
  );

  /// Remove the import edge for [name] from the caller scope.
  void removeLibraryImport(
    int callerLibraryId,
    int callerLibraryVersionId,
    String name,
  );

  /// Canonical mangle prefix for a library version, e.g. draco@3. Compiled
  /// requires and exported wire names both derive from it, so the editor
  /// pushes one map for both.
  void setLibraryCanonicalName(
    int libraryId,
    int libraryVersionId,
    String canonicalName,
  );

  /// The statically linked source for [scriptId]: every constant require
  /// resolved to its registered name. Export flows compile elsewhere without
  /// this workspace's import state, so they send this instead of raw source.
  Future<String> rewriteRequires(String scriptId);

  /// Set a WGSL shader source. Same as [setScriptSource] but marks the script
  /// as WGSL so the workspace uses naga for validation/highlighting/formatting
  /// instead of Luau.
  Future<HighlightResult> setWGSLScriptSource(
    String scriptId,
    String scriptName,
    String source, {
    bool highlight = false,
  });

  /// Set the diff source for a module with [scriptId]. We store the diff source
  /// on the Script so subsequent calls to setScriptSource can return line
  /// level diffs with stored source when requesting highlighting data.
  ///
  /// **Important:** [setScriptSource] must be called first to create the script
  /// before calling this method. The script must exist in the workspace before
  /// a diff source can be set for it.
  Future<HighlightResult> setScriptDiffSource(String scriptId, String source);

  /// Clear the diff source for a module with [scriptId].
  void clearScriptDiffSource(String scriptId);

  void checkScriptsWithRequires();
  void removeScriptSource(String scriptId);

  /// Formats module named [scriptName].
  Future<FormatResult> format(String scriptName);

  /// Retrieves the bytecode for module named [scriptName].
  Future<CompileResult?> compile(
    String scriptName, {
    bool failOnErrors = false,
    bool compileDependencies = false,
    OptimizationLevel optimizationLevel = OptimizationLevel.medium,
    DebugLevel debugLevel = DebugLevel.medium,
  });

  /// Retrieves the bytecode for listed modules and signature.
  Future<CompileAndSignResult?> compileAndSign(
    Iterable<String> scriptNames,
    Uint8List privateKey, {
    bool failOnErrors = false,
    OptimizationLevel optimizationLevel = OptimizationLevel.medium,
    DebugLevel debugLevel = DebugLevel.medium,
    int shaderOutputFlags = 0,
  });

  /// Searches for [query] in files. If [inclusionSet] is provided, only those
  /// files are searched, otherwise all non-built-in files are searched.
  Future<FindInFilesResult> findInFiles(
    Iterable<String>? inclusionSet,
    String query, {
    bool caseSensitive = false,
    bool matchWholeWord = false,
    bool regularExpression = false,
    bool trim = true,
  });

  /// Retrieves the implemented type for module named [scriptName].
  Future<ImplementedType?> implementedType(String scriptName);

  /// Get the highlight data for a single row of [scriptName].
  Uint32List rowHighlight(String scriptName, int row);

  /// Get an error report for all the script files in this workspace.
  Future<List<ScriptProblemResult>> fullProblemReport();

  /// Get an error report for a script file with identified by [scriptName].
  Future<ScriptProblemResult> problemReport(String scriptName);

  /// Get possible autocompletion results at [position] in script with name
  /// [scriptName]. Uses the Luau frontend \u2014 see [autocompleteWGSL] for
  /// WGSL-backed assets.
  Future<AutocompleteResult> autocomplete(
    String scriptName,
    ScriptPosition position,
  );

  /// Get possible autocompletion results at [position] in a WGSL source with
  /// name [scriptName]. Uses the naga-backed WGSL frontend.
  Future<AutocompleteResult> autocompleteWGSL(
    String scriptName,
    ScriptPosition position,
  );

  /// Get definition information at [position] in script with name [scriptName].
  Future<DefinitionResult> getDefinition(
    String scriptName,
    ScriptPosition position,
  );

  /// Dispose of the workspace, any further calls will not work.
  @mustCallSuper
  void dispose() {
    _closing = true;
    _completers.clear();
  }

  /// Get extra text insertion to be auto-completed at the given position.
  Future<InsertionCompletion> completeInsertion(
    String scriptName,
    ScriptPosition position,
  );

  /// Get a specific line from the diff source for a module with [scriptId].
  /// Returns the line content when ready, or empty string if the line doesn't
  /// exist or no diff source is available.
  Future<String> getDiffSourceLine(String scriptId, int line);

  /// Check if a script needs to be recompiled (source changed since last
  /// compile). Returns true if the script has never been compiled or if the
  /// source has changed.
  Future<bool> checkNeedsRecompile(String scriptId);

  /// Sets the ore::Context pointer on the workspace so that VMs created via
  /// [requestVM] have access to GPU scripting. Call once after GPU init.
  void setOreContext(int oreContextPointer);

  /// Sets the gpu::RenderContext pointer on the workspace so that VMs created
  /// via [requestVM] can allocate RenderCanvas objects. Call once after GPU
  /// init, alongside [setOreContext].
  void setRenderContext(int renderContextPointer);

  /// Request a fresh VM with all scripts compiled and registered in
  /// dependency order. Returns a [VMResult] with the VM pointer and
  /// registered module list.
  Future<VMResult?> requestVM({int factoryPointer = 0});

  static ScriptingWorkspace make({bool canvasEnabled = false}) =>
      makeScriptingWorkspace(canvasEnabled: canvasEnabled);

  /// Initialises GPU scripting for the current platform. Call once after the
  /// native renderer is set up (i.e. after [RiveNative.init] completes).
  /// Returns the ore::Context pointer address, or 0 on unsupported platforms.
  /// Pass the result to [setOreContext] on every workspace you create.
  static int initGPUScripting() => initGPUScriptingForPlatform();

  /// Configures GPU contexts on this workspace from a [RenderTexture].
  /// On web, extracts ore/render context pointers directly from the texture's
  /// JS renderer object, avoiding global state. On native (FFI), delegates to
  /// [initGPUScripting] + [setOreContext] + [setRenderContext] as before.
  void configureGPUFromRenderTexture(RenderTexture? renderTexture) =>
      configureGPUFromRenderTextureImpl(this, renderTexture);

  static Uint8List nativeFontBytes() => getNativeFontBytes();

  final HashMap<int, Completer> _completers = HashMap<int, Completer>();

  ScriptingWorkspaceResponseResult responseForWork(int workId);

  @protected
  Future<T> registerCompleter<T>(int workId) {
    if (_closing) {
      throw ScriptingWorkspaceClosedError();
    }
    final completer = Completer<T>();
    assert(!_completers.containsKey(workId));
    final response = responseForWork(workId);
    if (response.available) {
      completeWork(completer, response);
    } else {
      assert(!_completers.containsKey(workId));
      _completers[workId] = completer;
    }
    return completer.future;
  }

  @protected
  void completeWork(
    Completer completer,
    ScriptingWorkspaceResponseResult response,
  ) {
    assert(response.available);
    if (completer is Completer<List<ScriptProblemResult>>) {
      _completeFullProblemReport(completer, response);
    } else if (completer is Completer<ScriptProblemResult>) {
      _completeProblemReport(completer, response);
    } else if (completer is Completer<HighlightResult>) {
      _completeHighlight(completer, response);
    } else if (completer is Completer<FormatResult>) {
      _completeFormat(completer, response);
    } else if (completer is Completer<AutocompleteResult>) {
      _completeAutocomplete(completer, response);
    } else if (completer is Completer<DefinitionResult>) {
      _completeDefinition(completer, response);
    } else if (completer is Completer<ImplementedType?>) {
      _completeImplementedType(completer, response);
    } else if (completer is Completer<VMResult?>) {
      _completeRequestVM(completer, response);
    } else if (completer is Completer<CompileResult?>) {
      _completeCompile(completer, response);
    } else if (completer is Completer<CompileAndSignResult?>) {
      _completeCompileAndSign(completer, response);
    } else if (completer is Completer<FindInFilesResult>) {
      _completeFindInFiles(completer, response);
    } else if (completer is Completer<InsertionCompletion>) {
      _completeInsertionCompletion(completer, response);
    } else if (completer is Completer<String>) {
      _completeDiffSourceLine(completer, response);
    } else if (completer is Completer<bool>) {
      _completeNeedsRecompile(completer, response);
    }
  }

  bool _closing = false;

  /// Whether this workspace is closing or has been closed.
  /// When true, no further async work can be scheduled.
  bool get isClosing => _closing;

  @protected
  void workReadyCallback(int workId) {
    if (_closing) {
      return;
    }
    final completer = _completers.remove(workId);
    if (completer == null) {
      return;
    }
    final response = responseForWork(workId);
    completeWork(completer, response);
  }

  void _completeFullProblemReport(
    Completer<List<ScriptProblemResult>> completer,
    ScriptingWorkspaceResponseResult result,
  ) {
    final reader = result.reader;
    if (reader == null) {
      return;
    }
    final results = <ScriptProblemResult>[];
    while (!reader.isEOF) {
      results.add(ScriptProblemResult.read(reader));
    }
    completer.complete(results);
  }

  void _completeProblemReport(
    Completer<ScriptProblemResult> completer,
    ScriptingWorkspaceResponseResult result,
  ) {
    final reader = result.reader;
    // Handle null reader OR empty buffer (work was cancelled).
    if (reader == null || reader.isEOF) {
      completer.complete(ScriptProblemResult.empty);
      return;
    }

    completer.complete(ScriptProblemResult.read(reader));
  }

  void _completeAutocomplete(
    Completer<AutocompleteResult> completer,
    ScriptingWorkspaceResponseResult result,
  ) {
    final reader = result.reader;
    // Handle null reader OR empty buffer (work was cancelled).
    if (reader == null || reader.isEOF) {
      completer.complete(AutocompleteResult.empty);
      return;
    }

    completer.complete(AutocompleteResult.read(reader));
  }

  void _completeDefinition(
    Completer<DefinitionResult> completer,
    ScriptingWorkspaceResponseResult result,
  ) {
    final reader = result.reader;
    // Handle null reader OR empty buffer (work was cancelled).
    if (reader == null || reader.isEOF) {
      completer.complete(DefinitionResult.notFound);
      return;
    }

    completer.complete(DefinitionResult.read(reader));
  }

  void _completeHighlight(
    Completer<HighlightResult> completer,
    ScriptingWorkspaceResponseResult result,
  ) {
    final reader = result.reader;
    // Handle null reader OR empty buffer (work was cancelled).
    if (reader == null || reader.isEOF) {
      completer.complete(const HighlightResult(HighlightResultType.computed));
      return;
    }
    final highlightResult = HighlightResult.read(reader);
    completer.complete(highlightResult);
  }

  void _completeFormat(
    Completer<FormatResult> completer,
    ScriptingWorkspaceResponseResult result,
  ) {
    final reader = result.reader;
    // Handle null reader OR empty buffer (work was cancelled).
    if (reader == null || reader.isEOF) {
      completer.complete(FormatResult.empty);
      return;
    }

    completer.complete(FormatResult.read(reader));
  }

  void _completeImplementedType(
    Completer<ImplementedType?> completer,
    ScriptingWorkspaceResponseResult result,
  ) {
    final reader = result.reader;
    // Handle null reader OR empty buffer (work was cancelled).
    if (reader == null || reader.isEOF) {
      completer.complete(null);
      return;
    }
    return completer.complete(ImplementedType.read(reader));
  }

  void _completeCompile(
    Completer<CompileResult?> completer,
    ScriptingWorkspaceResponseResult result,
  ) {
    final reader = result.reader;
    // Handle null reader OR empty buffer (work was cancelled).
    if (reader == null || reader.isEOF) {
      completer.complete(null);
      return;
    }
    completer.complete(CompileResult.read(reader));
  }

  void _completeCompileAndSign(
    Completer<CompileAndSignResult?> completer,
    ScriptingWorkspaceResponseResult result,
  ) {
    final reader = result.reader;
    // Handle null reader OR empty buffer (work was cancelled).
    if (reader == null || reader.isEOF) {
      completer.complete(null);
      return;
    }
    completer.complete(CompileAndSignResult.read(reader));
  }

  void _completeFindInFiles(
    Completer<FindInFilesResult> completer,
    ScriptingWorkspaceResponseResult result,
  ) {
    final reader = result.reader;
    // Handle null reader OR empty buffer (work was cancelled).
    if (reader == null || reader.isEOF) {
      completer.complete(FindInFilesResult.empty);
      return;
    }
    completer.complete(FindInFilesResult.read(reader));
  }

  void _completeInsertionCompletion(
    Completer<InsertionCompletion> completer,
    ScriptingWorkspaceResponseResult result,
  ) {
    final reader = result.reader;
    // Handle null reader OR empty buffer (work was cancelled).
    if (reader == null || reader.isEOF) {
      completer.complete(InsertionCompletion.none);
      return;
    }
    final completionType = reader.readUint8();
    if (completionType >= InsertionCompletion.values.length) {
      completer.complete(InsertionCompletion.none);
      return;
    }
    completer.complete(InsertionCompletion.values[completionType]);
  }

  void _completeDiffSourceLine(
    Completer<String> completer,
    ScriptingWorkspaceResponseResult result,
  ) {
    final reader = result.reader;
    // Handle null reader OR empty buffer (work was cancelled).
    if (reader == null || reader.isEOF) {
      completer.complete('');
      return;
    }
    completer.complete(reader.readString());
  }

  void _completeRequestVM(
    Completer<VMResult?> completer,
    ScriptingWorkspaceResponseResult result,
  ) {
    final reader = result.reader;
    if (reader == null || reader.isEOF) {
      completer.complete(null);
      return;
    }
    completer.complete(VMResult.read(reader));
  }

  void _completeNeedsRecompile(
    Completer<bool> completer,
    ScriptingWorkspaceResponseResult result,
  ) {
    final reader = result.reader;
    if (reader == null || reader.isEOF) {
      // Default to true (needs recompile) if no data
      completer.complete(true);
      return;
    }
    completer.complete(reader.readUint8() != 0);
  }

  String get builtinDefinitions;
  List<String> get builtinDefinitionKeys;
  String builtinDefinition(String key);
}
