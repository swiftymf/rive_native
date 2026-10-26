/// Edit-time boolean path operations (union, subtract, intersect, exclude)
/// backed by packages/pathops. Editor-only: the native symbols are excluded
/// from flutter_runtime builds, so this library must never be imported from
/// runtime code paths.
library;

export 'src/path_ops_types.dart';
export 'src/ffi/rive_pathops_ffi.dart'
    if (dart.library.js_interop) 'src/web/rive_pathops_web.dart'
    show combineRawPaths, simplifyRawPath, pathOpsAvailable;
