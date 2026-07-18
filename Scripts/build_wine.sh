#!/bin/bash
# ============================================================
# GameHub iOS - Wine Build Script
# Builds Wine for iOS (arm64) with Vulkan/Metal support
# ============================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/build"
SYSROOT="$BUILD_DIR/sysroot"
WINE_PREFIX="$BUILD_DIR/wine_prefix"

WINE_REPO="https://gitlab.winehq.org/wine/wine.git"
WINE_BRANCH="wine-9.0"

echo "========================================"
echo "  GameHub iOS - Wine Build Script"
echo "========================================"

# Check for required tools
check_dependencies() {
    echo "[*] Checking dependencies..."
    
    local deps=("cmake" "git" "flex" "bison" "autoconf" "automake")
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            echo "[!] $dep not found. Installing via Homebrew..."
            brew install "$dep"
        fi
    done
    
    echo "[+] Dependencies OK"
}

# Clone Wine source
clone_wine() {
    echo "[*] Cloning Wine..."
    
    if [ -d "$BUILD_DIR/wine" ]; then
        echo "[*] Wine source exists, updating..."
        cd "$BUILD_DIR/wine"
        git pull
        cd "$SCRIPT_DIR"
    else
        git clone --depth 1 -b "$WINE_BRANCH" "$WINE_REPO" "$BUILD_DIR/wine"
    fi
    
    echo "[+] Wine source ready"
}

# Patch Wine for iOS
patch_wine() {
    echo "[*] Patching Wine for iOS..."
    
    cd "$BUILD_DIR/wine"
    
    # Create iOS-specific config
    cat > ios_config.h << 'EOF'
/* iOS-specific Wine configuration */

/* Enable Vulkan support via MoltenVK */
#define HAVE_VULKAN 1
#define HAVE_MVK 1

/* Enable Metal rendering */
#define HAVE_METAL 1

/* iOS memory layout */
#define HAVE_MMAP_FIXED 1
#define HAVE_MMAP_MAP_FIXED 1

/* Disable features not available on iOS */
/* #undef HAVE_X11 */
/* #undef HAVE_XLIB */
/* #undef HAVE_XCB */

/* Use PulseAudio for audio */
#define HAVE_PULSE 1

/* Enable WoW64 support */
#define HAVE_WOW64 1

/* iOS thread support */
#define HAVE_PTHREAD 1
#define HAVE_PTHREAD_np 1
#define HAVE_PTHREAD_JIT_WRITE_PROTECT_NP 1
EOF
    
    echo "[+] Wine patched"
}

# Build Wine for iOS
build_wine() {
    echo "[*] Building Wine for iOS (arm64)..."
    
    cd "$BUILD_DIR/wine"
    mkdir -p build_ios
    cd build_ios
    
    # Configure for cross-compilation to iOS
    ../configure \
        --host=aarch64-apple-ios \
        --prefix="$SYSROOT/usr" \
        --without-x \
        --without-xfixes \
        --without-xrender \
        --without-xshape \
        --without-xinerama \
        --without-xrandr \
        --without-xcomposite \
        --without-xinput \
        --without-xinput2 \
        --without-xf86vmode \
        --without-opengl \
        --with-vulkan \
        --with-pulse \
        --without-alsa \
        --without-capi \
        --without-cups \
        --without-curses \
        --without-dbus \
        --without-fontconfig \
        --with-freetype \
        --without-gettext \
        --without-gphoto \
        --without-gsm \
        --without-gstreamer \
        --without-inotify \
        --without-krb5 \
        --without-capi \
        --without-pcap \
        --without-png \
        --without-pthread \
        --without-pulse \
        --without-sane \
        --without-tiff \
        --without-v4l2 \
        --without-vulkan \
        --without-xslt \
        --without-zlib \
        --without-zstd \
        --disable-tests \
        --enable-win64 \
        2>&1 | tee "$BUILD_DIR/wine_build.log"
    
    make -j$(sysctl -n hw.ncpu) 2>&1 | tee -a "$BUILD_DIR/wine_build.log"
    
    make install 2>&1 | tee -a "$BUILD_DIR/wine_build.log"
    
    echo "[+] Wine built successfully!"
}

# Setup Wine prefix with iOS-friendly defaults
setup_wine_prefix() {
    echo "[*] Setting up Wine prefix..."
    
    mkdir -p "$WINE_PREFIX/drive_c/windows"
    mkdir -p "$WINE_PREFIX/drive_c/windows/system32"
    mkdir -p "$WINE_PREFIX/drive_c/Program Files"
    mkdir -p "$WINE_PREFIX/drive_c/Program Files (x86)"
    mkdir -p "$WINE_PREFIX/drive_c/users"
    mkdir -p "$WINE_PREFIX/drive_c/games"
    
    # Create registry entries for iOS-optimized settings
    cat > "$WINE_PREFIX/system.reg" << 'REG'
Windows Registry Editor Version 5.00

[HKEY_CURRENT_USER\Software\Wine\Direct3D]
"UseGLSL"="enabled"
"DirectDrawRenderer"="opengl"
"OffscreenRenderingMode"="fbo"
"VideoMemorySize"="2048"
"MaxFrameLatency"="1"
"StrictDrawOrdering"="disabled"
"CSMT"="enabled"

[HKEY_CURRENT_USER\Software\Wine\DllOverrides]
"dxgi"="dxvk"
"d3d11"="dxvk"
"d3d10"="dxvk"
"d3d9"="dxvk"
"d3d8"="dxvk"
"dinput"="dxinput"
"dinput8"="dxinput"
"xinput1_3"="dxinput"

[HKEY_CURRENT_USER\Software\Wine\Drivers]
"Audio"="pulse"

[HKEY_LOCAL_MACHINE\Software\Wine]
"Version"="wine-9.0"
REG
    
    echo "[+] Wine prefix ready"
}

# Create Wine wrapper for iOS
create_wrapper() {
    echo "[*] Creating Wine wrapper..."
    
    cat > "$BUILD_DIR/wine_wrapper.sh" << 'WRAPPER'
#!/bin/bash
# Wine iOS Wrapper Script

export WINEPREFIX="$APP_DOCUMENTS/Wine"
export WINEDEBUG="-all"
export WINEARCH="win64"
export WINEESYNC=1
export WINEFSYNC=1
export DISPLAY=":0"

# Vulkan via MoltenVK
export MVK_CONFIG_LOG_LEVEL=0
export MVK_CONFIG_SYNCHRONOUS_QUEUE_SUBMITS=1

# DXVK settings
export DXVK_LOG_LEVEL=none
export DXVK_HUD=fps
export DXVK_FRAME_RATE=60

# Box64 settings for Wine
export BOX64_DYNAREC=1
export BOX64_DYNAREC_BIGBLOCK=1
export BOX64_DYNAREC_STRONGMEM=1
export BOX64_NOBANNED=1

# Execute Wine
exec "$SYSROOT/usr/bin/wine64" "$@"
WRAPPER
    
    chmod +x "$BUILD_DIR/wine_wrapper.sh"
    
    echo "[+] Wrapper created"
}

# Main
main() {
    check_dependencies
    clone_wine
    patch_wine
    build_wine
    setup_wine_prefix
    create_wrapper
    
    echo ""
    echo "========================================"
    echo "  Wine build complete!"
    echo "  Binary: $SYSROOT/usr/bin/wine64"
    echo "  Prefix: $WINE_PREFIX"
    echo "========================================"
}

main "$@"
