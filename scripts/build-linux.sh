#!/usr/bin/env bash
# Build FFmpeg (x264/x265/libvpx/libaom/libdav1d/libmp3lame/freetype + HW accel) for Linux.
# Usage: build-linux.sh <arch> <compiler>
#   arch:     x86_64 | aarch64
#   compiler: gcc | clang
set -euo pipefail

ARCH="${1:?arch required (x86_64|aarch64)}"
COMPILER="${2:?compiler required (gcc|clang)}"

PREFIX="${PREFIX:?PREFIX required}"
SRC="${SRC:?SRC required}"
JOBS="-j$(nproc)"

mkdir -p "$PREFIX" "$SRC" "$HOME/bin"
export PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig"
export PATH="$HOME/bin:$PATH"

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

# ---------------- toolchain ----------------
if [ "$ARCH" = "aarch64" ]; then
  case "$COMPILER" in
    gcc)
      export CC=aarch64-linux-gnu-gcc
      export CXX=aarch64-linux-gnu-g++
      ;;
    clang)
      cat > "$HOME/bin/aarch64-linux-gnu-clang" <<'EOF'
#!/bin/sh
exec clang --target=aarch64-linux-gnu --gcc-toolchain=/usr "$@"
EOF
      cat > "$HOME/bin/aarch64-linux-gnu-clang++" <<'EOF'
#!/bin/sh
exec clang++ --target=aarch64-linux-gnu --gcc-toolchain=/usr "$@"
EOF
      chmod +x "$HOME/bin/aarch64-linux-gnu-clang" "$HOME/bin/aarch64-linux-gnu-clang++"
      export CC=aarch64-linux-gnu-clang
      export CXX=aarch64-linux-gnu-clang++
      ;;
  esac
  export AR=aarch64-linux-gnu-ar RANLIB=aarch64-linux-gnu-ranlib
  export STRIP=aarch64-linux-gnu-strip NM=aarch64-linux-gnu-nm
else
  case "$COMPILER" in
    gcc)   export CC=gcc;   export CXX=g++ ;;
    clang) export CC=clang; export CXX=clang++ ;;
  esac
  export AR=ar RANLIB=ranlib STRIP=strip NM=nm
fi
log "Toolchain: arch=$ARCH compiler=$COMPILER CC=$CC"

# ---------------- deps ----------------
build_x264() {
  log "Building x264"
  cd "$SRC"
  fetch_git x264 https://code.videolan.org/videolan/x264.git https://github.com/mirror/x264
  cd x264
  local host=()
  if [ "$ARCH" = aarch64 ]; then host=(--host=aarch64-linux-gnu); fi
  ./configure --prefix="$PREFIX" --enable-static --disable-shared \
    --disable-cli --disable-lavf --disable-swscale "${host[@]}"
  make $JOBS && make install
}

build_x265() {
  log "Building x265"
  cd "$SRC"
  fetch_git x265 https://bitbucket.org/multicoreware/x265_git https://github.com/zhongflyTeam/x265_git
  cd x265
  mkdir -p build && cd build
  local extra=()
  if [ "$ARCH" = aarch64 ]; then
    extra+=( -DCMAKE_SYSTEM_NAME=Linux -DCMAKE_SYSTEM_PROCESSOR=aarch64 )
    extra+=( -DCMAKE_C_COMPILER="$CC" -DCMAKE_CXX_COMPILER="$CXX" )
    extra+=( -DCMAKE_AR="$AR" -DCMAKE_RANLIB="$RANLIB" -DCMAKE_STRIP="$STRIP" )
    extra+=( -DENABLE_ASSEMBLY=OFF )
  else
    extra+=( -DCMAKE_C_COMPILER="$CC" -DCMAKE_CXX_COMPILER="$CXX" )
  fi
  cmake ../source -DCMAKE_INSTALL_PREFIX="$PREFIX" -DCMAKE_BUILD_TYPE=Release \
    -DENABLE_SHARED=OFF -DENABLE_CLI=OFF -DCMAKE_POSITION_INDEPENDENT_CODE=ON "${extra[@]}"
  make $JOBS && make install
}

build_libvpx() {
  log "Building libvpx"
  cd "$SRC"
  fetch_git libvpx https://github.com/webmproject/libvpx
  cd libvpx
  local target
  if [ "$ARCH" = aarch64 ]; then target=arm64-linux-gcc; else target=x86_64-linux-gcc; fi
  ./configure --target="$target" --prefix="$PREFIX" \
    --disable-examples --disable-docs --disable-unit-tests \
    --enable-static --disable-shared
  make $JOBS && make install
}

build_libaom() {
  log "Building libaom"
  cd "$SRC"
  fetch_git aom https://aomedia.googlesource.com/aom
  cd aom && mkdir -p build && cd build
  local extra=()
  if [ "$ARCH" = aarch64 ]; then
    extra+=( -DCMAKE_SYSTEM_NAME=Linux -DCMAKE_SYSTEM_PROCESSOR=aarch64 )
    extra+=( -DCMAKE_C_COMPILER="$CC" -DCMAKE_ASM_COMPILER="$CC" )
    extra+=( -DCMAKE_AR="$AR" -DCMAKE_RANLIB="$RANLIB" -DCMAKE_STRIP="$STRIP" )
    extra+=( -DAOM_TARGET_CPU=arm64 -DCONFIG_RUNTIME_CPU_DETECT=0 )
  else
    extra+=( -DCMAKE_C_COMPILER="$CC" -DAOM_TARGET_CPU=x86_64 )
  fi
  cmake .. -DCMAKE_INSTALL_PREFIX="$PREFIX" -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=OFF -DENABLE_TESTS=0 -DENABLE_DOCS=0 -DENABLE_EXAMPLES=0 \
    -DENABLE_TOOLS=0 -DCONFIG_MULTITHREAD=1 "${extra[@]}"
  make $JOBS && make install
}

build_dav1d() {
  log "Building dav1d"
  cd "$SRC"
  fetch_git dav1d https://code.videolan.org/videolan/dav1d.git
  cd dav1d
  local extra=(-Denable_tools=false -Denable_tests=false)
  if [ "$ARCH" = aarch64 ]; then
    cat > "$SRC/dav1d-cross.txt" <<'EOF'
[binaries]
c = 'aarch64-linux-gnu-gcc'
cpp = 'aarch64-linux-gnu-g++'
ar = 'aarch64-linux-gnu-ar'
strip = 'aarch64-linux-gnu-strip'
[host_machine]
system = 'linux'
cpu_family = 'aarch64'
cpu = 'aarch64'
endian = 'little'
EOF
    sed -i "s/aarch64-linux-gnu-gcc/$CC/g; s/aarch64-linux-gnu-g++/$CXX/g" "$SRC/dav1d-cross.txt"
    extra+=(-Dcross_file="$SRC/dav1d-cross.txt")
  fi
  rm -rf build
  CC="$CC" CXX="$CXX" meson setup build --buildtype=release --default-library=static \
    --prefix="$PREFIX" "${extra[@]}"
  ninja -C build && ninja -C build install
}

build_lame() {
  log "Building libmp3lame"
  cd "$SRC"
  if [ ! -d lame-3.100 ]; then
    curl -sSL -o lame.tar.gz \
      https://downloads.sourceforge.net/project/lame/lame/3.100/lame-3.100.tar.gz
    tar xzf lame.tar.gz
  fi
  cd lame-3.100
  local host=()
  if [ "$ARCH" = aarch64 ]; then host=(--host=aarch64-linux-gnu); fi
  ./configure --prefix="$PREFIX" --enable-static --disable-shared \
    --disable-frontend --disable-analyzer --disable-decoder --disable-rpath "${host[@]}"
  make $JOBS && make install
}

build_freetype() {
  log "Building freetype"
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
  local host=()
  if [ "$ARCH" = aarch64 ]; then host=(--host=aarch64-linux-gnu); fi
  ./configure --prefix="$PREFIX" --enable-static --disable-shared \
    --without-zlib --without-png --without-brotli --without-harfbuzz --without-bzip2 "${host[@]}"
  make $JOBS && make install
}

build_ffnvcodec() {
  log "Building nv-codec-headers"
  cd "$SRC"
  fetch_git nv-codec-headers https://github.com/FFmpeg/nv-codec-headers
  cd nv-codec-headers
  make install PREFIX="$PREFIX"
}

# ---------------- ffmpeg ----------------
build_ffmpeg() {
  log "Building FFmpeg"
  cd "$SRC"
  fetch_git ffmpeg https://github.com/FFmpeg/FFmpeg.git
  cd ffmpeg
  local extra=()
  if [ "$ARCH" = aarch64 ]; then
    extra+=( --cross-prefix=aarch64-linux-gnu- )
  else
    extra+=( --enable-vaapi --enable-vdpau )
  fi
  ./configure \
    --prefix="$PREFIX" \
    --pkg-config-flags="--static" \
    --cc="$CC" \
    --arch="$ARCH" \
    --enable-gpl --enable-version3 \
    --enable-static --disable-shared \
    --enable-libx264 --enable-libx265 --enable-libvpx --enable-libaom --enable-libdav1d \
    --enable-libmp3lame --enable-libfreetype \
    --enable-ffnvcodec --enable-cuvid --enable-nvdec --enable-nvenc \
    --extra-cflags="-I$PREFIX/include" \
    --extra-ldflags="-L$PREFIX/lib" \
    --disable-doc \
    "${extra[@]}"
  make $JOBS && make install
}

build_x264
build_x265
build_libvpx
build_libaom
build_dav1d
build_lame
build_freetype
build_ffnvcodec
build_ffmpeg

log "ALL DONE"