use std::ffi::{CStr, CString};
use std::os::raw::c_char;

use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum MediaKind {
    Movie,
    TvEpisode,
    Unknown,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct MediaIdentity {
    pub raw_title: String,
    pub normalized_title: String,
    pub year: Option<u16>,
    pub season: Option<u16>,
    pub episode: Option<u16>,
    pub kind: MediaKind,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SearchCandidate {
    pub title: String,
    pub media_type_hint: String,
    pub year: Option<u16>,
    pub season_number: Option<u16>,
    pub episode_number: Option<u16>,
    pub version_name: String,
    pub version_tags: Vec<String>,
    pub version_dir_path: String,
    pub source_type: String,
    pub source_path: String,
    pub confidence: f64,
    pub warnings: Vec<String>,
}

pub fn parse_media_identity(folder_name: &str, file_name: &str) -> Result<MediaIdentity> {
    let json = parse_media_identity_json(folder_name, file_name)?;
    serde_json::from_str(&json).context("failed to decode media identity")
}

pub fn parse_media_identity_json(folder_name: &str, file_name: &str) -> Result<String> {
    let folder_name = CString::new(folder_name).context("folder name contains nul byte")?;
    let file_name = CString::new(file_name).context("file name contains nul byte")?;
    cpp_string(|| unsafe {
        player_core_cpp_parse_media_identity_json(folder_name.as_ptr(), file_name.as_ptr())
    })
}

pub fn parse_media_path_candidates(source_type: &str, path: &str) -> Result<Vec<SearchCandidate>> {
    let json = parse_media_path_candidates_json(source_type, path)?;
    serde_json::from_str(&json).context("failed to decode media path candidates")
}

pub fn parse_media_path_candidates_json(source_type: &str, path: &str) -> Result<String> {
    let source_type = CString::new(source_type).context("source type contains nul byte")?;
    let path = CString::new(path).context("path contains nul byte")?;
    cpp_string(|| unsafe {
        player_core_cpp_parse_media_path_candidates_json(source_type.as_ptr(), path.as_ptr())
    })
}

pub fn media_series_title_json(source_type: &str, path: &str) -> Result<String> {
    let source_type = CString::new(source_type).context("source type contains nul byte")?;
    let path = CString::new(path).context("path contains nul byte")?;
    cpp_string(|| unsafe {
        player_core_cpp_media_series_title_json(source_type.as_ptr(), path.as_ptr())
    })
}

pub fn set_version_directory_regexes_json(patterns_json: &str) -> Result<String> {
    let patterns: Vec<String> = serde_json::from_str(patterns_json)
        .context("failed to decode version directory regexes")?;
    let mut normalized = Vec::new();
    for pattern in patterns {
        let trimmed = pattern.trim();
        if trimmed.is_empty() {
            continue;
        }
        if trimmed.contains('\n') || trimmed.contains('\r') {
            anyhow::bail!("version directory regex cannot contain line breaks");
        }
        normalized.push(trimmed.to_string());
    }
    let patterns_text =
        CString::new(normalized.join("\n")).context("version directory regex contains nul byte")?;
    let error = cpp_string(|| unsafe {
        player_core_cpp_set_version_directory_regexes(patterns_text.as_ptr())
    })?;
    if error.trim().is_empty() {
        Ok("{}".to_string())
    } else {
        anyhow::bail!(error);
    }
}

fn cpp_string(run: impl FnOnce() -> *mut c_char) -> Result<String> {
    let value = run();
    if value.is_null() {
        anyhow::bail!("C++ media identity parser returned null");
    }
    let text = unsafe { CStr::from_ptr(value) }
        .to_str()
        .context("C++ media identity parser returned invalid UTF-8")?
        .to_string();
    unsafe {
        player_core_cpp_free_string(value);
    }
    Ok(text)
}

extern "C" {
    fn player_core_cpp_parse_media_path_candidates_json(
        source_type: *const c_char,
        path: *const c_char,
    ) -> *mut c_char;
    fn player_core_cpp_parse_media_identity_json(
        folder_name: *const c_char,
        file_name: *const c_char,
    ) -> *mut c_char;
    fn player_core_cpp_media_series_title_json(
        source_type: *const c_char,
        path: *const c_char,
    ) -> *mut c_char;
    fn player_core_cpp_set_version_directory_regexes(patterns: *const c_char) -> *mut c_char;
    fn player_core_cpp_free_string(value: *mut c_char);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_movie_title() {
        let identity =
            parse_media_identity("Inception (2010)", "Inception.2010.1080p.BluRay.x265.mkv")
                .unwrap();

        assert_eq!(identity.year, Some(2010));
        assert_eq!(identity.kind, MediaKind::Movie);
        assert!(identity.normalized_title.contains("Inception"));
    }

    #[test]
    fn parses_tv_episode() {
        let identity =
            parse_media_identity("Breaking Bad", "Breaking.Bad.S01E02.1080p.mkv").unwrap();

        assert_eq!(identity.kind, MediaKind::TvEpisode);
        assert_eq!(identity.season, Some(1));
        assert_eq!(identity.episode, Some(2));
    }

    #[test]
    fn parses_single_digit_tv_episode() {
        let identity = parse_media_identity("Show", "Show.S1E2.mkv").unwrap();

        assert_eq!(identity.kind, MediaKind::TvEpisode);
        assert_eq!(identity.season, Some(1));
        assert_eq!(identity.episode, Some(2));
    }

    #[test]
    fn parses_ep_number_tokens() {
        for (file_name, episode) in [
            ("Example-EP126.mp4", 126),
            ("Example.E126.1080p.mkv", 126),
            ("example-ep007.mp4", 7),
            ("A-B-EP68.mp4", 68),
        ] {
            let identity = parse_media_identity("Example Show", file_name).unwrap();

            assert_eq!(identity.kind, MediaKind::TvEpisode);
            assert_eq!(identity.season, Some(1));
            assert_eq!(identity.episode, Some(episode));
        }
    }

    #[test]
    fn infers_episode_from_numeric_file_in_series_folder() {
        let identity = parse_media_identity("Example Show", "01~4K.mp4").unwrap();

        assert_eq!(identity.kind, MediaKind::TvEpisode);
        assert_eq!(identity.normalized_title, "Example Show");
        assert_eq!(identity.season, Some(1));
        assert_eq!(identity.episode, Some(1));
    }

    #[test]
    fn infers_episode_from_plain_numeric_file_in_series_folder() {
        let identity = parse_media_identity("Example Show", "2.mp4").unwrap();

        assert_eq!(identity.kind, MediaKind::TvEpisode);
        assert_eq!(identity.normalized_title, "Example Show");
        assert_eq!(identity.season, Some(1));
        assert_eq!(identity.episode, Some(2));
    }

    #[test]
    fn uses_series_folder_for_local_season_path() {
        assert_eq!(
            media_series_title_json("local", "C:/media/Low IQ Crime/Season 1/S01E01.mkv").unwrap(),
            "\"Low IQ Crime\""
        );
    }

    #[test]
    fn uses_series_folder_for_remote_season_path() {
        assert_eq!(
            media_series_title_json("webdav", "/media/Low IQ Crime/Season 1/S01E01.mkv").unwrap(),
            "\"Low IQ Crime\""
        );
    }

    #[test]
    fn parses_reverse_path_candidates_with_version_directory() {
        let candidates = parse_media_path_candidates(
            "webdav",
            "/media/庆余年/4K 高码率/Season 2/03.2160p.HEVC.mkv",
        )
        .unwrap();

        assert_eq!(candidates[0].title, "庆余年");
        assert_eq!(candidates[0].media_type_hint, "tv");
        assert_eq!(candidates[0].season_number, Some(2));
        assert_eq!(candidates[0].episode_number, Some(3));
        assert_eq!(candidates[0].version_name, "4K 高码率");
        assert_eq!(candidates[0].source_type, "directory");
    }

    #[test]
    fn treats_quark_share_quality_directories_as_version_context() {
        let plain_4k =
            parse_media_path_candidates("webdav", "/夸克1/来自：分享/乡村爱情十八/4K/01.mkv")
                .unwrap();
        assert_eq!(plain_4k[0].title, "乡村爱情十八");
        assert_eq!(plain_4k[0].version_name, "4K");
        assert_eq!(
            plain_4k[0].version_dir_path,
            "夸克1/来自：分享/乡村爱情十八/4K"
        );

        let sdr_high_bitrate = parse_media_path_candidates(
            "webdav",
            "/夸克1/来自：分享/乡村爱情十八/4K SDR 高码率/01.mkv",
        )
        .unwrap();

        assert_eq!(sdr_high_bitrate[0].title, "乡村爱情十八");
        assert_eq!(sdr_high_bitrate[0].version_name, "4K SDR 高码率");
        assert_eq!(
            sdr_high_bitrate[0].version_dir_path,
            "夸克1/来自：分享/乡村爱情十八/4K SDR 高码率"
        );

        let dolby_vision = parse_media_path_candidates(
            "webdav",
            "/夸克1/来自：分享/小城大事/4K DV杜比视界 高码率/01.mkv",
        )
        .unwrap();

        assert_eq!(dolby_vision[0].title, "小城大事");
        let dolby_version_name = dolby_vision[0].version_name.to_lowercase();
        assert!(dolby_version_name.contains("4k"));
        assert!(dolby_version_name.contains("dv"));
        assert!(dolby_vision[0].version_name.contains("杜比视界"));
        assert_eq!(
            dolby_vision[0].version_dir_path,
            "夸克1/来自：分享/小城大事/4K DV杜比视界 高码率"
        );
    }

    #[test]
    fn rejects_pure_filename_as_search_candidate() {
        let candidates =
            parse_media_path_candidates("local", "D:/Shows/Example Show/01.1080p.HEVC.mp4")
                .unwrap();

        assert_eq!(candidates.len(), 1);
        assert_eq!(candidates[0].title, "Example Show");
        assert_eq!(candidates[0].media_type_hint, "tv");
        assert_eq!(candidates[0].season_number, Some(1));
        assert_eq!(candidates[0].episode_number, Some(1));
        assert!(candidates
            .iter()
            .all(|candidate| candidate.source_type != "filename"));
    }

    #[test]
    fn keeps_files_in_same_directory_as_default_version() {
        let first = parse_media_path_candidates("local", "D:/Shows/Example Show/01.mkv").unwrap();
        let second =
            parse_media_path_candidates("local", "D:/Shows/Example Show/02.1080p.mkv").unwrap();

        assert_eq!(first[0].title, "Example Show");
        assert_eq!(first[0].version_name, "默认");
        assert_eq!(first[0].version_dir_path, "D:/Shows/Example Show");
        assert_eq!(second[0].title, "Example Show");
        assert_eq!(second[0].version_name, "默认");
        assert_eq!(second[0].version_dir_path, first[0].version_dir_path);
    }

    #[test]
    fn keeps_numeric_episodes_under_their_direct_parent() {
        let candidates =
            parse_media_path_candidates("webdav", "/Quark/Small Folder/Example Show/141.mp4")
                .unwrap();

        assert_eq!(candidates[0].title, "Example Show");
        assert_eq!(candidates[0].source_path, "Quark/Small Folder/Example Show");
        assert_eq!(candidates[0].version_name, "默认");
        assert_eq!(
            candidates[0].version_dir_path,
            "Quark/Small Folder/Example Show"
        );
        assert_eq!(candidates[0].episode_number, Some(141));
    }

    #[test]
    fn keeps_ep_number_token_files_under_their_direct_parent() {
        let candidates = parse_media_path_candidates(
            "webdav",
            "/Quark/Small Folder/Example Show/Example-EP126.mp4",
        )
        .unwrap();

        assert_eq!(candidates[0].title, "Example Show");
        assert_eq!(candidates[0].episode_number, Some(126));
    }

    #[test]
    fn treats_child_directories_as_named_versions() {
        let candidates = parse_media_path_candidates(
            "local",
            "D:/Shows/Example Show/1080P Internal Subs/01.mkv",
        )
        .unwrap();

        assert_eq!(candidates[0].title, "Example Show");
        assert_eq!(candidates[0].version_name, "1080P Internal Subs");
        assert_eq!(
            candidates[0].version_dir_path,
            "D:/Shows/Example Show/1080P Internal Subs"
        );
        assert_eq!(candidates[0].episode_number, Some(1));
    }

    #[test]
    fn treats_extras_directory_as_named_version() {
        let candidates =
            parse_media_path_candidates("webdav", "/夸克1/来自：分享/去有风的地方/花絮/彩蛋.mp4")
                .unwrap();

        assert_eq!(candidates[0].title, "去有风的地方");
        assert_eq!(candidates[0].version_name, "花絮");
        assert_eq!(
            candidates[0].version_dir_path,
            "夸克1/来自：分享/去有风的地方/花絮"
        );
    }

    #[test]
    fn treats_regex_quality_directory_as_version_context() {
        let candidates =
            parse_media_path_candidates("local", "D:/Shows/Example Show/4K.H.265/01.mkv").unwrap();

        assert_eq!(candidates[0].title, "Example Show");
        assert_eq!(candidates[0].version_name, "4K.H.265");
        assert_eq!(
            candidates[0].version_dir_path,
            "D:/Shows/Example Show/4K.H.265"
        );
        assert_eq!(candidates[0].episode_number, Some(1));
    }

    #[test]
    fn applies_custom_version_directory_regexes() {
        set_version_directory_regexes_json(r#"["^My Edition$"]"#).unwrap();
        let candidates =
            parse_media_path_candidates("local", "D:/Shows/Example Show/My Edition/01.mkv")
                .unwrap();
        set_version_directory_regexes_json("[]").unwrap();

        assert_eq!(candidates[0].title, "Example Show");
        assert_eq!(candidates[0].version_name, "My Edition");
        assert_eq!(
            candidates[0].version_dir_path,
            "D:/Shows/Example Show/My Edition"
        );
        assert_eq!(candidates[0].episode_number, Some(1));
    }

    #[test]
    fn treats_chapter_directories_as_version_context() {
        for chapter in ["第1章", "第一章", "第1章 CMake快速入门篇"] {
            let path = format!("/Quark/Example Show/{chapter}/01.mp4");
            let candidates = parse_media_path_candidates("webdav", &path).unwrap();

            assert_eq!(candidates[0].title, "Example Show");
            assert_eq!(candidates[0].version_name, chapter);
            assert_eq!(
                candidates[0].version_dir_path,
                format!("Quark/Example Show/{chapter}")
            );
            assert_eq!(candidates[0].episode_number, Some(1));
        }
    }

    #[test]
    fn treats_chapter_title_directories_as_versions() {
        let candidates = parse_media_path_candidates(
            "webdav",
            "/夸克1/来自：分享/夏曹俊-CMake跨平台构建大型c++项目/第1章 CMake快速入门篇/01.mp4",
        )
        .unwrap();

        assert_eq!(candidates[0].title, "夏曹俊 CMake跨平台构建大型c 项目");
        assert_eq!(candidates[0].version_name, "第1章 CMake快速入门篇");
        assert_eq!(
            candidates[0].version_dir_path,
            "夸克1/来自：分享/夏曹俊-CMake跨平台构建大型c++项目/第1章 CMake快速入门篇"
        );
    }

    #[test]
    fn keeps_season_directories_out_of_version_names() {
        let candidates =
            parse_media_path_candidates("local", "D:/Shows/Example Show/Season 2/03.mkv").unwrap();

        assert_eq!(candidates[0].title, "Example Show");
        assert_eq!(candidates[0].season_number, Some(2));
        assert_eq!(candidates[0].episode_number, Some(3));
        assert_eq!(candidates[0].version_name, "默认");
        assert_eq!(candidates[0].version_dir_path, "D:/Shows/Example Show");
    }

    #[test]
    fn treats_chinese_season_directories_as_version_context() {
        let candidates =
            parse_media_path_candidates("webdav", "/Quark/Example Show/第一季/01.mp4").unwrap();

        assert_eq!(candidates[0].title, "Example Show");
        assert_eq!(candidates[0].episode_number, Some(1));
        assert_eq!(candidates[0].version_name, "第一季");
        assert_eq!(candidates[0].version_dir_path, "Quark/Example Show/第一季");
    }

    #[test]
    fn treats_subtitle_quality_directories_as_version_context() {
        let candidates = parse_media_path_candidates(
            "webdav",
            "/夸克/来自：分享/去有风的地方（2023）全40集/1080P 内封简繁英字幕/01.mkv",
        )
        .unwrap();

        assert_eq!(candidates[0].title, "去有风的地方");
        assert_eq!(
            candidates[0].source_path,
            "夸克/来自：分享/去有风的地方（2023）全40集"
        );
        assert_eq!(
            candidates[0].version_dir_path,
            "夸克/来自：分享/去有风的地方（2023）全40集/1080P 内封简繁英字幕"
        );
        assert!(candidates[0].version_name.contains("1080P"));
        assert!(candidates[0].version_name.contains("内封"));
        assert!(candidates[0].version_name.contains("简繁英字幕"));
        assert_eq!(candidates[0].episode_number, Some(1));
    }

    #[test]
    fn keeps_title_directory_when_it_contains_quality_tags() {
        let candidates = parse_media_path_candidates(
            "webdav",
            "/夸克1/来自：分享/Q 去有风的地方（2023）全40集 内封字幕 4K+1080P/1080P 内封简繁英字幕/01.mkv",
        )
        .unwrap();

        assert_eq!(candidates[0].title, "Q 去有风的地方");
        assert_eq!(
            candidates[0].source_path,
            "夸克1/来自：分享/Q 去有风的地方（2023）全40集 内封字幕 4K+1080P"
        );
        assert_eq!(
            candidates[0].version_dir_path,
            "夸克1/来自：分享/Q 去有风的地方（2023）全40集 内封字幕 4K+1080P/1080P 内封简繁英字幕"
        );
        assert_eq!(candidates[0].version_name, "1080P 内封简繁英字幕");
        assert_eq!(candidates[0].episode_number, Some(1));
    }
}
