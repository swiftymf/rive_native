import 'package:rive_native/rive_native.dart' show RenderTexture;

/// VM stand-ins so `@TestOn('browser')` files still compile on the VM
/// (web tests are compiled before `@TestOn` filtering).
int liveGLContextCount() =>
    throw UnsupportedError('liveGLContextCount is web-only');

void debugLoseWebGLContext(RenderTexture? texture) =>
    throw UnsupportedError('debugLoseWebGLContext is web-only');

int get debugWebRenderTexturePoolCap =>
    throw UnsupportedError('debugWebRenderTexturePoolCap is web-only');

Future<void> awaitWebGLHeadroom() =>
    throw UnsupportedError('awaitWebGLHeadroom is web-only');
