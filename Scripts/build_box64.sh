#!/bin/bash
# ============================================================
# GameHub iOS - Box64 Build Script
# Builds Box64 for iOS (arm64) with JIT support
# ============================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/build"
SYSROOT="$BUILD_DIR/sysroot"
TOOLCHAIN="$BUILD_DIR/toolchain"

BOX64_REPO="https://github.com/ptitSeb/box64.git"
BOX64_BRANCH="main"

echo "========================================"
echo "  GameHub iOS - Box64 Build Script"
echo "========================================"

# Check for required tools
check_dependencies() {
    echo "[*] Checking dependencies..."
    
    if ! command -v cmake &> /dev/null; then
        echo "[!] cmake not found. Installing via Homebrew..."
        brew install cmake
    fi
    
    if ! command -v git &> /dev/null; then
        echo "[!] git not found. Please install Xcode Command Line Tools."
        exit 1
    fi
    
    echo "[+] Dependencies OK"
}

# Clone Box64 source
clone_box64() {
    echo "[*] Cloning Box64..."
    
    if [ -d "$BUILD_DIR/box64" ]; then
        echo "[*] Box64 source exists, updating..."
        cd "$BUILD_DIR/box64"
        git pull
        cd "$SCRIPT_DIR"
    else
        git clone --depth 1 -b "$BOX64_BRANCH" "$BOX64_REPO" "$BUILD_DIR/box64"
    fi
    
    echo "[+] Box64 source ready"
}

# Patch Box64 for iOS JIT support
patch_box64() {
    echo "[*] Patching Box64 for iOS..."
    
    cd "$BUILD_DIR/box64"
    
    # Enable iOS-specific patches
    cat > ios_patch.cmake << 'EOF'
# iOS JIT Support for Box64

# Enable MAP_JIT for Apple platforms
add_definitions(-DMAP_JIT)
add_definitions(-DHAVE_MACH_O)
add_definitions(-D__APPLE__)
add_definitions(-DTARGET_IPHONE)

# Use pthread_jit_write_protect_np for JIT
add_definitions(-DJIT_WRITE_PROTECT)

# Disable banned instructions on iOS (use software fallback)
add_definitions(-DNOBANNED=1)

# Enable dynamic recompilation
add_definitions(-DDYNAREC)

# iOS memory mapping
add_definitions(-DMEM_MAP_SIZE=0x10000000)
EOF
    
    echo "[+] Box64 patched"
}

# Build Box64 for iOS
build_box64() {
    echo "[*] Building Box64 for iOS (arm64)..."
    
    cd "$BUILD_DIR/box64"
    mkdir -p build_ios
    cd build_ios
    
    cmake .. \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_SYSTEM_NAME=iOS \
        -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0 \
        -DCMAKE_OSX_ARCHITECTURES=arm64 \
        -DCMAKE_XCODE_ATTRIBUTE_ONLY_ACTIVE_ARCH=NO \
        -DBUILD_SHARED_LIBS=OFF \
        -DARM_DYNAREC=ON \
        -DBAD_SIGNAL=ON \
        -DBUILD_TESTING=OFF \
        -DCMAKE_INSTALL_PREFIX="$SYSROOT" \
        -DCMAKE_C_FLAGS="-arch arm64 -mios-version-min=15.0 -fembed-bitcode" \
        -DCMAKE_CXX_FLAGS="-arch arm64 -mios-version-min=15.0 -fembed-bitcode" \
        2>&1 | tee "$BUILD_DIR/box64_build.log"
    
    make -j$(sysctl -n hw.ncpu) 2>&1 | tee -a "$BUILD_DIR/box64_build.log"
    
    # Install to sysroot
    make install 2>&1 | tee -a "$BUILD_DIR/box64_build.log"
    
    echo "[+] Box64 built successfully!"
}

# Create Box64 wrapper for iOS
create_wrapper() {
    echo "[*] Creating Box64 wrapper..."
    
    cat > "$BUILD_DIR/box64_wrapper.sh" << 'WRAPPER'
#!/bin/bash
# Box64 iOS Wrapper Script

# Set up Box64 environment
export BOX64_DYNAREC=1
export BOX64_DYNAREC_BIGBLOCK=1
export BOX64_DYNAREC_STRONGMEM=1
export BOX64_DYNAREC_SAFEFLAGS=1
export BOX64_DYNAREC_CALLRET=1
export BOX64_DYNAREC_DIRTY=1
export BOX64_NOBANNED=1
export BOX64_LD_LIBRARY_PATH="/usr/lib"

# JIT configuration for iOS
export BOX64_JIT_WRITE_PROTECT=1
export BOX64_MMAP_JIT=1

# Execute the target binary
exec "$@"
WRAPPER
    
    chmod +x "$BUILD_DIR/box64_wrapper.sh"
    
    echo "[+] Wrapper created"
}

# Main
main() {
    check_dependencies
    clone_box64
    patch_box64
    build_box64
    create_wrapper
    
    echo ""
    echo "========================================"
    echo "  Box64 build complete!"
    echo "  Binary: $SYSROOT/bin/box64"
    echo "========================================"
}

main "$@"
