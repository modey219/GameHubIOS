#!/bin/bash
# ============================================================
# GameHub iOS - MoltenVK Build Script
# Builds MoltenVK for iOS (Vulkan → Metal translation)
# ============================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/build"
SYSROOT="$BUILD_DIR/sysroot"

MOLTENVK_REPO="https://github.com/nicoboss/MoltenVK.git"
MOLTENVK_BRANCH="master"

echo "========================================"
echo "  GameHub iOS - MoltenVK Build Script"
echo "========================================"

# Clone MoltenVK
clone_moltenvk() {
    echo "[*] Cloning MoltenVK..."
    
    if [ -d "$BUILD_DIR/MoltenVK" ]; then
        echo "[*] MoltenVK source exists, updating..."
        cd "$BUILD_DIR/MoltenVK"
        git pull
        cd "$SCRIPT_DIR"
    else
        git clone --depth 1 -b "$MOLTENVK_BRANCH" "$MOLTENVK_REPO" "$BUILD_DIR/MoltenVK"
    fi
    
    echo "[+] MoltenVK source ready"
}

# Build MoltenVK for iOS
build_moltenvk() {
    echo "[*] Building MoltenVK for iOS (arm64)..."
    
    cd "$BUILD_DIR/MoltenVK"
    
    # Build using MoltenVK's build system
    ./fetchDependencies --macos --ios
    
    xcodebuild \
        -project MoltenVK/MoltenVK.xcodeproj \
        -scheme "MoltenVK (iOS)" \
        -configuration Release \
        -sdk iphoneos \
        -arch arm64 \
        SYMROOT="$BUILD_DIR/MoltenVK/build" \
        BUILD_DIR="$BUILD_DIR/MoltenVK/build" \
        2>&1 | tee "$BUILD_DIR/moltenvk_build.log"
    
    # Copy built framework
    cp -r "$BUILD_DIR/MoltenVK/build/Release-iphoneos/MoltenVK.framework" \
          "$SYSROOT/lib/"
    
    echo "[+] MoltenVK built successfully!"
}

# Build DXVK for iOS (DirectX → Vulkan)
build_dxvk() {
    echo "[*] Building DXVK..."
    
    if [ -d "$BUILD_DIR/dxvk" ]; then
        cd "$BUILD_DIR/dxvk"
        git pull
    else
        git clone --depth 1 https://github.com/doitsujin/dxvk.git "$BUILD_DIR/dxvk"
    fi
    
    cd "$BUILD_DIR/dxvk"
    
    # Cross-compile DXVK for ARM64
    meson setup build-ios \
        --cross-file cross-ios.txt \
        --buildtype=release \
        -Denable_dxgi=true \
        -Denable_d3d11=true \
        -Denable_d3d10=true \
        -Denable_d3d9=true \
        2>&1 | tee "$BUILD_DIR/dxvk_build.log"
    
    ninja -C build-ios 2>&1 | tee -a "$BUILD_DIR/dxvk_build.log"
    
    # Copy DXVK DLLs to Wine prefix
    mkdir -p "$SYSROOT/lib/dxvk"
    cp build-ios/src/dxgi/dxgi.dll "$SYSROOT/lib/dxvk/"
    cp build-ios/src/d3d11/d3d11.dll "$SYSROOT/lib/dxvk/"
    cp build-ios/src/d3d10/d3d10.dll "$SYSROOT/lib/dxvk/"
    cp build-ios/src/d3d9/d3d9.dll "$SYSROOT/lib/dxvk/"
    
    echo "[+] DXVK built successfully!"
}

# Build VKD3D for iOS (DirectX 12 → Vulkan)
build_vkd3d() {
    echo "[*] Building VKD3D..."
    
    if [ -d "$BUILD_DIR/vkd3d" ]; then
        cd "$BUILD_DIR/vkd3d"
        git pull
    else
        git clone --depth 1 https://github.com/wine-mirror/vkd3d.git "$BUILD_DIR/vkd3d"
    fi
    
    cd "$BUILD_DIR/vkd3d"
    
    meson setup build-ios \
        --cross-file cross-ios.txt \
        --buildtype=release \
        -Denable_tests=false \
        2>&1 | tee "$BUILD_DIR/vkd3d_build.log"
    
    ninja -C build-ios 2>&1 | tee -a "$BUILD_DIR/vkd3d_build.log"
    
    mkdir -p "$SYSROOT/lib/vkd3d"
    cp build-ios/libs/vkd3d/libvkd3d-12.dll "$SYSROOT/lib/vkd3d/"
    cp build-ios/libs/vkd3d/libvkd3d-shader-1.dll "$SYSROOT/lib/vkd3d/"
    
    echo "[+] VKD3D built successfully!"
}

# Main
main() {
    clone_moltenvk
    build_moltenvk
    build_dxvk
    build_vkd3d
    
    echo ""
    echo "========================================"
    echo "  Graphics stack build complete!"
    echo "  MoltenVK: $SYSROOT/lib/MoltenVK.framework"
    echo "  DXVK: $SYSROOT/lib/dxvk/"
    echo "  VKD3D: $SYSROOT/lib/vkd3d/"
    echo "========================================"
}

main "$@"
