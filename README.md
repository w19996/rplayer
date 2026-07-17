# rplayer
<div align="center">
 <img src=https://img.shields.io/github/downloads/w19996/rplayer/total />
</div>

rplayer 是一个面向本地影音库和远程媒体源的视频播放器。它使用 Flutter 构建界面，使用 Rust 管理媒体库、元数据和部分解析逻辑，播放核心基于 media_kit / libmpv。

当前主要支持 Android 和 Windows x64。

## 功能特性

### 视频播放

- 播放本地视频、WebDAV 视频和 OpenList 远程视频。
- 支持播放/暂停、进度拖动、续播、横竖屏、画面比例、音轨切换和字幕轨切换。
- 使用 libmpv 作为底层播放引擎，支持常见视频格式和硬件解码能力。
- 记录播放进度、总时长、最近播放时间，回到媒体库后可以继续观看。
- 针对移动端做了低负载播放参数，尽量降低播放时发热和后台/分屏场景卡顿。

### 媒体库

- 添加本地目录、WebDAV 目录、OpenList 目录作为媒体源。
- 自动扫描视频文件并建立媒体库。
- 首页展示最近播放、电影、电视剧、综艺、纪录片、新闻、迷你剧等分类。
- 支持按剧集/文件夹聚合，避免同一剧集或同一目录在首页重复出现。
- 支持多版本文件，例如 4K、1080p、HDR、DV 等版本目录，并在详情页切换播放版本。

### TMDB 元数据

- 使用 TMDB 匹配电影和电视剧。
- 展示标题、海报、背景图、评分、发布日期、类型、简介、演员和剧集信息。
- 缓存海报、背景图、剧集图和演员头像。
- 支持手动重新识别，修正自动匹配错误。
- 同一部剧或电影的多个文件版本共用一份 TMDB 元数据，减少重复请求。

### 弹幕

- 支持通过 danmu_api 搜索和加载弹幕。
- 支持自动匹配、手动重选、播放时同步渲染。
- 支持在分屏、悬浮窗、画中画等场景下保持弹幕显示。

### 远程资源与同步

- WebDAV 目录浏览、文件选择和远程播放。
- OpenList API 目录浏览、登录和远程播放。
- 支持同步配置文件和媒体库数据库。
- 支持导入导出配置，便于换设备迁移。

### 诊断与设置

- 应用内可配置 TMDB、弹幕 API、WebDAV 同步、MPV 高级参数和诊断日志。
- 诊断日志覆盖扫描、数据库、TMDB、图片缓存、同步、播放和弹幕流程，方便定位设备端问题。

## 开源项目与依赖

rplayer 主要使用了这些开源项目：

### 应用与界面

- [Flutter](https://flutter.dev/) / Dart：跨平台应用界面。
- `flutter_localizations`：中文本地化和系统控件本地化。
- `file_picker`：本地文件和目录选择。
- `permission_handler`：Android 权限申请。
- `cupertino_icons`：基础图标。

### 播放

- [media_kit](https://github.com/media-kit/media-kit)：Flutter 播放器封装。
- `media_kit_video`：Flutter 视频渲染组件。
- `media_kit_libs_android_video`：Android 播放 native 库。
- `media_kit_libs_windows_video`：Windows 播放 native 库。
- [mpv / libmpv](https://mpv.io/)：底层音视频播放引擎。

### Rust 核心

- [Rust](https://www.rust-lang.org/)：媒体库、解析、缓存和 FFI 核心。
- `rusqlite` / SQLite：媒体库、播放进度、TMDB 缓存和设置存储。
- `reqwest`：HTTP 请求。
- `tokio`：异步运行时。
- `serde` / `serde_json`：JSON 序列化。
- `roxmltree`：WebDAV XML 解析。
- `url`、`percent-encoding`、`base64`：URL、路径和认证相关处理。
- `anyhow`、`thiserror`：错误处理。
- `cc`：构建 C/C++ 辅助代码。

### 服务与数据

- [TMDB](https://www.themoviedb.org/)：电影、剧集、海报、背景图和演员信息。
- [danmu_api](https://github.com/huangxd-/danmu_api)：弹幕搜索和弹幕数据来源。
- WebDAV：远程媒体库访问与同步。
- OpenList：远程文件列表和播放源接入。
- [TVBoxOS](https://github.com/q215613905/TVBoxOS)：Android TVBox Spider/JAR（type 3）兼容运行时，AGPL-3.0；仅负责解析来源，播放仍走 rplayer 现有流程。详见 [第三方许可证说明](THIRD_PARTY_NOTICES.md)。

## 捐助

如果这个项目对你有帮助，可以通过下面的二维码支持开发。

<p align="center">
  <img src="docs/donate.png" alt="捐助码" width="280">
</p>

## 许可证

本仓库使用 [GPL-3.0](LICENSE) 许可证。
