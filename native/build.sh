#!/bin/bash
set -e

CONFIG=debug
GRAPHICS=metal
COMPAT=
EXTRA_OUT=
KIND=
RIVE_AUDIO=system
RUNTIME=
WASM_SINGLE_THREADED=
CROSS_COMPILE_OS=
WITH_MICROPROFILE=

unameOut="$(uname -s)"
case "${unameOut}" in
Linux*) machine=linux ;;
Darwin*) machine=macosx ;;
MINGW*) machine=windows ;;
*) machine="unhandled:${unameOut}" ;;
esac
OS=$machine
VARIANT=system
NO_LTO=
RIVE_AUDIO=system

if [[ $OS == "windows" ]]; then
    if ! command -v msbuild.exe &>/dev/null; then
        SETUP_SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../runtime/build" && pwd)/setup_windows_dev.sh"
        if [ -f "$SETUP_SCRIPT" ]; then
            source "$SETUP_SCRIPT"
        else
            powershell "./build.ps1" $@
            exit $?
        fi
    fi
fi

if [[ $machine = "linux" ]]; then
    LOCAL_ARCH=$(uname -m)
    if [[ $LOCAL_ARCH == "aarch64" ]]; then
        LINUX_ARCH=arm64
    else
        LINUX_ARCH=x64
    fi
fi
# Default to build runtime for the Rive Editor
FLUTTER_RUNTIME=
RUNTIME_PATH="$PWD/../../runtime/build"

for var in "$@"; do
    if [[ $var = "release" ]]; then
        CONFIG=release
        ACTUAL_CONFIG=$CONFIG
    fi
    if [[ $var = "ios" ]]; then
        export IOS_SYSROOT=$(xcrun --sdk iphoneos --show-sdk-path)
        OS=ios
        CROSS_COMPILE_OS=ios
    fi
    if [[ $var = "emulator" ]]; then
        export IOS_SYSROOT=$(xcrun --sdk iphonesimulator --show-sdk-path)
        OS=ios
        CROSS_COMPILE_OS=ios
        VARIANT=emulator
    fi
    if [[ $var = "android" ]]; then
        OS=android
        CROSS_COMPILE_OS=android
    fi
    if [[ $var = "wasm" ]]; then
        OS=wasm
    fi
    if [[ $var = "single-threaded" ]]; then
        COMPAT=--single-threaded
        WASM_SINGLE_THREADED=true
    fi
    if [[ $var = "compatibility" ]]; then
        COMPAT="--no-wasm-simd --single-threaded"
        EXTRA_OUT=_compatibility
        WASM_SINGLE_THREADED=true
    fi
    if [[ $var = "shared" ]]; then
        KIND=--shared
        EXTRA_OUT=_shared
    fi
    if [[ $var = "flutter-runtime" ]]; then
        # Build runtime for Flutter package
        FLUTTER_RUNTIME=--flutter_runtime
        if [[ -d "$PWD/../runtime/build" ]]; then
            RUNTIME_PATH="$PWD/../runtime/build"
        fi
    fi
    if [[ $var = "no-lto" ]]; then
        NO_LTO=--no-lto
    fi

    if [[ $var = "no-audio" ]]; then
        RIVE_AUDIO=disabled
    fi
    if [[ $var = "asan" ]]; then
        ASAN=--with-asan
        # Use Xcode's clang for ASan so the runtime version matches the linker.
        export CC=/usr/bin/clang
        export CXX=/usr/bin/clang++
    fi
    if [[ $var = "microprofile" ]]; then
        WITH_MICROPROFILE=--with_microprofile
    fi
done

# Default debug builds to include microprofile support
if [[ -z $WITH_MICROPROFILE && $CONFIG = "debug" ]]; then
    WITH_MICROPROFILE=--with_microprofile
fi

if [[ $OS = "wasm" ]]; then
    NO_LTO=--no-lto
    if [[ ! -f "dependencies/bin/emsdk/emsdk_env.sh" ]]; then
        mkdir -p dependencies/bin
        pushd dependencies/bin
        # Pin the emsdk installer to the same release as the toolchain —
        # emsdk HEAD moves independently (e.g. it now requires Python 3.10+,
        # which breaks CI runners whose python3 is Xcode's 3.9).
        git clone --depth 1 --branch 3.1.70 https://github.com/emscripten-core/emsdk.git
        pushd emsdk
        ./emsdk install 3.1.70
        ./emsdk activate 3.1.70
        popd
        popd
    fi
    source ./dependencies/bin/emsdk/emsdk_env.sh
    # A RIVE_EMSDK_VERSION value of "none" tells build_rive.sh to just use
    # whatever emcc environment is already set up.
    export RIVE_EMSDK_VERSION=none
fi

if [[ $FLUTTER_RUNTIME = "" ]]; then
    # Building for the editor.
    # Requires cbindgen
    #   cargo install --force cbindgen
    #   rustup toolchain install nightly-2025-02-10
    #   rustup target add x86_64-apple-darwin
    #   rustup target add wasm32-unknown-emscripten
    #   rustup component add rust-src --toolchain nightly-2025-02-10-aarch64-apple-darwin
    # Regenerate C headers from Rust source if needed.
    # (Headers are committed; only regenerate when the Rust API changes.)
    pushd "../../scripting_workspace/formatter"
    if [[ ! -f stylua.h ]]; then
        cbindgen --config cbindgen.toml --output stylua.h
    fi
    popd
    pushd "../../scripting_workspace/naga_ffi"
    if [[ ! -f naga_ffi.h ]]; then
        cbindgen --config cbindgen.toml --output naga_ffi.h
    fi
    popd
    pushd "../../scripting_workspace/wgsl_analyzer_ffi"
    if [[ ! -f wgsl_analyzer_ffi.h ]]; then
        cbindgen --config cbindgen.toml --output wgsl_analyzer_ffi.h
    fi
    popd
    pushd "../../scripting_workspace/wgsl_formatter_ffi"
    if [[ ! -f wgsl_formatter_ffi.h ]]; then
        cbindgen --config cbindgen.toml --output wgsl_formatter_ffi.h
    fi
    popd

    # Build the combined rust_ffi crate (stylua + naga + wgsl_analyzer on
    # desktop) in one staticlib, sharing a single Rust runtime to avoid
    # duplicate symbol errors.
    pushd "../../scripting_workspace/rust_ffi"
    function build_rust_lib() {
        if [[ $OS = "wasm" ]] && [[ $WASM_SINGLE_THREADED = "" ]]; then
            RUSTFLAGS="--emit=llvm-ir -C target-feature=+atomics,+bulk-memory,+mutable-globals" cargo +nightly-2025-02-10 build --target $1 --profile minimize_web_threaded -Z build-std=std,panic_abort
        elif [[ $OS = "wasm" ]]; then
            RUSTFLAGS="--emit=llvm-ir -C target-feature=+atomics,+bulk-memory,+mutable-globals" cargo +nightly-2025-02-10 build --target $1 --profile minimize_web -Z build-std=std,panic_abort
        else
            # Desktop (macOS / Linux / Windows): enable wgsl_ide for
            # multi-error diagnostics, completions, and hover.
            if [[ $1 = "" ]]; then
                RUSTFLAGS="--emit=llvm-ir" cargo build --profile minimize --features wgsl_ide
            else
                RUSTFLAGS="--emit=llvm-ir" cargo build --target $1 --profile minimize --features wgsl_ide
            fi
        fi
    }

    if [[ $OS = "wasm" ]]; then
        export EMCC_CFLAGS="--no-entry -s ALLOW_MEMORY_GROWTH=1 -s WASM=1 -s ASSERTIONS=0 -s STRICT=1 -s WASM_BIGINT -Oz"
        if [[ $WASM_SINGLE_THREADED = "" ]]; then
            export EMCC_CFLAGS="$EMCC_CFLAGS  -pthread"
        fi
        build_rust_lib wasm32-unknown-emscripten
        export EMCC_CFLAGS=""
    elif [[ $OS = "macosx" ]]; then
        rustup target add x86_64-apple-darwin 2>/dev/null || true
        build_rust_lib aarch64-apple-darwin
        build_rust_lib x86_64-apple-darwin
    elif [[ $machine = "windows" ]]; then
        build_rust_lib x86_64-pc-windows-msvc
    elif [[ $machine = "linux" ]]; then
        if [[ $LINUX_ARCH == "arm64" ]]; then
            build_rust_lib aarch64-unknown-linux-gnu
        else
            build_rust_lib x86_64-unknown-linux-gnu
        fi
    else
        build_rust_lib
    fi
    popd
fi

for var in "$@"; do
    if [[ $var = "clean" ]]; then
        echo 'Cleaning...'
        rm -fR out
    fi
done

out_dir() {
    if [[ $2 == "wasm" ]]; then
        echo "out/$CONFIG/$2$EXTRA_OUT"
    else
        echo "out/$CONFIG/$1/$2$EXTRA_OUT"
    fi
}

if [[ $machine = "windows" ]]; then
    KIND=--shared
    EXTRA_OUT=_shared
fi

RIVE_TOOLS=
if [[ $FLUTTER_RUNTIME = "" ]]; then
    RIVE_TOOLS=--with_rive_tools
fi

# Software decoders for GPU-compressed textures (KTX2: ASTC/ETC2/BC). The
# editor's GPU backend can't decode every format (e.g. D3D has no ASTC/ETC2),
# so without these the runtime fails to render compressed textures instead of
# falling back to a software decode-to-RGBA. RIVE_KTX2 itself is already on by
# default (gated on `not no-rive-decoders`). Editor-only: the Flutter runtime
# doesn't need the software fallback, so gate on FLUTTER_RUNTIME like RIVE_TOOLS.
RIVE_DECODERS=
if [[ $FLUTTER_RUNTIME = "" ]]; then
    RIVE_DECODERS="--with_rive_astc_decoder --with_rive_bc_decoder --with_rive_etc_decoder"
fi

RIVE_NATIVE_PREMAKE_COMMANDS="$WITH_MICROPROFILE --with_rive_canvas --with_rive_scripting --with_objc_exceptions $RIVE_TOOLS --with_rive_text --with_rive_layout --with_rive_audio=$RIVE_AUDIO $CONFIG --variant=$VARIANT $COMPAT $KIND $FLUTTER_RUNTIME $NO_LTO $ASAN $CROSS_COMPILE_OS"

make_rive_native_plugin() {
    local BUILD_OS=$1
    local BUILD_ARCH=$2
    shift 2
    # The wasm target builds with --no-rive-decoders, which makes the decoders
    # premake script return early before it registers the --with_rive_*_decoder
    # options. Passing those flags there fails with "invalid option", so only
    # include the software decoders for non-wasm builds.
    local DECODERS=$RIVE_DECODERS
    if [[ $BUILD_ARCH == "wasm" ]]; then
        DECODERS=
    fi
    export RIVE_OUT="$(out_dir $BUILD_OS $BUILD_ARCH)"
    $RUNTIME_PATH/build_rive.sh $BUILD_ARCH $CONFIG $RIVE_NATIVE_PREMAKE_COMMANDS $DECODERS $@
}

rive_native_lipo_macosx() {
    ARCH_X64="$(out_dir macosx x64)"
    ARCH_ARM64="$(out_dir macosx arm64)"
    mkdir -p build/macosx/bin/$CONFIG$EXTRA_OUT
    lipo -create -arch arm64 $ARCH_ARM64/$1 -arch x86_64 $ARCH_X64/$1 -output build/macosx/bin/$CONFIG$EXTRA_OUT/$1
    du -hs build/macosx/bin/$CONFIG$EXTRA_OUT/$1
}

# Gen compile commands
if [[ $OS != "wasm" ]]; then
    $RUNTIME_PATH/build_rive.sh compdb $FLUTTER_RUNTIME $CROSS_COMPILE_OS --variant=$VARIANT
fi
# Generate project files.

if [[ $OS = "wasm" ]]; then
    # ninja does not track the emcc --pre-js/--post-js glue as a dependency of
    # rive_native.js, so a glue-only change leaves a stale link ("ninja: no
    # work to do"). Force the relink when the glue is newer than the output.
    WASM_OUT="out/$CONFIG/$OS$EXTRA_OUT"
    for glue in platform/wasm/init.js platform/wasm/scripting_work_callbacks.js platform/wasm/externs.js; do
        if [[ -f "$WASM_OUT/rive_native.js" && "$glue" -nt "$WASM_OUT/rive_native.js" ]]; then
            echo "wasm glue $glue changed; forcing relink"
            rm -f "$WASM_OUT/rive_native.js" "$WASM_OUT/rive_native.wasm"
            break
        fi
    done
    make_rive_native_plugin $machine wasm --no-rive-decoders
    if [[ -f "../../editor/web/index.html" ]]; then
        EDITOR_WEB=../../editor/web/$OS$EXTRA_OUT/
        mkdir -p $EDITOR_WEB
        cp out/$CONFIG/$OS$EXTRA_OUT/rive_native.js $EDITOR_WEB
        cp out/$CONFIG/$OS$EXTRA_OUT/rive_native.wasm $EDITOR_WEB
    fi
    mkdir -p wasm/$OS$EXTRA_OUT
    cp out/$CONFIG/$OS$EXTRA_OUT/rive_native.js wasm/$OS$EXTRA_OUT
    cp out/$CONFIG/$OS$EXTRA_OUT/rive_native.wasm wasm/$OS$EXTRA_OUT

elif [[ $OS = "android" ]]; then
    # arm
    make_rive_native_plugin android arm --shared
    OUT_DIR="$(out_dir android arm)"
    TARGET_DIR=../android/src/main/jniLibs/armeabi-v7a/
    mkdir -p $TARGET_DIR
    cp $OUT_DIR/librive_native.so $TARGET_DIR

    # arm64
    make_rive_native_plugin android arm64 --shared
    OUT_DIR="$(out_dir android arm64)"
    TARGET_DIR=../android/src/main/jniLibs/arm64-v8a
    mkdir -p $TARGET_DIR
    cp $OUT_DIR/librive_native.so $TARGET_DIR

    # x86
    make_rive_native_plugin android x86 --shared
    OUT_DIR="$(out_dir android x86)"
    TARGET_DIR=../android/src/main/jniLibs/x86/
    mkdir -p $TARGET_DIR
    cp $OUT_DIR/librive_native.so $TARGET_DIR

    # x86_64
    make_rive_native_plugin android x64 --shared
    OUT_DIR="$(out_dir android x64)"
    TARGET_DIR=../android/src/main/jniLibs/x86_64/
    mkdir -p $TARGET_DIR
    cp $OUT_DIR/librive_native.so $TARGET_DIR

    # To ensure that the android config does not overwrite the binaries by downloading them from our bucket
    touch ../android/rive_marker_android_development

elif [[ $machine = "linux" ]]; then
    # LTO doesn't work on linux right now (causes object files to not be recognized by the linker). Some versioning issue?
    make_rive_native_plugin $machine $LINUX_ARCH --with-pic --no-lto --raw_shaders
    if [[ $KIND = "--shared" ]]; then
        TARGET_DIR=../linux/bin/lib/$CONFIG$EXTRA_OUT
        mkdir -p $TARGET_DIR
        OUT_DIR="$(out_dir $machine $LINUX_ARCH)"
        cp $OUT_DIR/librive_native.so $TARGET_DIR
    else
        COPY_TO=../linux/bin/lib/$CONFIG
        rm -fR $COPY_TO
        mkdir -p $COPY_TO
        if [[ $FLUTTER_RUNTIME = "" ]]; then
            if [[ $LINUX_ARCH == "arm64" ]]; then
                cp ../../scripting_workspace/target/aarch64-unknown-linux-gnu/minimize/librust_ffi.a $(out_dir linux arm64)
            else
                cp ../../scripting_workspace/target/x86_64-unknown-linux-gnu/minimize/librust_ffi.a $(out_dir linux x64)
            fi
            # Only mark scripting support if the workspace lib actually has real
            # symbols (not just a dummy stub). Without the real lib,
            # riveLuaDummyLinker will be undefined at link time.
            SCRIPTING_LIB="$(out_dir $machine $LINUX_ARCH)/librive_scripting_workspace.a"
            if nm "$SCRIPTING_LIB" 2>/dev/null | grep -q riveLuaDummyLinker; then
                touch ../linux/rive_marker_linux_scripting
            else
                rm -f ../linux/rive_marker_linux_scripting
            fi
        else
            # Remove scripting marker if it exists from a previous editor build
            rm -f ../linux/rive_marker_linux_scripting
        fi
        cp -R $(out_dir $machine $LINUX_ARCH)/*.a $COPY_TO
        du -hs $COPY_TO/librive_native.a
        du -hs $COPY_TO/librive_harfbuzz.a
        du -hs $COPY_TO/librive_pls_renderer.a
        du -hs $COPY_TO/librive_sheenbidi.a
        du -hs $COPY_TO/librive_decoders.a
        du -hs $COPY_TO/librive_yoga.a
        du -hs $COPY_TO/librive.a
        du -hs $COPY_TO/liblibpng.a
        du -hs $COPY_TO/libzlib.a
        du -hs $COPY_TO/liblibjpeg.a
        du -hs $COPY_TO/liblibwebp.a
        du -hs $COPY_TO/librive_scripting_workspace.a
        du -hs $COPY_TO/libspirv_cross.a
        du -hs $COPY_TO/libluau_vm.a
        du -hs $COPY_TO/libluau_compiler.a
        du -hs $COPY_TO/libluau_analyzer.a
        du -hs $COPY_TO/librust_ffi.a
        du -hs $COPY_TO/libminiaudio.a
        du -hs $COPY_TO/libbrotli.a
    fi
    touch ../linux/rive_marker_linux_development
    # TARGET_DIR=../../rive_native/native/build/linux/bin/$CONFIG$EXTRA_OUT
    # mkdir -p $TARGET_DIR
    # echo "--> OUT DIR CONTAINS"
    # ls $OUT_DIR
    # cp $OUT_DIR/librive_native.so $TARGET_DIR
    # echo "--> TARGET DIR CONTAINS ($TARGET_DIR)"
    # ls $TARGET_DIR

elif [[ $machine = "macosx" ]]; then
    if [[ $OS = "ios" ]]; then
        make_rive_native_plugin ios universal

        OUT_DIR="$(out_dir ios universal)"
        TARGET_DIR=build/iphoneos/bin/
        if [[ $VARIANT = "emulator" ]]; then
            TARGET_DIR+="emulator"
        else
            TARGET_DIR+="$CONFIG"
        fi
        mkdir -p $TARGET_DIR
        cp $OUT_DIR/librive_native.a $TARGET_DIR
        cp $OUT_DIR/librive_harfbuzz.a $TARGET_DIR
        cp $OUT_DIR/librive_pls_renderer.a $TARGET_DIR
        cp $OUT_DIR/librive_sheenbidi.a $TARGET_DIR
        cp $OUT_DIR/libminiaudio.a $TARGET_DIR
        cp $OUT_DIR/librive_decoders.a $TARGET_DIR
        cp $OUT_DIR/librive.a $TARGET_DIR
        cp $OUT_DIR/librive_yoga.a $TARGET_DIR
        cp $OUT_DIR/liblibpng.a $TARGET_DIR
        cp $OUT_DIR/libzlib.a $TARGET_DIR
        cp $OUT_DIR/liblibjpeg.a $TARGET_DIR
        cp $OUT_DIR/liblibwebp.a $TARGET_DIR
        cp $OUT_DIR/librive_scripting_workspace.a $TARGET_DIR
        cp $OUT_DIR/libspirv_cross.a $TARGET_DIR
        cp $OUT_DIR/libluau_vm.a $TARGET_DIR
        cp $OUT_DIR/libluau_compiler.a $TARGET_DIR
        cp $OUT_DIR/libluau_analyzer.a $TARGET_DIR
        # stylua_ffi is not built for iOS (Rust doesn't have iOS target in build)
        # The formatter is stubbed out in scripting_workspace.cpp for iOS
        cp $OUT_DIR/libbrotli.a $TARGET_DIR

        # To ensure that the ios podspec file does not overwrite the binaries by downloading them from our bucket
        touch ../ios/rive_marker_ios_development

    else
        make_rive_native_plugin macosx x64
        make_rive_native_plugin macosx arm64

        if [[ $KIND = "--shared" ]]; then
            rive_native_lipo_macosx librive_native.dylib
        else
            if [[ $FLUTTER_RUNTIME = "" ]]; then
                # When building for the editor the stylua lib is the real one
                # built via the Rust toolchain. So we need to copy the static
                # libraries to let the rest of the system behave the same.
                cp ../../scripting_workspace/target/x86_64-apple-darwin/minimize/librust_ffi.a $(out_dir macosx x64)
                cp ../../scripting_workspace/target/aarch64-apple-darwin/minimize/librust_ffi.a $(out_dir macosx arm64)
                #else
                # When building for the flutter runtime our same premake config
                # builds stub stylua libs, so we have nothing else to do here.
            fi
            rive_native_lipo_macosx librive_native.a
            rive_native_lipo_macosx librive_harfbuzz.a
            rive_native_lipo_macosx librive_pls_renderer.a
            rive_native_lipo_macosx librive_sheenbidi.a
            rive_native_lipo_macosx libminiaudio.a
            rive_native_lipo_macosx librive_decoders.a
            rive_native_lipo_macosx librive.a
            rive_native_lipo_macosx librive_yoga.a
            rive_native_lipo_macosx liblibpng.a
            rive_native_lipo_macosx libzlib.a
            rive_native_lipo_macosx liblibjpeg.a
            rive_native_lipo_macosx liblibwebp.a
            rive_native_lipo_macosx librive_scripting_workspace.a
            rive_native_lipo_macosx libspirv_cross.a
            rive_native_lipo_macosx libluau_vm.a
            rive_native_lipo_macosx libluau_compiler.a
            rive_native_lipo_macosx libluau_analyzer.a
            rive_native_lipo_macosx librust_ffi.a
            rive_native_lipo_macosx libbrotli.a
            # Boolean path operations (real lib for the editor, dummy stub
            # in flutter_runtime builds -- same pattern as luau/rust_ffi).
            rive_native_lipo_macosx librive_pathops.a
            # To ensure that the macos podspec file does not overwrite the binaries by downloading them from our bucket
            touch ../macos/rive_marker_macos_development
        fi
    fi
elif [[ $machine = "windows" ]]; then
    if [[ $CONFIG = "debug" ]]; then
        # always build release on windows (comment this out if you need local debug)
        ACTUAL_CONFIG=release
        USE_DEFAULT_RUNTIME="--windows_runtime=dynamic_debug"
    else
        USE_DEFAULT_RUNTIME="--windows_runtime=dynamic"
    fi
    export RIVE_OUT=$(out_dir windows x64)

    $RUNTIME_PATH/build_rive.sh $ACTUAL_CONFIG x64 $FLUTTER_RUNTIME --variant=$VARIANT $USE_DEFAULT_RUNTIME $WITH_MICROPROFILE --with_rive_canvas --with_rive_scripting $RIVE_TOOLS $RIVE_DECODERS --with_rive_text --with_rive_layout --with_rive_audio=$RIVE_AUDIO --config=$ACTUAL_CONFIG --out=$(out_dir windows x64) --shared
    pushd $(out_dir windows x64)
    msbuild.exe rive.sln -m:$NUMBER_OF_PROCESSORS
    popd

    COPY_TO=../windows/bin/lib/$CONFIG
    rm -fR $COPY_TO
    mkdir -p $COPY_TO
    cp -R $(out_dir windows x64)/rive_native.lib $COPY_TO
    cp -R $(out_dir windows x64)/*.dll $COPY_TO
    cp -R $(out_dir windows x64)/*.pdb $COPY_TO

    du -hs $COPY_TO/rive_native.lib

    # To ensure that the windos cmakelist file does not overwrite the binaries by downloading them from our bucket
    touch ../windows/rive_marker_windows_development

fi