pub mod danmu;
pub mod media;
pub mod metadata_cache;
pub mod scanner;
pub mod tmdb;
pub mod webdav;

use std::ffi::{CStr, CString};
use std::os::raw::c_char;

pub use danmu::{DanmuClient, DanmuEvent, DanmuMatchRequest};
pub use media::{parse_media_identity, MediaIdentity, MediaKind};
pub use metadata_cache::{get_all_metadata_json, put_metadata_json, replace_all_metadata_json};
pub use scanner::{
    list_local_directory, list_local_directory_json, scan_local_videos, scan_local_videos_json,
    LocalDirectoryEntry, ScannedVideo,
};
pub use tmdb::{TmdbClient, TmdbMediaType, TmdbSearchItem};
pub use webdav::{
    parse_webdav_entries, parse_webdav_entries_json, RemoteEntry, WebdavClient, WebdavConfig,
    WebdavDirectoryEntry,
};

#[no_mangle]
pub extern "C" fn player_core_scan_local_videos_json(root: *const c_char) -> *mut c_char {
    ffi_result(|| {
        let root = read_c_string(root)?;
        scan_local_videos_json(&root)
    })
}

#[no_mangle]
pub extern "C" fn player_core_list_local_directory_json(root: *const c_char) -> *mut c_char {
    ffi_result(|| {
        let root = read_c_string(root)?;
        list_local_directory_json(&root)
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
pub extern "C" fn player_core_parse_webdav_entries_json(
    body: *const c_char,
    base_url: *const c_char,
    request_url: *const c_char,
    current_path: *const c_char,
) -> *mut c_char {
    ffi_result(|| {
        let body = read_c_string(body)?;
        let base_url = read_c_string(base_url)?;
        let request_url = read_c_string(request_url)?;
        let current_path = read_c_string(current_path)?;
        parse_webdav_entries_json(&body, &base_url, &request_url, &current_path)
    })
}

#[no_mangle]
pub extern "C" fn player_core_tmdb_get_json(
    url: *const c_char,
    access_token: *const c_char,
    proxy_url: *const c_char,
) -> *mut c_char {
    ffi_result(|| {
        let url = read_c_string(url)?;
        let access_token = read_c_string(access_token)?;
        let proxy_url = read_c_string(proxy_url)?;
        let runtime = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()?;
        runtime.block_on(async move {
            let mut builder = reqwest::Client::builder()
                .timeout(std::time::Duration::from_secs(8))
                .user_agent("player_flutter/0.1");
            if !proxy_url.trim().is_empty() {
                builder = builder.proxy(reqwest::Proxy::all(proxy_url.trim())?);
            }
            let client = builder.build()?;
            tmdb_get_json_once(&client, &url, access_token.trim()).await
        })
    })
}

#[no_mangle]
pub extern "C" fn player_core_metadata_put_json(
    db_path: *const c_char,
    item_id: *const c_char,
    metadata_json: *const c_char,
) -> *mut c_char {
    ffi_result(|| {
        let db_path = read_c_string(db_path)?;
        let item_id = read_c_string(item_id)?;
        let metadata_json = read_c_string(metadata_json)?;
        put_metadata_json(&db_path, &item_id, &metadata_json)?;
        Ok("{}".to_string())
    })
}

#[no_mangle]
pub extern "C" fn player_core_metadata_get_all_json(db_path: *const c_char) -> *mut c_char {
    ffi_result(|| {
        let db_path = read_c_string(db_path)?;
        get_all_metadata_json(&db_path)
    })
}

#[no_mangle]
pub extern "C" fn player_core_metadata_replace_all_json(
    db_path: *const c_char,
    metadata_map_json: *const c_char,
) -> *mut c_char {
    ffi_result(|| {
        let db_path = read_c_string(db_path)?;
        let metadata_map_json = read_c_string(metadata_map_json)?;
        replace_all_metadata_json(&db_path, &metadata_map_json)?;
        Ok("{}".to_string())
    })
}

async fn tmdb_get_json_once(
    client: &reqwest::Client,
    url: &str,
    access_token: &str,
) -> anyhow::Result<String> {
    let response = client
        .get(url)
        .bearer_auth(access_token)
        .header("accept", "application/json")
        .send()
        .await?;
    let status = response.status();
    let body = response.text().await?;
    if !status.is_success() {
        anyhow::bail!("TMDB {status}: {body}");
    }
    Ok(body)
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
    CString::new(json)
        .expect("json response must not contain nul")
        .into_raw()
}
