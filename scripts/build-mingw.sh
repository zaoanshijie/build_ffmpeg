#!/usr/bin/env bash
# Cross-build FFmpeg for Windows x86_64 using the llvm-mingw (clang) toolchain.
# Env required: PREFIX, SRC, MINGW_DIR
set -euo pipefail

PREFIX="${PREFIX:?PREFIX required}"
SRC="${SRC:?SRC required}"
MINGW_DIR="${MINGW_DIR:?MINGW_DIR required}"
JOBS="-j$(nproc)"

mkdir -p "$PREFIX" "$SRC"
export PATH="$MINGW_DIR/bin:$PATH"
export PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig"
export SYSROOT="$MINGW_DIR/x86_64-w64-mingw32"

# FFmpeg configure looks for the cross-prefixed pkg-config on win64 targets.
cat > "$MINGW_DIR/bin/x86_64-w64-mingw32-pkg-config" <<'EOF'
#!/bin/sh
exec /usr/bin/pkg-config "$@"
EOF
chmod +x "$MINGW_DIR/bin/x86_64-w64-mingw32-pkg-config"

export CC=x86_64-w64-mingw32-gcc
export CXX=x86_64-w64-mingw32-g++
export AR=x86_64-w64-mingw32-ar
export RANLIB=x86_64-w64-mingw32-ranlib
export STRIP=x86_64-w64-mingw32-strip
export NM=x86_64-w64-mingw32-nm
export WINDRES=x86_64-w64-mingw32-windres
export DLLTOOL=x86_64-w64-mingw32-dlltool

cd "$SRC"

log()  { echo; echo "############ $* ############"; }
fail() { echo "ERROR: $*"; exit 1; }

fetch_git() {
  local dir="$1" primary="$2" fallback="${3:-}"
  if [ -d "$dir/.git" ]; then return 0; fi
  if git clone --depth 1 --quiet "$primary" "$dir" 2>/dev/null; then return 0; fi
  if [ -n "$fallback" ]; then
    git clone --depth 1 --quiet "$fallback" "$dir"
  else
    fail "clone $primary"
  fi
}

# CMake toolchain file for Windows + llvm-mingw cross
cat > "$PREFIX/mingw-toolchain.cmake" <<EOF
set(CMAKE_SYSTEM_NAME Windows)
set(CMAKE_SYSTEM_PROCESSOR x86_64)
set(CMAKE_C_COMPILER $CC)
set(CMAKE_CXX_COMPILER $CXX)
set(CMAKE_RC_COMPILER $WINDRES)
set(CMAKE_AR $AR CACHE FILEPATH "" FORCE)
set(CMAKE_RANLIB $RANLIB CACHE FILEPATH "" FORCE)
set(CMAKE_STRIP $STRIP CACHE FILEPATH "" FORCE)
set(CMAKE_FIND_ROOT_PATH $MINGW_DIR $PREFIX)
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
EOF

build_x264() {
  log "Building x264 (mingw)"
  cd "$SRC"
  fetch_git x264 https://code.videolan.org/videolan/x264.git https://github.com/mirror/x264
  cd x264
  ./configure --prefix="$PREFIX" --host=x86_64-w64-mingw32 \
    --cross-prefix=x86_64-w64-mingw32- \
    --enable-static --disable-shared --disable-cli --disable-lavf --disable-swscale
  make $JOBS && make install
}

build_x265() {
  log "Building x265 (mingw)"
  cd "$SRC"
  if [ ! -d x265/.git ]; then
    git clone --quiet https://bitbucket.org/multicoreware/x265_git x265 2>/dev/null || \
    git clone --quiet https://github.com/zhongflyTeam/x265_git x265 2>/dev/null || \
    fail "clone x265"
  fi
  cd x265 && mkdir -p build && cd build
  cmake ../source -DCMAKE_TOOLCHAIN_FILE="$PREFIX/mingw-toolchain.cmake" \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" -DCMAKE_BUILD_TYPE=Release \
    -DENABLE_SHARED=OFF -DENABLE_CLI=OFF -DENABLE_ASSEMBLY=OFF
  make $JOBS VERBOSE=1 2>&1 | tee /tmp/x265-build.log || \
    { echo "--- x265 link.txt ---"; cat CMakeFiles/x265-static.dir/link.txt 2>/dev/null; exit 1; }
  make install
}

build_libvpx() {
  log "Building libvpx (mingw)"
  cd "$SRC"
  fetch_git libvpx https://github.com/webmproject/libvpx
  cd libvpx
  ./configure --target=x86_64-win64-gcc --prefix="$PREFIX" \
    --disable-examples --disable-docs --disable-unit-tests \
    --enable-static --disable-shared
  make $JOBS && make install
}

build_libaom() {
  log "Building libaom (mingw)"
  cd "$SRC"
  fetch_git aom https://aomedia.googlesource.com/aom
  cd aom && mkdir -p build && cd build
  cmake .. -DCMAKE_TOOLCHAIN_FILE="$PREFIX/mingw-toolchain.cmake" \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=OFF -DENABLE_TESTS=0 -DENABLE_DOCS=0 -DENABLE_EXAMPLES=0 \
    -DENABLE_TOOLS=0 -DCONFIG_MULTITHREAD=1 -DCONFIG_RUNTIME_CPU_DETECT=0 \
    -DAOM_TARGET_CPU=x86_64
  make $JOBS VERBOSE=1 2>&1 | tee /tmp/aom-build.log || exit 1
  make install
}

build_lame() {
  log "Building libmp3lame (mingw)"
  cd "$SRC"
  if [ ! -d lame-3.100 ]; then
    curl -sSL -o lame.tar.gz \
      https://downloads.sourceforge.net/project/lame/lame/3.100/lame-3.100.tar.gz
    tar xzf lame.tar.gz
  fi
  cd lame-3.100
  ./configure --host=x86_64-w64-mingw32 --prefix="$PREFIX" \
    --enable-static --disable-shared --disable-frontend \
    --disable-analyzer --disable-decoder --disable-rpath
  make $JOBS && make install
}

build_freetype() {
  log "Building freetype (mingw)"
  cd "$SRC"
  local VER=2.13.3
  if [ ! -d "freetype-$VER" ]; then
    curl -sSL -o freetype.tar.xz \
      "https://download.savannah.gnu.org/releases/freetype/freetype-$VER.tar.xz" || \
    curl -sSL -o freetype.tar.gz \
      "https://github.com/freetype/freetype/archive/refs/tags/VER-$VER.tar.gz"
    rm -rf "freetype-$VER" && mkdir -p "freetype-$VER"
    tar xf freetype.tar.xz -C "freetype-$VER" --strip-components=1 || \
    tar xzf freetype.tar.gz -C "freetype-$VER" --strip-components=1
  fi
  cd "freetype-$VER"
  ./configure --host=x86_64-w64-mingw32 --prefix="$PREFIX" \
    --enable-static --disable-shared --without-zlib --without-png \
    --without-brotli --without-harfbuzz --without-bzip2
  make $JOBS && make install
}

build_ffnvcodec() {
  log "Building nv-codec-headers"
  cd "$SRC"
  fetch_git nv-codec-headers https://github.com/FFmpeg/nv-codec-headers
  cd nv-codec-headers
  make install PREFIX="$PREFIX"
}

build_ffmpeg() {
  log "Building FFmpeg (mingw)"
  cd "$SRC"
  fetch_git ffmpeg https://github.com/FFmpeg/FFmpeg.git
  cd ffmpeg
  # Diagnostic: prove libaom links against the cross toolchain.
  log "Testing libaom link"
  cat > /tmp/aomtest.c <<'EOF'
#include <aom/aom_codec.h>
int main(void) { aom_codec_version(); return 0; }
EOF
  pkg-config --exists 'aom >= 2.0.0' && echo "pkg-config aom: OK" || echo "pkg-config aom: MISSING"
  cat "$PREFIX/lib/pkgconfig/aom.pc"
  "$CC" -I"$PREFIX/include" /tmp/aomtest.c -L"$PREFIX/lib" -laom \
    -lws2_32 -luser32 -lbcrypt -lwinpthread -o /tmp/aomtest.exe && echo "aom link: OK"
  log "Recreating ffmpeg libaom check"
  {
    echo "#include <aom/aom_codec.h>"
    echo "#include <stdint.h>"
    echo "long check_aom_codec_version(void) { return (long) aom_codec_version; }"
    echo "int main(void) { int ret = 0; ret |= ((intptr_t)check_aom_codec_version) & 0xFFFF; return ret; }"
  } > /tmp/aomcheck.c
  "$CC" -I"$PREFIX/include" /tmp/aomcheck.c -L"$PREFIX/lib" -laom \
    -lws2_32 -luser32 -lbcrypt -lwinpthread -o /tmp/aomcheck.exe && echo "aom recreate: OK"
  log "Recreating with pkg-config flags"
  AOM_CFLAGS="$(pkg-config --cflags aom)"
  AOM_LIBS="$(pkg-config --libs aom)"
  echo "cflags: $AOM_CFLAGS"
  echo "libs: $AOM_LIBS"
  "$CC" $AOM_CFLAGS /tmp/aomcheck.c $AOM_LIBS \
    -lws2_32 -luser32 -lbcrypt -lwinpthread -o /tmp/aomcheck2.exe && echo "aom pkg-config recreate: OK"
  ./configure \
    --prefix="$PREFIX" \
    --target-os=win64 --arch=x86_64 \
    --cross-prefix=x86_64-w64-mingw32- \
    --cc=x86_64-w64-mingw32-gcc \
    --enable-x86asm \
    --enable-gpl --enable-version3 \
    --enable-static --disable-shared \
    --enable-libx264 --enable-libx265 --enable-libvpx --enable-libaom \
    --enable-libmp3lame --enable-libfreetype \
    --enable-ffnvcodec --enable-cuvid --enable-nvdec --enable-nvenc \
    --enable-dxva2 --enable-d3d11va \
    --extra-cflags="-I$PREFIX/include" \
    --extra-ldflags="-L$PREFIX/lib" \
    --extra-libs="-lws2_32 -luser32 -lbcrypt -lwinpthread" \
    --disable-doc
  make $JOBS && make install
}

build_x264
build_x265
build_libvpx
build_libaom
build_lame
build_freetype
build_ffnvcodec
build_ffmpeg

log "ALL DONE"