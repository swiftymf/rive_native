/// Test-visible WebGL context lifecycle probe, backed by wasm glue
/// instrumentation (`native/platform/wasm/init.js`). Browsers cap live
/// WebGL contexts and expose no way to observe the count, so lifecycle
/// tests assert against the glue's own bookkeeping.
library;

export 'web_context_probe_io.dart'
    if (dart.library.js_interop) 'web_context_probe_web.dart';
