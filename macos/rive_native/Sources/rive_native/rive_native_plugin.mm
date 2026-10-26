#import "rive_native_plugin.h"
#include "rive_native/external.hpp"
#include "rive_native/external_objc.h"
#include "rive_native/read_write_ring.hpp"
#import <MetalKit/MetalKit.h>

// rive_binding wants this defined
bool usePLS = true;

// Forward declaration for linker dummy function
void linkDummyMethods();

#pragma mark - RiveNativeRenderTexture

@interface RiveNativeRenderTexture ()
{
    CVMetalTextureCacheRef _metalTextureCache;
    CVMetalTextureRef _metalTextureCVRef[3];
@public
    id<MTLTexture> _metalTexture[3];
@public
    MTLRenderPassDescriptor* _passDescriptor[3];
    CVPixelBufferRef _pixelData[3];

    // Rive/C++ interop
    void* _riveRenderer;
    ReadWriteRing _readWriteRing;
}
@end

@implementation RiveNativeRenderTexture
- (instancetype)initWithDevice:(id<MTLDevice>)device
                    andContext:(void*)context
                      andQueue:(id<MTLCommandQueue>)commandQueue
                      andWidth:(int)width
                     andHeight:(int)height
                  registerWith:(NSObject<FlutterTextureRegistry>*)registry
{
    self = [super init];
    _riveRenderer = nullptr;
    if (self)
    {
        _width = width;
        _height = height;
        NSDictionary* options = @{
            // This key is required to generate SKPicture with CVPixelBufferRef
            // in metal.
            (NSString*)kCVPixelBufferMetalCompatibilityKey : @YES
        };
        CVReturn status = CVMetalTextureCacheCreate(
            kCFAllocatorDefault, nil, device, nil, &_metalTextureCache);
        if (status != kCVReturnSuccess)
        {
            NSLog(@"CVMetalTextureCacheCreate error %d", (int)status);
        }
        for (int i = 0; i < 3; i++)
        {
            status = CVPixelBufferCreate(kCFAllocatorDefault,
                                         width,
                                         height,
                                         kCVPixelFormatType_32BGRA,
                                         (__bridge CFDictionaryRef)options,
                                         &_pixelData[i]);
            if (status != kCVReturnSuccess)
            {
                NSLog(@"CVPixelBufferCreate error %d", (int)status);
            }

            status = CVMetalTextureCacheCreateTextureFromImage(
                kCFAllocatorDefault,
                _metalTextureCache,
                _pixelData[i],
                nil,
                MTLPixelFormatBGRA8Unorm,
                width,
                height,
                0,
                &_metalTextureCVRef[i]);
            if (status != kCVReturnSuccess)
            {
                NSLog(@"CVMetalTextureCacheCreateTextureFromImage error %d",
                      (int)status);
            }
            _metalTexture[i] = CVMetalTextureGetTexture(_metalTextureCVRef[i]);
            // make 3 of these...
            _passDescriptor[i] = [MTLRenderPassDescriptor renderPassDescriptor];
            _passDescriptor[i].colorAttachments[0].texture = _metalTexture[i];
            _passDescriptor[i].colorAttachments[0].loadAction =
                MTLLoadActionClear;
            _passDescriptor[i].colorAttachments[0].storeAction =
                MTLStoreActionStore;
            _passDescriptor[i].colorAttachments[0].clearColor =
                MTLClearColorMake(0.0, 0.0, 0.0, 0.0);
        }

        // Register with Flutter
        _flutterTextureId = [registry registerTexture:self];

        // --- Ownership boundary: pass retained pointers into C++ ---
        // These are used asynchronously by the renderer callbacks.
        // We transfer an extra retain into "CF/void* world" here.
        // The C++ side MUST CFRelease them.

        void* registry_retained = (__bridge_retained void*)registry;
        void* self_retained = (__bridge_retained void*)self;
        void* queue_bridged = (__bridge void*)commandQueue;
        void* tex0_bridged = (__bridge void*)_metalTexture[0];
        void* tex1_bridged = (__bridge void*)_metalTexture[1];
        void* tex2_bridged = (__bridge void*)_metalTexture[2];

        _riveRenderer = createRiveRenderer(
            registry_retained,
            context, // already a C pointer owned by C++ context
            self_retained,
            queue_bridged,
            &_readWriteRing,
            tex0_bridged,
            tex1_bridged,
            tex2_bridged,
            width,
            height);
        // NOTE: Do NOT CFRelease any of the *_retained pointers here.
        // Ownership is now shared between C++ and Obj-C
    }

    return self;
}

- (int64_t)flutterTextureId
{
    return _flutterTextureId;
}

// Explicitly break the C++ <-> Obj-C ownership by destroying the C++ renderer.
- (void)destroyRenderer
{
    riveLock();
    void* renderer = _riveRenderer;
    _riveRenderer = nullptr;
    if (renderer)
    {
        destroyRiveRenderer(renderer);
    }
    riveUnlock();
}

- (void)dealloc
{
    // Invalidate C++ renderer (it should stop scheduling callbacks once
    // destroyed)
    [self destroyRenderer];

    // Release CV/Metal resources
    for (int i = 0; i < 3; i++)
    {
        _passDescriptor[i] = nil;
        _metalTexture[i] = nil;
        if (_metalTextureCVRef[i])
        {
            CFRelease(_metalTextureCVRef[i]);
            _metalTextureCVRef[i] = nil;
        }
        if (_pixelData[i])
        {
            CVPixelBufferRelease(_pixelData[i]);
            _pixelData[i] = nil;
        }
    }
    if (_metalTextureCache)
    {
        CFRelease(_metalTextureCache);
        _metalTextureCache = nil;
    }
}

#pragma mark - FlutterTexture

- (CVPixelBufferRef)copyPixelBuffer
{
    int readIndex = _readWriteRing.currentRead();
    CVPixelBufferRef data = _pixelData[readIndex];
    CVBufferRetain(data);
    return data;
}

@end

#pragma mark - RiveNativePlugin

@interface RiveNativePlugin ()
{
    id<MTLDevice> _metalDevice;
    id<MTLCommandQueue> _metalCommandQueue;
    void* _riveRendererContext; // owned by C++ context
}
@property(nonatomic, strong) NSObject<FlutterTextureRegistry>* textureRegistry;
@property(nonatomic, strong)
    NSMutableDictionary<NSNumber*, RiveNativeRenderTexture*>* renderTextures;
@end

@implementation RiveNativePlugin

- (instancetype)initWithTextures:(NSObject<FlutterTextureRegistry>*)textures
{
    self = [super init];
    if (self)
    {
        _textureRegistry = textures;
        _renderTextures = [[NSMutableDictionary alloc] init];

        _metalDevice = MTLCreateSystemDefaultDevice();
        _metalCommandQueue = [_metalDevice newCommandQueue];

        // Pass device into C++ context. It will be used across frames.
        // Since the context stores/uses the device asynchronously, bridge as
        // retained. C++ must CFRelease in destroyRiveRendererContext(...).
        void* device_retained = (__bridge_retained void*)_metalDevice;
        _riveRendererContext = createRiveRendererContext(device_retained);

        setGPU((__bridge void*)_metalDevice,
               (__bridge void*)_metalCommandQueue);
    }
    return self;
}

- (void)dealloc
{
    riveLock();
    if (_riveRendererContext != nullptr)
    {
        destroyRiveRendererContext(_riveRendererContext);
        _riveRendererContext = nullptr;
    }
    // Clear global GPU pointers to avoid stale globals after teardown.
    setGPU(nullptr, nullptr);
    riveUnlock();

    // Explicitly release Metal resources in the correct order (queue before
    // device) to prevent the compiler-generated .cxx_destruct from releasing
    // them in declaration order (device first), which causes a use-after-free
    // in MTLResourceListPool when the queue's dealloc calls _purgeDevice on
    // an already-torn-down device.
    // https://github.com/rive-app/rive-flutter/issues/623
    _metalCommandQueue = nil;
    _metalDevice = nil;
}

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar
{
    FlutterMethodChannel* channel =
        [FlutterMethodChannel methodChannelWithName:@"rive_native"
                                    binaryMessenger:[registrar messenger]];

    auto riveNativePluginInstance =
        [[RiveNativePlugin alloc] initWithTextures:[registrar textures]];
    [registrar addMethodCallDelegate:riveNativePluginInstance channel:channel];

    linkDummyMethods();
}

#pragma mark - C callback into Obj-C (used by C++)

void preCommitCallback(id<MTLCommandBuffer> commandBuffer,
                       void* nativeRenderTexture,
                       void* renderer,
                       void* textureRegistry)
{
    // Retain the bridged CF pointers for the duration of the completion
    // handler to guarantee lifetime across async boundary.
    if (nativeRenderTexture)
    {
        CFRetain(nativeRenderTexture);
    }
    if (textureRegistry)
    {
        CFRetain(textureRegistry);
    }

    [commandBuffer addCompletedHandler:^(id<MTLCommandBuffer> _Nonnull cb) {
      @autoreleasepool
      {
          // Bridge to Obj-C references. CFRetain kept them alive until now.
          auto rt = (__bridge RiveNativeRenderTexture*)nativeRenderTexture;
          auto flutterTextureRegistry =
              (__bridge NSObject<FlutterTextureRegistry>*)textureRegistry;

          // Guard: renderer might have been destroyed during teardown.
          if (!rt || !flutterTextureRegistry)
          {
              if (nativeRenderTexture)
              {
                  CFRelease(nativeRenderTexture);
              }
              if (textureRegistry)
              {
                  CFRelease(textureRegistry);
              }
              return;
          }

          // Textures must be managed on the platform (main) thread
          // https://api.flutter.dev/ios-embedder/protocol_flutter_texture_registry-p.html
          // See issue:
          // https://github.com/flutter-webrtc/flutter-webrtc/issues/1914
          dispatch_async(dispatch_get_main_queue(), ^{
            riveLock();
            if (rt->_riveRenderer != nullptr)
            {
                rt->_readWriteRing.nextRead();
                [flutterTextureRegistry
                    textureFrameAvailable:[rt flutterTextureId]];
            }
            riveUnlock();

            // Release the temp retains now that we're done with Obj-C
            if (nativeRenderTexture)
            {
                CFRelease(nativeRenderTexture);
            }
            if (textureRegistry)
            {
                CFRelease(textureRegistry);
            }
          });
      }
    }];
}

#pragma mark - Flutter plugin API

- (void)handleMethodCall:(FlutterMethodCall*)call result:(FlutterResult)result
{
    if ([call.method isEqualToString:@"createTexture"])
    {
        NSNumber* width = call.arguments[@"width"];
        NSNumber* height = call.arguments[@"height"];
        if (width == nil || height == nil)
        {
            result([FlutterError
                errorWithCode:@"CreateTexture Error"
                      message:
                          @"Missing width/height in RiveNative.createTexture"
                      details:nil]);
            return;
        }

        RiveNativeRenderTexture* renderTexture =
            [[RiveNativeRenderTexture alloc] initWithDevice:_metalDevice
                                                 andContext:_riveRendererContext
                                                   andQueue:_metalCommandQueue
                                                   andWidth:width.intValue
                                                  andHeight:height.intValue
                                               registerWith:_textureRegistry];

        // Store strongly so lifetime outlives async GPU callbacks.
        _renderTextures[@(renderTexture.flutterTextureId)] = renderTexture;

        char buff[255];
        snprintf(buff, sizeof(buff), "%p", renderTexture->_riveRenderer);

        result(@{
            @"textureId" : @(renderTexture.flutterTextureId),
            @"renderer" : [NSString stringWithCString:buff
                                             encoding:NSUTF8StringEncoding],
        });

        return;
    }

    if ([call.method isEqualToString:@"getRenderContext"])
    {
        char buff[255];
        snprintf(buff,
                 sizeof(buff),
                 "%p",
                 factoryFromRiveRendererContext(_riveRendererContext));

        result(@{
            @"rendererContext" :
                [NSString stringWithCString:buff encoding:NSUTF8StringEncoding]
        });
        return;
    }

    if ([call.method isEqualToString:@"removeTexture"])
    {
        NSNumber* texId = call.arguments[@"id"];
        if (texId == nil)
        {
            result([FlutterError
                errorWithCode:@"removeTexture Error"
                      message:@"Missing id in RiveNative.removeTexture"
                      details:nil]);
            return;
        }

        RiveNativeRenderTexture* texture = _renderTextures[texId];
        if (texture)
        {
            // Break C++/Obj-C ownership before unregistering to avoid retain
            // cycles and to ensure command buffer callbacks won't outlive
            // the texture wrapper.
            [texture destroyRenderer];
            // Unregister first so Flutter stops asking for frames.
            [_textureRegistry unregisterTexture:texture.flutterTextureId];

            // Drop strong ref -> triggers -dealloc, which destroys the C++
            // renderer and (on the C++ side) CFReleases the retained bridged
            // pointers.
            [_renderTextures removeObjectForKey:texId];
        }

        result(nil);
        return;
    }

    result(FlutterMethodNotImplemented);
}
@end

#pragma mark - Link dummy methods

// Forward declarations for FFI functions that need force-linking.
// These are accessed via dlsym at runtime, so we reference them here
// to prevent the linker from stripping them from the static library.
extern "C"
{
    void* loadRiveFile(const void*, size_t, void*, void*);
    void deleteFlutterRenderer(void*);
    void rewindRenderPath(void*);
    void disposeYogaStyle(void*);
    void riveFontDummyLinker();
    void stopAudioSound(void*, uint64_t);
}

void linkDummyMethods()
{
    loadRiveFile(nullptr, 0, nullptr, nullptr);
    deleteFlutterRenderer(nullptr);
    rewindRenderPath(nullptr);
    disposeYogaStyle(nullptr);
    riveFontDummyLinker();
    stopAudioSound(nullptr, 0);
}