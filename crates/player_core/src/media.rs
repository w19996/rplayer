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

pub fn media_series_title_json(source_type: &str, path: &str) -> Result<String> {
    let source_type = CString::new(source_type).context("source type contains nul byte")?;
    let path = CString::new(path).context("path contains nul byte")?;
    cpp_string(|| unsafe {
        player_core_cpp_media_series_title_json(source_type.as_ptr(), path.as_ptr())
    })
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
    fn player_core_cpp_parse_media_identity_json(
        folder_name: *const c_char,
        file_name: *const c_char,
    ) -> *mut c_char;
    fn player_core_cpp_media_series_title_json(
        source_type: *const c_char,
        path: *const c_char,
    ) -> *mut c_char;
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
}
