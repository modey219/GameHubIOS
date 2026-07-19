#!/bin/bash
# ============================================================
# GameHub iOS - Build Box64 for iOS ARM64 as static library
# ============================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/build/box64_ios"
OUTPUT_DIR="$PROJECT_DIR/GameHub/Native/Box64Lib"
JOBS=$(sysctl -n hw.ncpu 2>/dev/null || echo 4)

echo "========================================"
echo "  Building Box64 for iOS ARM64"
echo "========================================"

# Step 1: Clone Box64
echo "[1/5] Cloning Box64 v0.4.2..."
if [ ! -d "$BUILD_DIR/box64" ]; then
    mkdir -p "$BUILD_DIR"
    git clone --depth 1 --branch v0.4.2 https://github.com/ptitSeb/box64.git "$BUILD_DIR/box64"
fi

# Step 2: Patch for iOS
echo "[2/5] Patching Box64 for iOS cross-compilation..."
cd "$BUILD_DIR/box64"

# Save original
cp CMakeLists.txt CMakeLists.txt.orig

# Patch 1: Add iOS support in the platform check (skip the "not Linux" error)
# Box64 checks: if(NOT ANDROID AND NOT TERMUX) then it expects Linux
sed -i '' 's/if(NOT ANDROID AND NOT TERMUX)/if(NOT ANDROID AND NOT TERMUX AND NOT IOS)/' CMakeLists.txt

# Patch 2: Skip the binary install check for cross-compilation
sed -i '' 's/install(TARGETS box64 DESTINATION ${CMAKE_INSTALL_PREFIX}\/bin)/# install skipped for cross-compilation/' CMakeLists.txt

# Patch 3: For iOS, we build a static library, not an executable
# Add after the add_executable(box64 ...) line, add a static lib target
cat >> CMakeLists.txt << 'PATCHEOF'

# iOS: Build as static library instead of executable
if(IOS)
    message(STATUS "Building Box64 as static library for iOS")
    # Collect all object files from the box64 executable
    get_target_property(BOX64_SOURCES box64 SOURCES)
    # Create static library from the executable's objects
    add_library(box64_ios STATIC)
    target_sources(box64_ios PRIVATE ${BOX64_SOURCES})
    target_include_directories(box64_ios PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/src/include
        ${CMAKE_CURRENT_SOURCE_DIR}/src
        ${CMAKE_CURRENT_SOURCE_DIR}/src/wrapped
        ${CMAKE_CURRENT_SOURCE_DIR}/src/wrapped/generated
        ${CMAKE_CURRENT_SOURCE_DIR}/src/custommem
        ${CMAKE_CURRENT_SOURCE_DIR}/src/emu
        ${CMAKE_CURRENT_SOURCE_DIR}/src/tools
        ${CMAKE_CURRENT_SOURCE_DIR}/src/libtools
        ${CMAKE_CURRENT_SOURCE_DIR}/src/os
    )
    target_compile_definitions(box64_ios PRIVATE
        ARM64 NOGIT
        _GNU_SOURCE
        __ILP32__=0
        BOX64_ENV=1
        HAVE_CLOCK_GETTIME=1
        HAVE_STRTOLD_L=1
        __USE_MISC=1
    )
    target_link_libraries(box64_ios PRIVATE "-framework Foundation" "-framework Metal")
    install(TARGETS box64_ios ARCHIVE DESTINATION lib)
endif()
PATCHEOF

# Step 3: Configure with CMake for iOS
echo "[3/5] Configuring Box64 with CMake for iOS..."
mkdir -p "$BUILD_DIR/build_ios"
cd "$BUILD_DIR/build_ios"

cmake "$BUILD_DIR/box64" \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_SYSTEM_PROCESSOR=aarch64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=16.0 \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_SYSROOT=iphoneos \
    -DCMAKE_XCODE_ATTRIBUTE_ONLY_ACTIVE_ARCH=NO \
    -DCMAKE_C_FLAGS="-arch arm64 -mios-version-min=16.0 -fembed-bitcode-marker -O2" \
    -DCMAKE_CXX_FLAGS="-arch arm64 -mios-version-min=16.0 -fembed-bitcode-marker -O2" \
    -DARM64=ON \
    -DBAD_SIGNAL=ON \
    -DNOGIT=ON \
    -DBUILD_TESTING=OFF \
    -DBUILD_SHARED_LIBS=OFF \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$BUILD_DIR/output" \
    2>&1 | tee "$BUILD_DIR/cmake.log" || {
        echo "CMake configuration failed, trying alternative approach..."
        # Alternative: compile all .c files directly
        cd "$BUILD_DIR"
        "$SCRIPT_DIR/compile_box64_direct.sh" "$BUILD_DIR/box64" "$OUTPUT_DIR"
        exit $?
    }

# Step 4: Build
echo "[4/5] Building Box64 (this may take 10-20 minutes)..."
make -j"$JOBS" 2>&1 | tee "$BUILD_DIR/make.log" || {
    echo "Make failed, trying direct compilation..."
    cd "$BUILD_DIR"
    "$SCRIPT_DIR/compile_box64_direct.sh" "$BUILD_DIR/box64" "$OUTPUT_DIR"
    exit $?
}

# Step 5: Copy outputs
echo "[5/5] Copying outputs..."
mkdir -p "$OUTPUT_DIR"

# Find and copy .a files
find "$BUILD_DIR/build_ios" -name "*.a" -exec cp {} "$OUTPUT_DIR/" \;

# Also find .o files if .a creation failed
if [ ! -f "$OUTPUT_DIR/libbox64.a" ]; then
    echo "No .a files found, collecting .o files..."
    mkdir -p "$OUTPUT_DIR/objects"
    find "$BUILD_DIR/build_ios" -name "*.o" -exec cp {} "$OUTPUT_DIR/objects/" \;
fi

echo "========================================"
echo "  Box64 build complete!"
echo "  Output: $OUTPUT_DIR"
ls -la "$OUTPUT_DIR/"
echo "========================================"
