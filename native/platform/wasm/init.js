Module["onRuntimeInitialized"] = function () {
  const makeRenderer = Module["makeRenderer"];
  const cppDeleteRenderer = Module["deleteRenderer"];
  let _offscreenGL = null;
  // Device capabilities from the first feature probe. Immutable for the
  // page's lifetime, so an offscreen rebuild after releaseOffscreenGL can
  // skip re-probing (and the extra context the MSAA re-probe would create).
  let _glCaps = null;

  // Live WebGL2 contexts created by this module (canvases + the offscreen
  // probe), decremented on genuine release. Browsers cap live contexts
  // (~16 browser-wide) and expose no way to observe the count, so tests
  // assert against this instead.
  let _liveGLContexts = 0;
  Module["liveGLContextCount"] = function () {
    return _liveGLContexts;
  };

  function makeGLRenderer(canvas, enableMSAA = false) {
    var contextAttributes = {
      "alpha": true,
      "depth": enableMSAA,
      "stencil": enableMSAA,
      "antialias": enableMSAA,
      "premultipliedAlpha": true,
      "preserveDrawingBuffer": 1,
      "powerPreference": "high-performance",
      "failIfMajorPerformanceCaveat": 0,
      "enableExtensionsByDefault": false,
      "explicitSwapControl": 0,
      "renderViaOffscreenBackBuffer": 0,
    };

    var gl = canvas.getContext("webgl2", contextAttributes);
    if (!gl) {
      return null;
    }
    var handle = GL.registerContext(gl, contextAttributes);

    GL.makeContextCurrent(handle);

    _liveGLContexts++;
    return {
      "_ptr": makeRenderer(canvas.width, canvas.height),
      _handle: handle,
      _canvas: canvas,
      _gl: gl,
    };
  }

  // Fully release a renderer made by makeGLRenderer: the C++ renderer (PLS +
  // ore contexts) first, while its WebGL context is still alive, then the
  // browser context itself via WEBGL_lose_context. The context slot is the
  // scarce resource — the browser caps live contexts at ~16 and a lost one
  // no longer counts.
  //
  // Deliberately do NOT GL.deleteContext: objects uploaded to this context
  // can outlive it (an image's GPU texture is torn down when its File is
  // disposed, which may be after the render texture died), and that teardown
  // re-binds the upload context by handle. A lost-but-registered context
  // makes those glDelete* calls safe no-ops, whereas an unregistered handle
  // nulls Emscripten's current context and the next GL call crashes with
  // "Cannot read properties of undefined (reading 'deleteTexture')" — the
  // same class of bug as runtime_wasm PRs #12770/#12886. The registry entry
  // it keeps is a few objects per released texture; the context itself is
  // gone.
  function releaseGLRenderer(renderer) {
    if (renderer["_ptr"]) {
      cppDeleteRenderer(renderer["_ptr"]);
      renderer["_ptr"] = 0;
    }
    const lose = renderer._gl.getExtension("WEBGL_lose_context");
    if (lose) {
      lose.loseContext();
    }
    if (_activeRenderer === renderer) {
      _activeRenderer = null;
    }
    // Unconditional: the extension is universally implemented, and remains
    // queryable even on a lost context (it is the recovery extension) — a
    // null `lose` in practice means the context is already lost, i.e. its
    // browser slot is already free and this release is pure bookkeeping.
    _liveGLContexts--;
  }

  // Genuinely destroy a renderer returned by Module["makeRenderer"] — used
  // by the Dart side when a disposed render texture doesn't go back to the
  // (bounded) pool.
  Module["releaseRenderer"] = releaseGLRenderer;

  // Release the shared offscreen probe context (feature detection + GPU
  // limits). Recreated on demand by the next makeRenderer call; lets an idle
  // page drop to zero live contexts.
  Module["releaseOffscreenGL"] = function () {
    if (_offscreenGL) {
      releaseGLRenderer(_offscreenGL);
      _offscreenGL = null;
    }
  };

  Module["makeRenderer"] = function (canvas) {
    if (!_offscreenGL) {
      function MakeOffscreenGL(enableMSAA) {
        const offscreenCanvas = document.createElement("canvas");
        offscreenCanvas.width = 1;
        offscreenCanvas.height = 1;
        _offscreenGL = makeGLRenderer(offscreenCanvas, enableMSAA);
        if (!_offscreenGL) {
          throw new Error(
            "Rive: failed to create a WebGL2 context. WebGL2 may be " +
              "unavailable or disabled in this environment.",
          );
        }

        _offscreenGL._hasPixelLocalStorage = Boolean(
          _offscreenGL._gl.getExtension("WEBGL_shader_pixel_local_storage"),
        );

        _offscreenGL._maxRTSize = Math.min(
          _offscreenGL._gl.getParameter(_offscreenGL._gl.MAX_RENDERBUFFER_SIZE),
          _offscreenGL._gl.getParameter(_offscreenGL._gl.MAX_TEXTURE_SIZE),
        );

        // WEBGL_shader_pixel_local_storage works without MSAA.
        _offscreenGL._enableAntialiasCanvas =
          !_offscreenGL._hasPixelLocalStorage;

        const webglDebugInfo = _offscreenGL._gl.getExtension(
          "WEBGL_debug_renderer_info",
        );
        if (webglDebugInfo) {
          const vendor = _offscreenGL._gl.getParameter(
            webglDebugInfo.UNMASKED_VENDOR_WEBGL,
          );
          const renderer = _offscreenGL._gl.getParameter(
            webglDebugInfo.UNMASKED_RENDERER_WEBGL,
          );
          if (
            vendor.includes("Google") &&
            renderer.includes("ANGLE Metal Renderer")
          ) {
            // We experience flickering on Chrome/Metal when using a WebGL context with
            // "antialias:true". This appears to be a synchronization issue internal to the browser.
            // Avoid "antialias:true" in this case, opting instead to do our own internal MSAA.
            _offscreenGL._enableAntialiasCanvas = false;
          }
        }

        return _offscreenGL;
      }

      if (_glCaps) {
        // Rebuild after releaseOffscreenGL, reusing the cached probe results.
        const offscreenCanvas = document.createElement("canvas");
        offscreenCanvas.width = 1;
        offscreenCanvas.height = 1;
        _offscreenGL = makeGLRenderer(
          offscreenCanvas,
          _glCaps._enableAntialiasCanvas,
        );
        if (!_offscreenGL) {
          throw new Error(
            "Rive: failed to create a WebGL2 context. WebGL2 may be " +
              "unavailable or disabled in this environment.",
          );
        }
        Object.assign(_offscreenGL, _glCaps);
      } else {
        _offscreenGL = MakeOffscreenGL(/*enableMSAA =*/ true);
        if (!_offscreenGL._enableAntialiasCanvas) {
          // This browser prefers "antialias:false". Re-create the offscreen without MSAA.
          const msaaProbe = _offscreenGL;
          _offscreenGL = MakeOffscreenGL(/*enableMSAA =*/ false);
          // Release the discarded probe (C++ renderer + WebGL context): an
          // idle context still occupies one of the browser's ~16 slots,
          // contributing to context-loss evictions elsewhere (including
          // Flutter's own CanvasKit surfaces).
          releaseGLRenderer(msaaProbe);
        }
        _glCaps = {
          _hasPixelLocalStorage: _offscreenGL._hasPixelLocalStorage,
          _maxRTSize: _offscreenGL._maxRTSize,
          _enableAntialiasCanvas: _offscreenGL._enableAntialiasCanvas,
        };
      }
    }
    var renderer = makeGLRenderer(
      canvas,
      /*enableMSAA =*/ _offscreenGL._enableAntialiasCanvas,
    );
    if (!renderer) {
      throw new Error(
        "Rive: failed to create a WebGL2 context for a canvas — the " +
          "browser's live WebGL context limit may be exhausted.",
      );
    }
    if (renderer) {
      // Extract the renderer-owned ore + PLS render context pointers.
      // These are created in the WebGL2Renderer constructor in the same
      // GL context, so they're guaranteed to match this canvas.
      renderer._oreCtxPtr = Module["_rendererGetOreContext"](renderer["_ptr"]);
      renderer._renderCtxPtr = Module["_rendererGetGPURenderContext"](
        renderer["_ptr"],
      );
      // The GPU's render-target limit, used to clamp canvas backing sizes in
      // clearRenderer (a backing beyond it fails to render at all).
      renderer._maxRTSize = _offscreenGL._maxRTSize;
      // Track the most recently created renderer so clearRenderer() can
      // restore the correct GL context each frame.
      _activeRenderer = renderer;
    }
    return renderer;
  };

  const cppClear = Module["clearRenderer"];
  const cppResize = Module["resizeRenderer"];

  // Track the active renderer so we know which GL context to restore after
  // ore operations that may have changed it.
  let _activeRenderer = null;

  Module["clearRenderer"] = function (renderer, color) {
    _activeRenderer = renderer;
    GL.makeContextCurrent(renderer._handle);

    const canvas = renderer._canvas;
    // Backing policy is pushed onto the renderer by the Dart side
    // (RenderResolution): an explicit physical size wins; otherwise size from
    // the element's layout × devicePixelRatio × per-axis scales (which carry
    // the ancestor paint scale under the display policy), capped at a logical
    // max (aspect preserved). Everything is finally clamped to the GPU's
    // render-target limit.
    let w, h;
    if (renderer._fixedWidth > 0 && renderer._fixedHeight > 0) {
      w = renderer._fixedWidth;
      h = renderer._fixedHeight;
    } else {
      let lw = canvas.clientWidth * (renderer._backingScaleX || 1);
      let lh = canvas.clientHeight * (renderer._backingScaleY || 1);
      const maxLogical = renderer._maxBackingLogical || 0;
      const longest = Math.max(lw, lh);
      if (maxLogical > 0 && longest > maxLogical) {
        const f = maxLogical / longest;
        lw *= f;
        lh *= f;
      }
      w = Math.round(lw * window.devicePixelRatio) || 1;
      h = Math.round(lh * window.devicePixelRatio) || 1;
    }
    const maxRT = renderer._maxRTSize || 0;
    const longestPhysical = Math.max(w, h);
    if (maxRT > 0 && longestPhysical > maxRT) {
      const f = maxRT / longestPhysical;
      w = Math.max(1, Math.floor(w * f));
      h = Math.max(1, Math.floor(h * f));
    }
    if (canvas.width != w || canvas.height != h) {
      canvas.width = w;
      canvas.height = h;
      cppResize(renderer["_ptr"], canvas.width, canvas.height);
    }
    cppClear(renderer["_ptr"], color);
  };

  Module["stringViewU8"] = function (start) {
    var wasmMemory = Module["wasmMemory"];
    var buffer = wasmMemory ? wasmMemory["buffer"] : Module["HEAPU8"]["buffer"];
    var data = wasmMemory
      ? new Uint8Array(buffer, buffer.byteOffset, buffer.byteLength)
      : Module["HEAPU8"];
    var current = start;
    while (data[current] != 0 && current < buffer.byteLength) {
      current++;
    }
    return new Uint8Array(buffer, start, current - start);
  };

  var nativeMakeGlyphPath = Module["makeGlyphPath"];
  var move = 0;
  var line = 1;
  var quad = 2;
  var cubic = 4;
  var close = 5;
  Module["makeGlyphPath"] = function (font, glyphId) {
    var glyph = nativeMakeGlyphPath(font, glyphId);
    var verbCount = glyph[3];
    var ptsPtr = glyph[1];
    var verbPtr = glyph[2];
    var verbs = Module["heapViewU8"](verbPtr, verbCount);

    let pointCount = 0;
    for (var verb of verbs) {
      switch (verb) {
        case move:
        case line:
          pointCount++;
          break;
        case quad:
          pointCount += 2;
          break;
        case cubic:
          pointCount += 3;
          break;
        default:
          break;
      }
    }

    const ptsStart = ptsPtr;
    return {
      "rawPath": glyph[0],
      "verbs": verbs,
      "points": Module["heapViewF32"](ptsStart, pointCount * 2),
    };
  };

  // Editor-only boolean path ops (absent in flutter_runtime wasm builds).
  // Like makeGlyphPath, converts the embind value_array (indexed, raw heap
  // pointers) into an object with named fields and typed-array views.
  var nativePathOpsResult = function (result) {
    var verbCount = result[3];
    var pointCount = result[4];
    return {
      "rawPath": result[0],
      "points": Module["heapViewF32"](result[1], pointCount * 2),
      "verbs": Module["heapViewU8"](result[2], verbCount),
      "verbCount": verbCount,
      "pointCount": pointCount,
      "fillRule": result[5],
      "success": result[6],
    };
  };
  // Editor-only exports (excluded from flutter_runtime modules). Gate on
  // ALL of them so a partial module leaves everything unwrapped and the
  // Dart side's link() fails closed (pathOpsAvailable == false) instead of
  // wrapping a missing export.
  if (
    Module["combinePaths"] &&
    Module["simplifyPath"] &&
    Module["deletePathOpsResult"]
  ) {
    var nativeCombinePaths = Module["combinePaths"];
    Module["combinePaths"] = function (op, ptsA, vbsA, fillA, ptsB, vbsB, fillB) {
      return nativePathOpsResult(
        nativeCombinePaths(op, ptsA, vbsA, fillA, ptsB, vbsB, fillB)
      );
    };
    var nativeSimplifyPath = Module["simplifyPath"];
    Module["simplifyPath"] = function (pts, vbs, fill) {
      return nativePathOpsResult(nativeSimplifyPath(pts, vbs, fill));
    };
  }

  var nativeShapeText = Module["shapeText"];
  Module["shapeText"] = function (codeUnits, runsList, level) {
    var shapeResult = nativeShapeText(codeUnits, runsList, level);
    return {
      "rawResult": shapeResult,
      "results": Module["heapDataView"](shapeResult),
    };
  };

  var nativeBreakLines = Module["breakLines"];
  Module["breakLines"] = function (shape, width, align, wrap) {
    var breakResult = nativeBreakLines(shape, width, align, wrap);
    return {
      "rawResult": breakResult,
      "results": Module["heapViewU8"](breakResult),
    };
  };

  var nativeFontFeatures = Module["fontFeatures"];
  Module["fontFeatures"] = function (font) {
    var featuresPtr = nativeFontFeatures(font);
    var heap = Module["heap"]();
    const view = new DataView(heap, featuresPtr);
    var dataPtr = view["getUint32"](0, true);
    var size = view["getUint32"](4, true);

    const dataView = new DataView(heap, dataPtr);

    var tags = [];
    for (var i = 0; i < size; i++) {
      var tag = dataView["getUint32"](i * 4, true);
      tags.push(tag);
    }

    Module["deleteFontFeatures"](featuresPtr);
    return tags;
  };

  Module["heap"] = function (start, length) {
    var wasmMemory = Module["wasmMemory"];
    if (!wasmMemory) {
      return Module["HEAPU8"]["buffer"];
    }
    return wasmMemory["buffer"];
  };

  Module["heapViewU8"] = function (start, length) {
    var wasmMemory = Module["wasmMemory"];
    if (!wasmMemory) {
      return new Uint8Array(Module["HEAPU8"]["buffer"], start, length);
    }
    return new Uint8Array(wasmMemory["buffer"], start, length);
  };

  Module["heapViewU16"] = function (start, length) {
    var wasmMemory = Module["wasmMemory"];
    if (!wasmMemory) {
      return new Uint16Array(Module["HEAPU8"]["buffer"], start, length);
    }
    return new Uint16Array(wasmMemory["buffer"], start, length);
  };

  Module["heapViewU32"] = function (start, length) {
    var wasmMemory = Module["wasmMemory"];
    if (!wasmMemory) {
      return new Uint32Array(Module["HEAPU8"]["buffer"], start, length);
    }
    return new Uint32Array(wasmMemory["buffer"], start, length);
  };

  Module["heapViewF32"] = function (start, length) {
    var wasmMemory = Module["wasmMemory"];
    if (!wasmMemory) {
      return new Float32Array(Module["HEAPF32"]["buffer"], start, length);
    }
    return new Float32Array(wasmMemory["buffer"], start, length);
  };

  Module["heapDataView"] = function (start, length) {
    var wasmMemory = Module["wasmMemory"];
    if (!wasmMemory) {
      return new DataView(Module["HEAPU8"]["buffer"], start, length);
    }
    return new DataView(wasmMemory["buffer"], start, length);
  };

  var scriptingWorkspaceResponse = Module["scriptingWorkspaceResponse"];
  Module["scriptingWorkspaceResponse"] = function (workspace, workId) {
    var response = scriptingWorkspaceResponse(workspace, workId);
    var available = response[0];
    var dataPtr = response[1];
    var size = response[2];
    var data = available ? Module["heapDataView"](dataPtr, size) : null;

    return {
      "available": available,
      "data": data,
    };
  };

  var riveLuaConsole = Module["riveLuaConsole"];
  Module["riveLuaConsole"] = function (state) {
    var response = riveLuaConsole(state);
    var dataPtr = response[0];
    var size = response[1];
    var data = Module["heapDataView"](dataPtr, size);

    return data;
  };

  var scriptingWorkspaceHighlightRow = Module["scriptingWorkspaceHighlightRow"];
  Module["scriptingWorkspaceHighlightRow"] = function (workspace, name, row) {
    var response = scriptingWorkspaceHighlightRow(workspace, name, row);
    var count = response[0];
    var dataPtr = response[1];
    var data = Module["heapViewU32"](dataPtr, count);

    return data;
  };

  var nativeFontBytes = Module["_nativeFontBytes"];
  Module["nativeFontBytes"] = function () {
    var dataPtr = nativeFontBytes();
    var count = Module["_nativeFontSize"]();
    return Module["heapViewU8"](dataPtr, count);
  };

  // initGPUScriptingGL and getGPURenderContextPtr removed — GL context handle,
  // ore context, and render context are now passed explicitly through
  // riveVMAdopt via the RenderTexture, eliminating global renderer tracking.

  // riveLuaPushCanvas / riveLuaPushGPUCanvas are now RIVE_FFI_EXPORT'd at their
  // definition sites, so EMSCRIPTEN_KEEPALIVE exports them as _riveLuaPush*.
  // The Dart-web layer accesses them without the leading underscore.
  Module["riveLuaPushCanvas"] = Module["_riveLuaPushCanvas"];
  Module["riveLuaPushGPUCanvas"] = Module["_riveLuaPushGPUCanvas"];
  Module["riveLuaContextBeginRenderPass"] =
    Module["_riveLuaContextBeginRenderPass"];

  // GL context switching and frame management are handled in C++ inside
  // riveGPUBeginFrameExport / riveGPUEndFrameExport (WASM-only wrappers).
  Module["riveGPUBeginFrame"] = Module["_riveGPUBeginFrameExport"];
  Module["riveGPUEndFrame"] = Module["_riveGPUEndFrameExport"];

  if (typeof Module["requestSerializedViewModelInstanceWasm"] === "function") {
    var requestSerializedViewModelInstanceWasm =
      Module["requestSerializedViewModelInstanceWasm"];
    var freeViewModelInstanceSerializedDataWasm =
      Module["freeViewModelInstanceSerializedDataWasm"];
    Module["_requestSerializedViewModelInstance"] = function (
      filePtr,
      instancePtr,
    ) {
      var response = requestSerializedViewModelInstanceWasm(
        filePtr,
        instancePtr,
      );
      if (!response || response.size === 0) {
        return null;
      }
      var bytes = Module["heapViewU8"](response.data, response.size);
      var copy = Array.from(bytes);
      freeViewModelInstanceSerializedDataWasm(response);
      return copy;
    };
  }
};
