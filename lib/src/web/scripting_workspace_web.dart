import 'dart:async';
import 'dart:js_interop' as js;
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:rive_native/rive_native.dart' show RenderTexture;
import 'package:rive_native/scripting_workspace.dart';
import 'package:rive_native/src/rive_native_web.dart';
import 'package:rive_native/utilities.dart';

late js.JSFunction _makeScriptingWorkspace;
late js.JSFunction _deleteScriptingWorkspace;
late js.JSFunction _requestProblemReport;
late js.JSFunction _requestFullProblemReport;
late js.JSFunction _requestImplementedType;
late js.JSFunction _scriptingWorkspaceCompleteInsertion;
// ignore: unused_element
late js.JSFunction _scriptingWorkspaceRequestAutocomplete;
late js.JSFunction _scriptingWorkspaceRequestAutocompleteWGSL;
late js.JSFunction _scriptingWorkspaceRequestGetDefinition;
late js.JSFunction _scriptingWorkspaceHighlightRow;
late js.JSFunction _scriptingWorkspaceResponse;
late js.JSFunction _setScriptSource;
late js.JSFunction _removeScriptSource;
late js.JSFunction _setScriptDiffSource;
late js.JSFunction _clearScriptDiffSource;
late js.JSFunction _requestDiffSourceLine;
late js.JSFunction _checkScriptsWithRequires;
late js.JSFunction _setSystemGeneratedSource;
late js.JSFunction _scriptingWorkspaceFormat;
late js.JSFunction _scriptingWorkspaceCompile;
late js.JSFunction _scriptingWorkspaceCheckNeedsRecompile;
late js.JSFunction _scriptingWorkspaceFindInFiles;
late js.JSFunction _nativeFontBytes;
late js.JSFunction _freeNativeFont;
late js.JSFunction _scriptingWorkspaceRequestVM;
late js.JSFunction _setScriptSourceWithType;
late js.JSFunction _setScriptSourceScoped;
late js.JSFunction _setScriptScope;
late js.JSFunction _setLibraryImport;
late js.JSFunction _removeLibraryImport;
late js.JSFunction _setLibraryCanonicalName;
late js.JSFunction _rewriteRequires;
late js.JSFunction _scriptingWorkspaceBuiltinDefinitions;
late js.JSFunction _scriptingWorkspaceBuiltinDefinitionKeys;
late js.JSFunction _scriptingWorkspaceBuiltinDefinition;
late js.JSFunction _scriptingWorkspaceSetOreContext;
late js.JSFunction _scriptingWorkspaceSetRenderContext;

class ScriptingWorkspaceResponseResultWasm
    implements ScriptingWorkspaceResponseResult {
  @override
  final bool available;
  late final ByteData? data;
  ScriptingWorkspaceResponseResultWasm(js.JSObject object)
    : available = (object['available'] as js.JSBoolean).toDart {
    data = available ? (object['data'] as js.JSDataView).toDart : null;
  }

  @override
  BinaryReader? get reader {
    final data = this.data;
    if (data == null) {
      return null;
    }

    return BinaryReader(data);
  }
}

// bool _wasmBool(js.JSAny? value) => (value as js.JSNumber).toDartInt == 1;
js.JSNumber _boolWasm(bool value) => (value ? 1 : 0).toJS;

class ScriptingWorkspaceWasm extends ScriptingWorkspace {
  static void link(js.JSObject module) {
    _makeScriptingWorkspace = module['makeScriptingWorkspace'] as js.JSFunction;
    _deleteScriptingWorkspace =
        module['_deleteScriptingWorkspace'] as js.JSFunction;
    _requestProblemReport =
        module['scriptingWorkspaceRequestProblemReport'] as js.JSFunction;
    _requestFullProblemReport =
        module['_scriptingWorkspaceRequestFullProblemReport'] as js.JSFunction;
    _requestImplementedType =
        module['scriptingWorkspaceImplementedType'] as js.JSFunction;
    _scriptingWorkspaceCompleteInsertion =
        module['scriptingWorkspaceCompleteInsertion'] as js.JSFunction;
    _scriptingWorkspaceRequestAutocomplete =
        module['scriptingWorkspaceRequestAutocomplete'] as js.JSFunction;
    _scriptingWorkspaceRequestAutocompleteWGSL =
        module['scriptingWorkspaceRequestAutocompleteWGSL'] as js.JSFunction;
    _scriptingWorkspaceRequestGetDefinition =
        module['scriptingWorkspaceRequestGetDefinition'] as js.JSFunction;
    _setScriptSourceWithType =
        module['scriptingWorkspaceSetScriptSourceWithType'] as js.JSFunction;
    _setScriptSourceScoped =
        module['scriptingWorkspaceSetScriptSourceScoped'] as js.JSFunction;
    _setScriptScope =
        module['scriptingWorkspaceSetScriptScope'] as js.JSFunction;
    _setLibraryImport =
        module['scriptingWorkspaceSetLibraryImport'] as js.JSFunction;
    _removeLibraryImport =
        module['scriptingWorkspaceRemoveLibraryImport'] as js.JSFunction;
    _setLibraryCanonicalName =
        module['scriptingWorkspaceSetLibraryCanonicalName'] as js.JSFunction;
    _rewriteRequires =
        module['scriptingWorkspaceRewriteRequires'] as js.JSFunction;
    _scriptingWorkspaceBuiltinDefinitions =
        module['_scriptingWorkspaceBuiltinDefinitions'] as js.JSFunction;
    _scriptingWorkspaceBuiltinDefinitionKeys =
        module['_scriptingWorkspaceBuiltinDefinitionKeys'] as js.JSFunction;
    _scriptingWorkspaceBuiltinDefinition =
        module['_scriptingWorkspaceBuiltinDefinition'] as js.JSFunction;
    _scriptingWorkspaceHighlightRow =
        module['scriptingWorkspaceHighlightRow'] as js.JSFunction;
    _scriptingWorkspaceResponse =
        module['scriptingWorkspaceResponse'] as js.JSFunction;
    _setScriptSource =
        module['scriptingWorkspaceSetScriptSource'] as js.JSFunction;
    _removeScriptSource =
        module['scriptingWorkspaceRemoveScriptSource'] as js.JSFunction;
    _setScriptDiffSource =
        module['scriptingWorkspaceSetScriptDiffSource'] as js.JSFunction;
    _clearScriptDiffSource =
        module['scriptingWorkspaceClearScriptDiffSource'] as js.JSFunction;
    _requestDiffSourceLine =
        module['scriptingWorkspaceRequestDiffSourceLine'] as js.JSFunction;
    _checkScriptsWithRequires =
        module['_scriptingWorkspaceCheckScriptsWithRequires'] as js.JSFunction;
    _setSystemGeneratedSource =
        module['scriptingWorkspaceSetSystemGeneratedSource'] as js.JSFunction;
    _scriptingWorkspaceFormat =
        module['scriptingWorkspaceFormat'] as js.JSFunction;
    _scriptingWorkspaceCompile =
        module['scriptingWorkspaceCompile'] as js.JSFunction;
    _scriptingWorkspaceCheckNeedsRecompile =
        module['scriptingWorkspaceCheckNeedsRecompile'] as js.JSFunction;
    _scriptingWorkspaceFindInFiles =
        module['_scriptingWorkspaceFindInFiles'] as js.JSFunction;
    _scriptingWorkspaceRequestVM =
        module['scriptingWorkspaceRequestVM'] as js.JSFunction;
    _nativeFontBytes = module['nativeFontBytes'] as js.JSFunction;
    _freeNativeFont = module['_freeNativeFont'] as js.JSFunction;
    _scriptingWorkspaceSetOreContext =
        module['_scriptingWorkspaceSetOreContext'] as js.JSFunction;
    _scriptingWorkspaceSetRenderContext =
        module['_scriptingWorkspaceSetRenderContext'] as js.JSFunction;
  }

  static final Finalizer<int> _finalizer = Finalizer(
    (nativePtr) =>
        _deleteScriptingWorkspace.callAsFunction(null, nativePtr.toJS),
  );
  int _nativePtr = 0;

  ScriptingWorkspaceWasm({bool canvasEnabled = false}) {
    _nativePtr =
        (_makeScriptingWorkspace.callAsFunction(
          null,
          workReadyCallback.toJS,
          canvasEnabled.toJS,
        ) as js.JSNumber).toDartInt;
    _finalizer.attach(this, _nativePtr, detach: this);
  }

  @override
  void dispose() {
    super.dispose();
    _deleteScriptingWorkspace.callAsFunction(null, _nativePtr.toJS);
    _nativePtr = 0;
    _finalizer.detach(this);
  }

  @override
  Future<AutocompleteResult> autocomplete(
    String scriptName,
    ScriptPosition position,
  ) {
    final workId =
        (_scriptingWorkspaceRequestAutocomplete.callAsFunction(
                  null,
                  _nativePtr.toJS,
                  scriptName.toJS,
                  position.line.toJS,
                  position.column.toJS,
                )
                as js.JSNumber)
            .toDartInt;

    return registerCompleter(workId);
  }

  @override
  Future<AutocompleteResult> autocompleteWGSL(
    String scriptName,
    ScriptPosition position,
  ) {
    final workId =
        (_scriptingWorkspaceRequestAutocompleteWGSL.callAsFunction(
                  null,
                  _nativePtr.toJS,
                  scriptName.toJS,
                  position.line.toJS,
                  position.column.toJS,
                )
                as js.JSNumber)
            .toDartInt;

    return registerCompleter(workId);
  }

  @override
  Future<DefinitionResult> getDefinition(
    String scriptName,
    ScriptPosition position,
  ) {
    final workId =
        (_scriptingWorkspaceRequestGetDefinition.callAsFunction(
                  null,
                  _nativePtr.toJS,
                  scriptName.toJS,
                  position.line.toJS,
                  position.column.toJS,
                )
                as js.JSNumber)
            .toDartInt;

    return registerCompleter(workId);
  }

  @override
  Future<InsertionCompletion> completeInsertion(
    String scriptName,
    ScriptPosition position,
  ) {
    final workId =
        (_scriptingWorkspaceCompleteInsertion.callAsFunction(
                  null,
                  _nativePtr.toJS,
                  scriptName.toJS,
                  position.line.toJS,
                  position.column.toJS,
                )
                as js.JSNumber)
            .toDartInt;
    return registerCompleter(workId);
  }

  @override
  Future<FormatResult> format(String scriptName) {
    final workId =
        (_scriptingWorkspaceFormat.callAsFunction(
                  null,
                  _nativePtr.toJS,
                  scriptName.toJS,
                )
                as js.JSNumber)
            .toDartInt;

    return registerCompleter(workId);
  }

  @override
  Future<List<ScriptProblemResult>> fullProblemReport() {
    final workId =
        (_requestFullProblemReport.callAsFunction(null, _nativePtr.toJS)
                as js.JSNumber)
            .toDartInt;
    return registerCompleter(workId);
  }

  @override
  Future<ScriptProblemResult> problemReport(String scriptName) async {
    final workId =
        (_requestProblemReport.callAsFunction(
                  null,
                  _nativePtr.toJS,
                  scriptName.toJS,
                )
                as js.JSNumber)
            .toDartInt;
    return registerCompleter(workId);
  }

  @override
  Future<ImplementedType?> implementedType(String scriptName) async {
    final workId =
        (_requestImplementedType.callAsFunction(
                  null,
                  _nativePtr.toJS,
                  scriptName.toJS,
                )
                as js.JSNumber)
            .toDartInt;
    return registerCompleter(workId);
  }

  @override
  Uint32List rowHighlight(String scriptName, int row) {
    var result =
        _scriptingWorkspaceHighlightRow.callAsFunction(
              null,
              _nativePtr.toJS,
              scriptName.toJS,
              row.toJS,
            )
            as js.JSUint32Array;
    return result.toDart;
  }

  @override
  Future<HighlightResult> setSystemGeneratedSource(
    String scriptName,
    String prefix,
    String source,
  ) async {
    final workId =
        (_setSystemGeneratedSource.callAsFunctionEx(
                  null,
                  _nativePtr.toJS,
                  scriptName.toJS,
                  prefix.toJS,
                  source.toJS,
                )
                as js.JSNumber)
            .toDartInt;

    return registerCompleter(workId);
  }

  @override
  Future<HighlightResult> setScriptSource(
    String scriptId,
    String scriptName,
    String source, {
    bool highlight = false,
    int libraryId = 0,
    int libraryVersionId = 0,
  }) async {
    final workId = libraryId == 0 && libraryVersionId == 0
        ? (_setScriptSource.callAsFunctionEx(
                    null,
                    _nativePtr.toJS,
                    scriptId.toJS,
                    scriptName.toJS,
                    source.toJS,
                    highlight.toJS,
                  )
                  as js.JSNumber)
              .toDartInt
        : (_setScriptSourceScoped.callAsFunctionEx(
                    null,
                    _nativePtr.toJS,
                    scriptId.toJS,
                    scriptName.toJS,
                    source.toJS,
                    libraryId.toJS,
                    libraryVersionId.toJS,
                    highlight.toJS,
                  )
                  as js.JSNumber)
              .toDartInt;
    if (!highlight) {
      // Still register the completer so the native response gets consumed,
      // but don't await it — just return the default result immediately.
      unawaited(registerCompleter(workId));
      return HighlightResult(HighlightResultType.unknown);
    }

    return registerCompleter(workId);
  }

  @override
  void setScriptScope(String scriptId, int libraryId, int libraryVersionId) {
    _setScriptScope.callAsFunctionEx(
      null,
      _nativePtr.toJS,
      scriptId.toJS,
      libraryId.toJS,
      libraryVersionId.toJS,
    );
  }

  @override
  void setLibraryImport(
    int callerLibraryId,
    int callerLibraryVersionId,
    String name,
    int targetLibraryId,
    int targetLibraryVersionId,
  ) {
    _setLibraryImport.callAsFunctionEx(
      null,
      _nativePtr.toJS,
      callerLibraryId.toJS,
      callerLibraryVersionId.toJS,
      name.toJS,
      targetLibraryId.toJS,
      targetLibraryVersionId.toJS,
    );
  }

  @override
  void removeLibraryImport(
    int callerLibraryId,
    int callerLibraryVersionId,
    String name,
  ) {
    _removeLibraryImport.callAsFunctionEx(
      null,
      _nativePtr.toJS,
      callerLibraryId.toJS,
      callerLibraryVersionId.toJS,
      name.toJS,
    );
  }

  @override
  void setLibraryCanonicalName(
    int libraryId,
    int libraryVersionId,
    String canonicalName,
  ) {
    _setLibraryCanonicalName.callAsFunctionEx(
      null,
      _nativePtr.toJS,
      libraryId.toJS,
      libraryVersionId.toJS,
      canonicalName.toJS,
    );
  }

  @override
  Future<String> rewriteRequires(String scriptId) async {
    if (isClosing) {
      return '';
    }
    final workId =
        (_rewriteRequires.callAsFunctionEx(
                  null,
                  _nativePtr.toJS,
                  scriptId.toJS,
                )
                as js.JSNumber)
            .toDartInt;
    return registerCompleter(workId);
  }

  @override
  Future<HighlightResult> setWGSLScriptSource(
    String scriptId,
    String scriptName,
    String source, {
    bool highlight = false,
  }) async {
    final workId =
        (_setScriptSourceWithType.callAsFunctionEx(
                  null,
                  _nativePtr.toJS,
                  scriptId.toJS,
                  scriptName.toJS,
                  source.toJS,
                  3.toJS,
                  highlight.toJS,
                )
                as js.JSNumber)
            .toDartInt;
    if (!highlight) {
      unawaited(registerCompleter(workId));
      return HighlightResult(HighlightResultType.unknown);
    }

    return registerCompleter(workId);
  }

  @override
  void removeScriptSource(String scriptId) => _removeScriptSource
      .callAsFunctionEx(null, _nativePtr.toJS, scriptId.toJS);

  @override
  Future<HighlightResult> setScriptDiffSource(
    String scriptId,
    String source,
  ) async {
    final workId =
        (_setScriptDiffSource.callAsFunctionEx(
                  null,
                  _nativePtr.toJS,
                  scriptId.toJS,
                  source.toJS,
                )
                as js.JSNumber)
            .toDartInt;
    return registerCompleter(workId);
  }

  @override
  void clearScriptDiffSource(String scriptId) => _clearScriptDiffSource
      .callAsFunctionEx(null, _nativePtr.toJS, scriptId.toJS);

  @override
  Future<String> getDiffSourceLine(String scriptId, int line) async {
    if (isClosing) {
      return '';
    }
    final workId =
        (_requestDiffSourceLine.callAsFunctionEx(
                  null,
                  _nativePtr.toJS,
                  scriptId.toJS,
                  line.toJS,
                )
                as js.JSNumber)
            .toDartInt;
    return registerCompleter(workId);
  }

  @override
  Future<CompileResult?> compile(
    String scriptName, {
    bool failOnErrors = false,
    bool compileDependencies = false,
    OptimizationLevel optimizationLevel = OptimizationLevel.medium,
    DebugLevel debugLevel = DebugLevel.medium,
  }) {
    final workId =
        (_scriptingWorkspaceCompile.callAsFunctionEx(
                  null,
                  _nativePtr.toJS,
                  scriptName.toJS,
                  _boolWasm(failOnErrors),
                  _boolWasm(compileDependencies),
                  optimizationLevel.index.toJS,
                  debugLevel.index.toJS,
                )
                as js.JSNumber)
            .toDartInt;
    return registerCompleter(workId);
  }

  @override
  void setOreContext(int oreContextPointer) {
    _scriptingWorkspaceSetOreContext.callAsFunction(
      null,
      _nativePtr.toJS,
      oreContextPointer.toJS,
    );
  }

  @override
  void setRenderContext(int renderContextPointer) {
    _scriptingWorkspaceSetRenderContext.callAsFunction(
      null,
      _nativePtr.toJS,
      renderContextPointer.toJS,
    );
  }

  @override
  Future<VMResult?> requestVM({int factoryPointer = 0}) {
    final workId =
        (_scriptingWorkspaceRequestVM.callAsFunction(
                  null,
                  _nativePtr.toJS,
                  factoryPointer.toJS,
                )
                as js.JSNumber)
            .toDartInt;
    return registerCompleter(workId);
  }

  @override
  Future<bool> checkNeedsRecompile(String scriptId) {
    final workId =
        (_scriptingWorkspaceCheckNeedsRecompile.callAsFunction(
                  null,
                  _nativePtr.toJS,
                  scriptId.toJS,
                )
                as js.JSNumber)
            .toDartInt;
    return registerCompleter(workId);
  }

  @override
  ScriptingWorkspaceResponseResult responseForWork(int workId) =>
      ScriptingWorkspaceResponseResultWasm(
        _scriptingWorkspaceResponse.callAsFunction(
              null,
              _nativePtr.toJS,
              workId.toJS,
            )
            as js.JSObject,
      );

  @override
  void checkScriptsWithRequires() =>
      _checkScriptsWithRequires.callAsFunction(null, _nativePtr.toJS);

  @override
  String get builtinDefinitions => RiveWasm.toDartString(
    (_scriptingWorkspaceBuiltinDefinitions.callAsFunction(null, _nativePtr.toJS)
            as js.JSNumber)
        .toDartInt,
  );

  @override
  List<String> get builtinDefinitionKeys => RiveWasm.toDartString(
    (_scriptingWorkspaceBuiltinDefinitionKeys.callAsFunction(
              null,
              _nativePtr.toJS,
            )
            as js.JSNumber)
        .toDartInt,
  ).split('\n').where((s) => s.isNotEmpty).toList();

  @override
  String builtinDefinition(String key) => RiveWasm.toDartString(
    (_scriptingWorkspaceBuiltinDefinition.callAsFunction(
              null,
              _nativePtr.toJS,
              key.toJS,
            )
            as js.JSNumber)
        .toDartInt,
  );

  @override
  Future<CompileAndSignResult?> compileAndSign(
    Iterable<String> scriptNames,
    Uint8List privateKey, {
    bool failOnErrors = false,
    OptimizationLevel optimizationLevel = OptimizationLevel.medium,
    DebugLevel debugLevel = DebugLevel.medium,
    int shaderOutputFlags = 0,
  }) {
    throw UnimplementedError("Not supported on web.");
  }

  @override
  Future<FindInFilesResult> findInFiles(
    Iterable<String>? inclusionSet,
    String query, {
    bool caseSensitive = false,
    bool matchWholeWord = false,
    bool regularExpression = false,
    bool trim = false,
  }) {
    final writer = BinaryWriter();
    final inclusionList = inclusionSet?.toList() ?? [];
    writer.writeVarUint(inclusionList.length);
    for (final name in inclusionList) {
      writer.writeString(name);
    }
    writer.writeString(query);
    final buffer = writer.uint8Buffer;
    final wasmBuffer = WasmBuffer.fromBytes(buffer);

    final workId =
        (_scriptingWorkspaceFindInFiles.callAsFunctionEx(
                  null,
                  _nativePtr.toJS,
                  wasmBuffer.pointer,
                  buffer.length.toJS,
                  _boolWasm(caseSensitive),
                  _boolWasm(matchWholeWord),
                  _boolWasm(regularExpression),
                  _boolWasm(trim),
                )
                as js.JSNumber)
            .toDartInt;
    wasmBuffer.dispose();
    return registerCompleter(workId);
  }
}

ScriptingWorkspace makeScriptingWorkspace({bool canvasEnabled = false}) =>
    ScriptingWorkspaceWasm(canvasEnabled: canvasEnabled);

/// On web, GPU scripting is now configured via [configureGPUFromRenderTextureImpl]
/// which extracts context pointers directly from the RenderTexture. This legacy
/// entry point returns 0; callers should use
/// [ScriptingWorkspace.configureGPUFromRenderTexture] instead.
int initGPUScriptingForPlatform() => 0;

/// On web, extracts ore/render context pointers directly from the
/// RenderTexture's JS renderer object, bypassing global state.
void configureGPUFromRenderTextureImpl(
  ScriptingWorkspace workspace,
  RenderTexture? renderTexture,
) {
  if (renderTexture == null) return;
  final oreCtxPtr = webOreCtxPtrFromRenderTexture(renderTexture);
  final renderCtxPtr = webRenderCtxPtrFromRenderTexture(renderTexture);
  if (oreCtxPtr != 0) {
    workspace.setOreContext(oreCtxPtr);
  }
  if (renderCtxPtr != 0) {
    workspace.setRenderContext(renderCtxPtr);
  }
}

Uint8List getNativeFontBytes() {
  final data =
      (_nativeFontBytes.callAsFunction(null) as js.JSUint8Array).toDart;
  final result = Uint8List.fromList(data);
  _freeNativeFont.callAsFunction(null);
  return result;
}
