pub mod danmu;
pub mod media;
pub mod scanner;
pub mod tmdb;
pub mod webdav;

use std::ffi::{CStr, CString};
use std::os::raw::c_char;

pub use danmu::{DanmuClient, DanmuEvent, DanmuMatchRequest};
pub use media::{parse_media_identity, MediaIdentity, MediaKind};
pub use scanner::{scan_local_videos, scan_local_videos_json, ScannedVideo};
pub use tmdb::{TmdbClient, TmdbMediaType, TmdbSearchItem};
pub use webdav::{RemoteEntry, WebdavClient, WebdavConfig};

#[no_mangle]
pub extern "C" fn player_core_scan_local_videos_json(root: *const c_char) -> *mut c_char {
    ffi_result(|| {
        let root = read_c_string(root)?;
        scan_local_videos_json(&root)
    })
}

#[no_mangle]
pub extern "C" fn player_core_parse_media_identity_json(
    folder_name: *const c_char,
    file_name: *const c_char,
) -> *mut c_char {
    ffi_result(|| {
        let folder_name = read_c_string(folder_name)?;
        let file_name = read_c_string(file_name)?;
        serde_json::to_string(&parse_media_identity(&folder_name, &file_name))
            .map_err(anyhow::Error::from)
    })
}

#[no_mangle]
pub extern "C" fn player_core_free_string(value: *mut c_char) {
    if !value.is_null() {
        unsafe {
            let _ = CString::from_raw(value);
        }
    }
}

fn read_c_string(value: *const c_char) -> anyhow::Result<String> {
    if value.is_null() {
        anyhow::bail!("received null string pointer");
    }
    let text = unsafe { CStr::from_ptr(value) };
    Ok(text.to_str()?.to_string())
}

fn ffi_result(run: impl FnOnce() -> anyhow::Result<String>) -> *mut c_char {
    #[derive(serde::Serialize)]
    struct Response {
        ok: bool,
        data: Option<String>,
        error: Option<String>,
    }

    let response = match run() {
        Ok(data) => Response {
            ok: true,
            data: Some(data),
            error: None,
        },
        Err(error) => Response {
            ok: false,
            data: None,
            error: Some(error.to_string()),
        },
    };

    let json = serde_json::to_string(&response).unwrap_or_else(|error| {
        format!(
            "{{\"ok\":false,\"data\":null,\"error\":\"failed to serialize ffi response: {error}\"}}"
        )
    });
    CString::new(json).expect("json response must not contain nul").into_raw()
}
