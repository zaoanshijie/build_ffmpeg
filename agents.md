使用github ations编译ffmpeg 需要添加h264 h265支持

一下这些尽力而为的也编译进去 不呢编译的列出原因

- VP8/VP9
- AV1
- AAC
- MP3
- 文字绘制：需要 libfreetype

目标平台

- win x86_64 msvc
- win x86_64 llvm-mingw
- linux x86_64 gcc
- linux aarch64 gcc
- linux x86_64 clang
- linux aarch64 clang

> win的如果直接编译不方便 可以尝试在linux中交叉编译
> 以上编译平台要求尽力而为的编译，尽量启用硬件加速，如遇到无法编译列出原因

结束后需要有readme文档以及每种类型的编译参数

> 注意: actions是有运行时间的 你提交任务后需要等待任务结束拿到结果后再继续推进 直到编译成功
