#!/bin/bash
# ============================================================
# Compile Box64 source files directly for iOS ARM64
# Creates libbox64_all.a from all Box64 .c source files
# ============================================================
set -e

BOX64_SRC="${1:?Usage: $0 <box64-source-dir> <output-dir>}"
OUTPUT_DIR="${2:?Usage: $0 <box64-source-dir> <output-dir>}"

echo "========================================"
echo "  Direct Box64 Compilation for iOS"
echo "  Source: $BOX64_SRC"
echo "  Output: $OUTPUT_DIR"
echo "========================================"

SDK=$(xcrun --sdk iphoneos --show-sdk-path)
CC=$(xcrun --sdk iphoneos --find clang)

# Compat headers MUST be first so our Linux stubs override missing system headers
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
COMPAT_DIR="$SCRIPT_DIR/../GameHub/Native/Compat"

CFLAGS="-arch arm64 -mios-version-min=16.0 -isysroot $SDK -O2 -fembed-bitcode-marker"
CFLAGS="$CFLAGS -DARM64 -DDYNAREC -DNOGIT -D__IOS__=1 -DTARGET_IPHONE=1"
CFLAGS="$CFLAGS -DBAD_SIGNAL=1 -D_MAP_JIT=1 -DBOX64_ENV=1"
CFLAGS="$CFLAGS -I$COMPAT_DIR -I$BOX64_SRC/src/include -I$BOX64_SRC/src"
CFLAGS="$CFLAGS -Wno-unused-variable -Wno-unused-function -Wno-incompatible-pointer-types"
CFLAGS="$CFLAGS -Wno-int-conversion -Wno-pointer-sign -Wno-implicit-function-declaration"
CFLAGS="$CFLAGS -Wno-deprecated-declarations -Wno-missing-declarations"

mkdir -p "$OUTPUT_DIR/objects"

# Find all C source files in Box64 core
echo "[1/3] Finding Box64 source files..."
SOURCES=""
for dir in src src/emu src/custommem src/os src/tools src/libtools src/dynarec src/dynarec/arm64; do
    if [ -d "$BOX64_SRC/$dir" ]; then
        for f in "$BOX64_SRC/$dir"/*.c; do
            [ -f "$f" ] && SOURCES="$SOURCES $f"
        done
    fi
done

# Also include wrapped library files
for dir in src/wrapped; do
    if [ -d "$BOX64_SRC/$dir" ]; then
        for f in "$BOX64_SRC/$dir"/*.c; do
            [ -f "$f" ] && SOURCES="$SOURCES $f"
        done
    fi
done

SRC_COUNT=$(echo $SOURCES | wc -w)
echo "  Found $SRC_COUNT source files"

# Compile each source file
echo "[2/3] Compiling $SRC_COUNT files..."
COMPILED=0
FAILED=0
FAILED_FILES=""

for src in $SOURCES; do
    BASENAME=$(basename "$src" .c)
    OBJ="$OUTPUT_DIR/objects/${BASENAME}.o"
    
    if $CC $CFLAGS -c "$src" -o "$OBJ" 2>/dev/null; then
        COMPILED=$((COMPILED + 1))
    else
        FAILED=$((FAILED + 1))
        FAILED_FILES="$FAILED_FILES $BASENAME"
    fi
    
    if [ $((COMPILED + FAILED)) -gt 0 ] && [ $((COMPILED + FAILED)) -eq 20 ] || \
       [ $((COMPILED + FAILED)) -eq 50 ] || [ $((COMPILED + FAILED)) -eq 100 ]; then
        echo "  Progress: $COMPILED compiled, $FAILED failed out of $((COMPILED + FAILED))"
    fi
done

echo "  Compiled: $COMPILED / $SRC_COUNT"
echo "  Failed: $FAILED"

if [ $COMPILED -eq 0 ]; then
    echo "ERROR: No files compiled!"
    exit 1
fi

# Create static library
echo "[3/3] Creating static library..."
cd "$OUTPUT_DIR/objects"
AR=$(xcrun --sdk iphoneos --find ar)
$AR rcs "$OUTPUT_DIR/libbox64.a" *.o

echo ""
echo "========================================"
echo "  Box64 compilation complete!"
echo "  Library: $OUTPUT_DIR/libbox64.a"
ls -la "$OUTPUT_DIR/libbox64.a"
echo "  Objects: $COMPILED"
if [ -n "$FAILED_FILES" ]; then
    echo "  Failed files:$FAILED_FILES"
fi
echo "========================================"
