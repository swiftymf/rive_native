var previousInit = Module["onRuntimeInitialized"];
Module["onRuntimeInitialized"] = function () {
  previousInit();
  // We do some work here to connect our own messaging protocol between worker
  // threads and this main thread because emscripten_async_run_in_main_thread
  // and MAIN_THREAD_ASYNC_EM_ASM cause deadlocks.
  var scriptingCallbacks = (Module.scriptingWorkCallbacks = new Map());

  function listenToWorker(worker) {
    worker.addEventListener("message", function (event) {
      var data = event.data;
      var workspace = data.scriptingWorkspace;
      if (workspace) {
        var id = data.workId;
        var cb = scriptingCallbacks.get(workspace);
        if (cb) {
          cb(id);
        }
      }
    });
  }

  for (var k in PThread.unusedWorkers) {
    listenToWorker(PThread.unusedWorkers[k]);
  }
  for (var k in PThread.runningWorkers) {
    listenToWorker(PThread.runningWorkers[k]);
  }

  // For new workers allocate later.
  var loadWasmModuleToWorker = PThread.loadWasmModuleToWorker;
  PThread.loadWasmModuleToWorker = function (worker) {
    loadWasmModuleToWorker(worker);
    listenToWorker(worker);
  };
};
