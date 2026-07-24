#!/bin/bash
# ============================================================
# GameHub iOS - Master Build Script
# Builds all components: Box64, Wine, MoltenVK, DXVK
# ============================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/build"

echo "========================================"
echo "  GameHub iOS - Master Build Script"
echo "========================================"
echo ""
echo "This script will build all components needed"
echo "for running PC games on iOS."
echo ""
echo "Components:"
echo "  - Box64 (x86_64 → ARM64 translation)"
echo "  - Wine (Windows API implementation)"
echo "  - MoltenVK (Vulkan → Metal translation)"
echo "  - DXVK (DirectX 11 → Vulkan)"
echo "  - VKD3D (DirectX 12 → Vulkan)"
echo ""
echo "Estimated build time: 30-60 minutes"
echo ""

# Check if running on macOS
if [[ "$OSTYPE" != "darwin"* ]]; then
    echo "[!] This script must be run on macOS"
    echo "    For other platforms, use Docker or a VM"
    exit 1
fi

# Check for Xcode
if ! command -v xcodebuild &> /dev/null; then
    echo "[!] Xcode not found. Please install Xcode from the App Store"
    exit 1
fi

# Create build directory
mkdir -p "$BUILD_DIR"

# Build order matters!
echo "========================================"
echo "  Step 1/4: Building Box64"
echo "========================================"
bash "$SCRIPT_DIR/build_box64.sh"

echo ""
echo "========================================"
echo "  Step 2/4: Building Wine"
echo "========================================"
bash "$SCRIPT_DIR/build_wine.sh"

echo ""
echo "========================================"
echo "  Step 3/4: Building Graphics Stack"
echo "========================================"
bash "$SCRIPT_DIR/build_graphics.sh"

echo ""
echo "========================================"
echo "  Step 4/4: Packaging for Xcode"
echo "========================================"

# Copy binaries to Xcode project
XCODE_RESOURCES="$PROJECT_DIR/GameHub/Resources"

echo "[*] Copying binaries to Xcode project..."
cp "$BUILD_DIR/box64" "$XCODE_RESOURCES/box64" 2>/dev/null || true
cp "$BUILD_DIR/sysroot/usr/bin/wine64" "$XCODE_RESOURCES/wine64" 2>/dev/null || true
cp -r "$BUILD_DIR/sysroot/lib/MoltenVK.framework" "$XCODE_RESOURCES/" 2>/dev/null || true

# Create rootfs archive
echo "[*] Creating rootfs archive..."
cd "$BUILD_DIR/sysroot"
tar --zstd -cf "$XCODE_RESOURCES/rootfs.tzst" . 2>/dev/null || true

echo ""
echo "========================================"
echo "  Build Complete!"
echo "========================================"
echo ""
echo "Next steps:"
echo "  1. Open GameHub.xcodeproj in Xcode"
echo "  2. Select your iOS device as target"
echo "  3. Set your Development Team in Signing"
echo "  4. Build and Run"
echo ""
echo "For JIT support:"
echo "  - Install StikDebug from App Store"
echo "  - Open StikDebug and enable JIT for GameHub"
echo "  - Return to GameHub and start playing!"
echo ""
echo "========================================"
