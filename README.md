# rplayer

rplayer 是一个基于 Flutter、Rust 和 mpv/media_kit 的本地与 WebDAV 视频播放器。当前重点是移动端体验：媒体库、最近播放、TMDB 海报墙与详情页、弹幕、WebDAV 资源、播放进度、诊断日志和配置同步。

## 当前功能

- 媒体库首页：按 TMDB 类型聚合电影、电视剧、综艺、纪录片、新闻、迷你剧等分类。
- 最近播放：记录播放位置、总时长和最近播放时间，首页显示进度与续播入口。
- 详情页：展示 TMDB 标题、海报、背景图、评分、发布日期、类型、简介、演员和剧集列表。
- 播放器：使用 `media_kit` / libmpv 播放本地或 WebDAV 视频，支持播放/暂停、进度拖动、横竖屏、画面比例、音轨和字幕轨切换。
- 加载状态：基于 mpv 的真实缓冲、视频尺寸和播放位置判断首帧可见状态，避免假进度。
- 可恢复网络错误处理：播放已经恢复时，短暂 TCP 读错误只记录日志，不再覆盖正在播放的画面。
- 弹幕：支持 danmu_api 搜索、匹配、加载、手动重选和播放时渲染。
- TMDB：支持 `/search/multi`，按电影和电视剧分别写入规范化元数据。
- 图片缓存：TMDB 海报、背景图、剧集图和演员头像缓存到本地 SQLite。
- WebDAV：添加远程资源、浏览目录、选择文件夹、播放远程视频。
- 配置与同步：支持导入导出配置、媒体库数据库同步、TMDB 设置、弹幕设置和诊断日志设置。
- 诊断日志：记录扫描、数据库、TMDB、图片缓存、同步、播放和弹幕相关事件，便于排查设备端问题。

## 项目结构

```text
.
├── apps/
│   └── player_flutter/          # Flutter 应用
├── crates/
│   └── player_core/             # Rust FFI 核心库
├── docs/                        # 架构、API 和 TMDB 媒体库设计文档
├── third_party/
│   └── media_kit_libs_android_video/
└── Cargo.toml                   # Rust workspace
```

## 技术栈

- Flutter / Dart：应用界面、播放器页面、设置页、媒体库交互。
- Rust：本地扫描、WebDAV 解析、TMDB/SQLite 元数据、弹幕可见窗口计算和 FFI API。
- SQLite：媒体库、播放进度、TMDB 元数据、图片缓存和配置状态。
- media_kit / libmpv：实际音视频播放。
- TMDB API：电影、剧集、海报、背景图、演员和简介。
- danmu_api：弹幕搜索、匹配和弹幕 XML/JSON 加载。

## 开发环境

需要准备：

- Flutter SDK
- Rust toolchain
- Android SDK / NDK
- `cargo-ndk`，用于生成 Android `libplayer_core.so`

本仓库会忽略本地工具链、构建目录、APK/AAB、Rust target、Android native `.so`、`.understand-anything` 和 graphify 等分析产物。这些文件不要提交到 Git。

## 常用命令

在仓库根目录运行 Rust 检查：

```powershell
cargo fmt -p player_core
cargo test -p player_core
```

在 Flutter 应用目录运行检查和测试：

```powershell
cd apps/player_flutter
flutter analyze
flutter test
```

生成 Android Rust native libs：

```powershell
$env:ANDROID_NDK_HOME = "D:\Users\Desktop\player\.toolchains\android-sdk\ndk\27.3.13750724"
cargo ndk -t armeabi-v7a -t arm64-v8a -o apps/player_flutter/android/app/src/main/jniLibs build -p player_core --release
```

构建 release APK：

```powershell
cd apps/player_flutter
flutter build apk --release
```

APK 输出路径：

```text
apps/player_flutter/build/app/outputs/flutter-apk/app-release.apk
```

## 配置

示例配置见 `.env.example`。常用服务：

```text
TMDB_ACCESS_TOKEN=...
DANMU_API_BASE_URL=http://127.0.0.1:9321
DANMU_API_TOKEN=87654321
```

应用内也可以在“我的”页面配置：

- TMDB 访问令牌、语言、地区和 API 节点
- 弹幕 API 地址和 token
- WebDAV 同步地址、配置文件路径和数据库路径
- 诊断日志开关与导出

## 数据与产物约定

- `apps/player_flutter/android/app/src/main/jniLibs/` 是本地编译产物，不提交。
- `apps/player_flutter/build/`、`target/`、`.dart_tool/`、`.gradle/` 都是构建缓存，不提交。
- `.understand-anything/`、`graphify-out/` 是代码分析产物，不提交。
- `*.sqlite`、`*.db` 是本地运行数据，不提交。
- `Cargo.lock` 当前按现有仓库规则不提交；如后续改成发布固定版本的应用，可再决定是否纳入版本管理。

## 文档

- `docs/architecture.md`：总体架构草案。
- `docs/api-contracts.md`：Flutter 与 Rust、TMDB、danmu_api 的接口说明。
- `docs/tmdb-media-architecture.md`：TMDB 媒体库、SQLite schema 和同步策略。

## 当前边界

项目当前主要验证 Android/Flutter 路径。桌面平台保留了 Rust 和 media_kit 的基础结构，但完整打包、平台库分发和桌面端 UI 还需要后续补齐。
