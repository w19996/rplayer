# [package:media_kit_libs_android_video](https://github.com/media-kit/media-kit)

[![](https://img.shields.io/discord/1079685977523617792?color=33cd57&label=Discord&logo=discord&logoColor=discord)](https://discord.gg/h7qf2R9n57) [![Github Actions](https://github.com/media-kit/media-kit/actions/workflows/ci.yml/badge.svg)](https://github.com/media-kit/media-kit/actions/workflows/ci.yml)

Android package providing video (& audio) native libraries for [`package:media_kit`](https://github.com/media-kit/media-kit).

## Bundled libmpv

The ARM libraries are pinned to the
[`mpv-android` 2026-04-25 release](https://github.com/mpv-android/mpv-android/releases/tag/2026-04-25).
That build includes libplacebo and `gpu-next`. media_kit renders Android video
to its native Surface with `vo=gpu` by default; rplayer selects `vo=gpu-next`
for confirmed Dolby Vision playback. Its FFmpeg build disables Vulkan and does
not include `vf_libplacebo`, so Android does not use the FFmpeg filter path. The
JARs also retain media_kit's Android helper library.

## License

Copyright © 2021 & onwards, Hitesh Kumar Saini <<saini123hitesh@gmail.com>>

This project & the work under this repository is governed by MIT license that can be found in the [LICENSE](./LICENSE) file.
