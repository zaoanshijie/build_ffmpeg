# FFmpeg GitHub Actions Builds

使用 GitHub Actions 从源码编译 FFmpeg，目标平台与依赖如下。构建产物在 Actions 的
Artifacts 中下载。

## 编译目标

| 平台 | 工具链 | 架构 | 构建方式 |
| --- | --- | --- | --- |
| Windows x86_64 | MSVC (Visual Studio) | x86_64 | vcpkg 在 windows-latest 上构建 |
| Windows x86_64 | llvm-mingw (clang/LLD) | x86_64 | Linux 上交叉编译 |
| Linux x86_64 | GCC | x86_64 | Linux 原生构建 |
| Linux aarch64 | GCC | aarch64 | Linux 上交叉编译 |
| Linux x86_64 | Clang | x86_64 | Linux 原生构建 |
| Linux aarch64 | Clang | aarch64 | Linux 上交叉编译 |

## 启用能力

- H.264：libx264（编码/解码）
- H.265/HEVC：libx265（编码/解码）
- VP8/VP9：libvpx（编码/解码）
- AV1：libaom（编码/解码）+ libdav1d（解码）
- AAC：FFmpeg 内置 AAC 编码/解码
- MP3：libmp3lame（编码）+ FFmpeg 内置 MP3 解码
- 文字绘制：libfreetype（drawtext 滤镜）

## 硬件加速（尽力而为）

- Linux x86_64：VAAPI、VDPAU、NVENC/NVDEC/CUVID（NVENC/NVDEC 为 headers-only 编译支持，运行时需要 NVIDIA 驱动）
- Linux aarch64：NVENC/NVDEC/CUVID（headers-only）+ V4L2 M2M（内核驱动时可用）；VAAPI/VDPAU 未启用，原因是 Ubuntu 交叉 sysroot 没有 aarch64 的 libva/libvdpau 开发包
- Windows：DXVA2、D3D11VA、NVENC/NVDEC/CUVID（运行时需要显卡驱动）

## 构建参数

### Linux（x86_64/aarch64，gcc/clang）

脚本：[scripts/build-linux.sh](scripts/build-linux.sh)

```bash
PREFIX=$PWD/install SRC=$PWD/src bash scripts/build-linux.sh x86_64 gcc
PREFIX=$PWD/install SRC=$PWD/src bash scripts/build-linux.sh x86_64 clang
PREFIX=$PWD/install SRC=$PWD/src bash scripts/build-linux.sh aarch64 gcc
PREFIX=$PWD/install SRC=$PWD/src bash scripts/build-linux.sh aarch64 clang
```

依赖构建：

- x264：`./configure --prefix=$PREFIX --enable-static --disable-shared --disable-cli --disable-lavf --disable-swscale`
- x265：CMake `-DENABLE_SHARED=OFF -DENABLE_CLI=OFF`，aarch64 另加 `-DENABLE_ASSEMBLY=OFF`
- libvpx：`./configure --target=x86_64-linux-gcc|arm64-linux-gcc --prefix=$PREFIX --disable-examples --disable-docs --disable-unit-tests --enable-static --disable-shared`
- libaom：CMake `-DBUILD_SHARED_LIBS=OFF -DENABLE_TESTS=0 -DENABLE_DOCS=0 -DENABLE_EXAMPLES=0 -DENABLE_TOOLS=0`
- libdav1d：Meson `--buildtype=release --default-library=static -Denable_tools=false -Denable_tests=false`
- libmp3lame：`./configure --prefix=$PREFIX --enable-static --disable-shared --disable-frontend --disable-analyzer --disable-decoder --disable-rpath`
- freetype：`./configure --prefix=$PREFIX --enable-static --disable-shared --without-zlib --without-png --without-brotli --without-harfbuzz --without-bzip2`
- nv-codec-headers：`make install PREFIX=$PREFIX`

FFmpeg configure（以 x86_64 gcc 为例）：

```bash
./configure \
  --prefix=$PREFIX \
  --pkg-config-flags="--static" \
  --cc=gcc \
  --arch=x86_64 \
  --enable-gpl --enable-version3 \
  --enable-static --disable-shared \
  --enable-libx264 --enable-libx265 --enable-libvpx --enable-libaom --enable-libdav1d \
  --enable-libmp3lame --enable-libfreetype \
  --enable-ffnvcodec --enable-cuvid --enable-nvdec --enable-nvenc \
  --enable-vaapi --enable-vdpau \
  --extra-cflags=-I$PREFIX/include \
  --extra-ldflags=-L$PREFIX/lib
```

aarch64 将 `--cc=gcc` 换成 `aarch64-linux-gnu-gcc`（或 clang 交叉包装器），并加
`--cross-prefix=aarch64-linux-gnu-`；不启用 VAAPI/VDPAU。

### Windows x86_64 MSVC

vcpkg 直接安装带全部所需 feature 的 ffmpeg：

```powershell
vcpkg install "ffmpeg[ffmpeg,ffprobe,gpl,x264,x265,vpx,aom,freetype,fontconfig,drawtext,mp3lame,nvcodec,dav1d]:x64-windows"
```

产物位于 `%VCPKG_INSTALLATION_ROOT%\installed\x64-windows\tools\ffmpeg\bin`，
运行时 DLL 位于 `%VCPKG_INSTALLATION_ROOT%\installed\x64-windows\bin`。

### Windows x86_64 llvm-mingw

脚本：[scripts/build-mingw.sh](scripts/build-mingw.sh)

```bash
PREFIX=$PWD/mingw-install SRC=$PWD/mingw-src MINGW_DIR=$PWD/llvm-mingw bash scripts/build-mingw.sh
```

llvm-mingw 工具链：`https://github.com/mstorsjo/llvm-mingw/releases/download/20260922/llvm-mingw-20260922-ucrt-ubuntu-22.04-x86_64.tar.xz`

依赖构建参数同 Linux，但使用 `x86_64-w64-mingw32-*` 工具链和 CMake Windows 交叉工具链文件。
FFmpeg configure：

```bash
./configure \
  --prefix=$PREFIX \
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
  --extra-cflags=-I$PREFIX/include \
  --extra-ldflags=-L$PREFIX/lib \
  --extra-libs="-lws2_32 -luser32 -lbcrypt -lwinpthread"
```

## 运行 / 验证

- Linux：解压 tar.gz 后直接运行 `bin/ffmpeg`、`bin/ffprobe`
- Windows：解压后 `ffmpeg.exe`、`ffprobe.exe` 与同目录 DLL 一起使用
- 构建信息：Artifacts 中 `build-info/version.txt`、`encoders.txt`、`hwaccels.txt`、`ffmpeg-config.log`
