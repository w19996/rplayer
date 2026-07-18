# rplayer Flutter app

这是 rplayer 的 Flutter 前端。根目录 README 说明完整项目、构建流程和产物约定；本文件只记录 Flutter 子项目相关内容。

## 主要页面

- `MediaLibraryPage`：媒体库首页、最近播放、分类海报墙、详情页、手动 TMDB 识别。
- `VideoPlayerPage`：media_kit 播放器、加载状态、横竖屏、字幕/音轨、弹幕渲染。
- `SourceLibraryPage`：本地和 WebDAV 资源管理、目录浏览、已添加目录管理。
- `ProfilePage`：TMDB、弹幕、WebDAV 同步、诊断日志、配置导入导出。

## 常用命令

```powershell
flutter analyze
flutter test
flutter build apk --release --target-platform android-arm64
```

如果 Android native Rust 库不存在，先在仓库根目录生成：

```powershell
$jniLibs = "apps/player_flutter/android/app/src/main/jniLibs"
cargo ndk --link-libcxx-shared -t arm64-v8a -o $jniLibs build -p player_core --release
Remove-Item -LiteralPath (Join-Path $jniLibs "arm64-v8a/libc++_shared.so")
```

## 产物约定

- `build/`、`.dart_tool/`、`.gradle/` 是本地构建缓存，不提交。
- `android/app/src/main/jniLibs/` 是 Rust 生成的 native 动态库目录，不提交。
- release APK 输出到 `build/app/outputs/flutter-apk/app-release.apk`。
