# FFmpeg GitHub Actions Builds

使用 GitHub Actions 从源码编译 FFmpeg，全部 6 个目标已编译成功。构建产物从每个
工作流运行的 **Actions Artifacts** 页面下载。

## 编译目标与状态

| 平台 | 工具链 | 架构 | 构建方式 | 状态 |
| --- | --- | --- | --- | --- |
| Windows x86_64 | MSVC (Visual Studio 2022) | x86_64 | vcpkg 在 windows-latest 上构建 | 成功 |
| Windows x86_64 | llvm-mingw (Clang/LLD, UCRT) | x86_64 | Linux 上交叉编译 | 成功 |
| Linux x86_64 | GCC 13 | x86_64 | Linux 原生构建 | 成功 |
| Linux aarch64 | GCC 13 | aarch64 | Linux 上交叉编译 | 成功 |
| Linux x86_64 | Clang | x86_64 | Linux 原生构建 | 成功 |
| Linux aarch64 | Clang | aarch64 | Linux 上交叉编译 | 成功 |

## 启用能力与验证结果

- H.264：`libx264`（编码/解码），已验证 `libx264`、`libx264rgb`
- H.265/HEVC：`libx265`（编码/解码），已验证 `libx265`
- VP8/VP9：`libvpx`（编码/解码），已验证 `libvpx`、`libvpx-vp9`
- AV1：`libaom`（编码/解码）+ `libdav1d`（解码），已验证 `libaom-av1`
- AAC：FFmpeg 内置 AAC，已验证 `aac`（MSVC 构建另有 `aac_mf` MediaFoundation 编码器）
- MP3：`libmp3lame`（编码）+ FFmpeg 内置 MP3 解码，已验证 `libmp3lame`
- 文字绘制：`libfreetype`（drawtext 滤镜），已启用

## 硬件加速（验证结果）

- Linux x86_64 gcc/clang：`vdpau`、`cuda`、`vaapi` 出现在 `-hwaccels`，编码器含 `h264_nvenc`、`hevc_nvenc`
- Linux aarch64 gcc/clang：已启用 `--enable-ffnvcodec --enable-nvdec --enable-nvenc --enable-cuvid` 与 V4L2 支持；VAAPI/VDPAU 未编译，原因是 Ubuntu 交叉 sysroot 没有 aarch64 的 libva/libvdpau 开发包
- Windows x86_64 MSVC：`dxva2`、`d3d11va`、`d3d12va`、`cuda`，编码器含 `h264_nvenc`、`hevc_nvenc`、`av1_nvenc`
- Windows x86_64 llvm-mingw：已启用 DXVA2/D3D11VA + NVENC/NVDEC/CUVID（运行时需要显卡驱动）

## Artifacts

| 目标 | Artifact 名称 |
| --- | --- |
| Windows x86_64 MSVC | `ffmpeg-windows-x86_64-msvc` |
| Windows x86_64 llvm-mingw | `ffmpeg-windows-x86_64-llvm-mingw` |
| Linux x86_64 gcc | `ffmpeg-linux-x86_64-gcc` |
| Linux x86_64 clang | `ffmpeg-linux-x86_64-clang` |
| Linux aarch64 gcc | `ffmpeg-linux-aarch64-gcc` |
| Linux aarch64 clang | `ffmpeg-linux-aarch64-clang` |

Linux 产物是 `ffmpeg-linux-<arch>-<compiler>.tar.gz`（含 `bin`、`lib`、`include`、
`build-info`）。Windows MSVC 产物是 `ffmpeg.exe`、`ffprobe.exe` 及同目录的运行时 DLL。

## 构建参数

### Linux（x86_64/aarch64，gcc/clang）

脚本：[scripts/build-linux.sh](scripts/build-linux.sh)

```bash
PREFIX=$PWD/install SRC=$PWD/src bash scripts/build-linux.sh x86_64 gcc
PREFIX=$PWD/install SRC=$PWD/src bash scripts/build-linux.sh x86_64 clang
PREFIX=$PWD/install SRC=$PWD/src bash scripts/build-linux.sh aarch64 gcc
PREFIX=$PWD/install SRC=$PWD/src bash scripts/build-linux.sh aarch64 clang
```

依赖构建（全部构建进 `$PREFIX`）：

- x264：`./configure --prefix=$PREFIX --enable-static --disable-shared --disable-cli --disable-lavf --disable-swscale`
- x265：完整 git clone（带 tag），CMake `-DENABLE_SHARED=OFF -DENABLE_CLI=OFF`；aarch64 另加 `-DENABLE_ASSEMBLY=OFF` 及交叉工具链路径
- libvpx：`./configure --target=x86_64-linux-gcc|arm64-linux-gcc --prefix=$PREFIX --disable-examples --disable-docs --disable-unit-tests --enable-static --disable-shared`
- libaom：CMake `-DBUILD_SHARED_LIBS=OFF -DENABLE_TESTS=0 -DENABLE_DOCS=0 -DENABLE_EXAMPLES=0 -DENABLE_TOOLS=0`，aarch64 另加 `-DAOM_TARGET_CPU=arm64 -DCONFIG_RUNTIME_CPU_DETECT=0`
- libdav1d：Meson `--buildtype=release --default-library=static --libdir=lib -Denable_tools=false -Denable_tests=false`，aarch64 用 `--cross-file`
- libmp3lame：`./configure --prefix=$PREFIX --enable-static --disable-shared --disable-frontend --disable-analyzer --disable-decoder --disable-rpath`
- freetype：`./configure --prefix=$PREFIX --enable-static --disable-shared --without-zlib --without-png --without-brotli --without-harfbuzz --without-bzip2`
- nv-codec-headers：`make install PREFIX=$PREFIX`

FFmpeg configure（x86_64 gcc，行为已在产物 `-buildconf` 中验证）：

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

aarch64 使用：

```bash
./configure \
  --prefix=$PREFIX \
  --pkg-config-flags="--static" \
  --cc=aarch64-linux-gnu-gcc \
  --arch=aarch64 --target-os=linux \
  --cross-prefix=aarch64-linux-gnu- \
  --enable-gpl --enable-version3 \
  --enable-static --disable-shared \
  --enable-libx264 --enable-libx265 --enable-libvpx --enable-libaom --enable-libdav1d \
  --enable-libmp3lame --enable-libfreetype \
  --enable-ffnvcodec --enable-cuvid --enable-nvdec --enable-nvenc \
  --extra-cflags=-I$PREFIX/include \
  --extra-ldflags=-L$PREFIX/lib
```

注意：交叉编译时 FFmpeg configure 会查找 `aarch64-linux-gnu-pkg-config`，脚本会创建
指向 `/usr/bin/pkg-config` 的包装器，避免库检测失败。

### Windows x86_64 MSVC

使用 vcpkg 的 ffmpeg port（MSVC 构建），命令即构建参数：

```powershell
vcpkg install "ffmpeg[ffmpeg,ffprobe,gpl,x264,x265,vpx,aom,freetype,fontconfig,drawtext,mp3lame,nvcodec,dav1d]:x64-windows"
```

产物在 `%VCPKG_INSTALLATION_ROOT%\installed\x64-windows\tools\ffmpeg\`，
工作流会收集 `ffmpeg.exe`、`ffprobe.exe` 及 `%VCPKG_INSTALLATION_ROOT%\installed\x64-windows\bin\` 下的运行时 DLL。

### Windows x86_64 llvm-mingw

脚本：[scripts/build-mingw.sh](scripts/build-mingw.sh)

```bash
PREFIX=$PWD/mingw-install SRC=$PWD/mingw-src MINGW_DIR=$PWD/llvm-mingw bash scripts/build-mingw.sh
```

llvm-mingw 工具链：
`llvm-mingw-20260922-ucrt-ubuntu-22.04-x86_64.tar.xz`（mstorsjo/llvm-mingw 发布版）。

依赖构建参数与 Linux 相同，但使用 `x86_64-w64-mingw32-*` 工具链和 CMake Windows
交叉工具链文件。脚本会创建 `x86_64-w64-mingw32-pkg-config` 包装器和
`libpthread.a -> libwinpthread.a` 链接。FFmpeg configure：

```bash
./configure \
  --prefix=$PREFIX \
  --target-os=win64 --arch=x86_64 \
  --cross-prefix=x86_64-w64-mingw32- \
  --cc=x86_64-w64-mingw32-gcc \
  --enable-x86asm \
  --enable-gpl --enable-version3 \
  --enable-static --disable-shared \
  --pkg-config-flags="--static" \
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
- Windows MSVC：`ffmpeg.exe`、`ffprobe.exe` 与同目录 DLL 放在同一目录使用
- Windows llvm-mingw：解压后运行 `bin/ffmpeg.exe`（依赖系统 UCRT，Windows 10+ 已内置）
- 构建信息：Artifacts 中 `build-info/version.txt`、`encoders.txt`、`hwaccels.txt`、`ffmpeg-config.log`