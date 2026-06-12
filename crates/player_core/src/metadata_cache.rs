use anyhow::Result;
use base64::{engine::general_purpose, Engine as _};
use rusqlite::{params, Connection};
use serde_json::{Map, Value};
use std::collections::HashSet;
use url::Url;

pub fn put_metadata_json(
    db_path: &str,
    title_key: &str,
    item_id: &str,
    metadata_json: &str,
) -> Result<()> {
    let value: Value = serde_json::from_str(metadata_json)?;
    let tmdb_id = value.get("tmdbId").and_then(Value::as_i64);
    let media_type = value.get("mediaType").and_then(Value::as_str);
    let updated_at = value.get("updatedAt").and_then(Value::as_i64);
    let title_json = title_json(&value).to_string();
    let episode_json = episode_json(&value).to_string();
    let conn = open(db_path)?;
    conn.execute(
        "insert into metadata_titles(title_key, tmdb_id, media_type, json, updated_at)
         values (?1, ?2, ?3, ?4, ?5)
         on conflict(title_key) do update set
           tmdb_id=excluded.tmdb_id,
           media_type=excluded.media_type,
           json=excluded.json,
           updated_at=excluded.updated_at",
        params![title_key, tmdb_id, media_type, title_json, updated_at],
    )?;
    conn.execute(
        "insert into metadata_episodes(item_id, title_key, json, updated_at)
         values (?1, ?2, ?3, ?4)
         on conflict(item_id) do update set
           title_key=excluded.title_key,
           json=excluded.json,
           updated_at=excluded.updated_at",
        params![item_id, title_key, episode_json, updated_at],
    )?;
    upsert_tmdb_metadata(&conn, title_key, item_id, &value)?;
    Ok(())
}

pub fn get_all_metadata_json(db_path: &str) -> Result<String> {
    let conn = open(db_path)?;
    migrate_legacy_metadata(&conn)?;
    let mut stmt = conn.prepare(
        "select e.item_id, t.json, e.json
         from metadata_episodes e
         join metadata_titles t on t.title_key = e.title_key
         order by e.item_id",
    )?;
    let rows = stmt.query_map([], |row| {
        Ok((
            row.get::<_, String>(0)?,
            row.get::<_, String>(1)?,
            row.get::<_, String>(2)?,
        ))
    })?;

    let mut map = Map::new();
    for row in rows {
        let (item_id, title_json, episode_json) = row?;
        let mut value: Value = serde_json::from_str(&title_json)?;
        merge_json(&mut value, serde_json::from_str(&episode_json)?);
        if let Value::Object(object) = &mut value {
            object.insert("itemId".to_string(), Value::String(item_id.clone()));
        }
        map.insert(item_id, value);
    }
    Ok(Value::Object(map).to_string())
}

pub fn put_app_state_json(db_path: &str, state_json: &str) -> Result<()> {
    let conn = open(db_path)?;
    sync_library_from_state_json(&conn, state_json)?;
    conn.execute("delete from app_state where key='media_state'", [])?;
    Ok(())
}

pub fn get_app_state_json(db_path: &str) -> Result<String> {
    let conn = open(db_path)?;
    export_library_state_json(&conn)
}

pub fn get_cached_image_json(db_path: &str, path: &str, size: &str) -> Result<String> {
    let conn = open(db_path)?;
    let image_key = format!("{size}:{path}");
    let value = conn.query_row(
        "select content_type, bytes from image_cache where cache_key=?1 and bytes is not null
         union all
         select content_type, bytes from metadata_images where image_key=?1
         limit 1",
        params![image_key],
        |row| {
            let content_type: Option<String> = row.get(0)?;
            let bytes: Vec<u8> = row.get(1)?;
            Ok((content_type, bytes))
        },
    );
    let (content_type, bytes) = match value {
        Ok(value) => value,
        Err(rusqlite::Error::QueryReturnedNoRows) => return Ok("null".to_string()),
        Err(error) => return Err(error.into()),
    };
    let mut object = Map::new();
    object.insert(
        "contentType".to_string(),
        content_type.map(Value::String).unwrap_or(Value::Null),
    );
    object.insert(
        "bytesBase64".to_string(),
        Value::String(general_purpose::STANDARD.encode(bytes)),
    );
    Ok(Value::Object(object).to_string())
}

pub fn put_cached_image_json(db_path: &str, image_json: &str) -> Result<()> {
    let conn = open(db_path)?;
    let value: Value = serde_json::from_str(image_json)?;
    let path = value
        .get("path")
        .and_then(Value::as_str)
        .unwrap_or("")
        .trim();
    let size = value
        .get("size")
        .and_then(Value::as_str)
        .unwrap_or("")
        .trim();
    let url = value.get("url").and_then(Value::as_str).unwrap_or("");
    let content_type = value.get("contentType").and_then(Value::as_str);
    let bytes_base64 = value
        .get("bytesBase64")
        .and_then(Value::as_str)
        .unwrap_or("");
    if path.is_empty() || size.is_empty() || bytes_base64.is_empty() {
        return Ok(());
    }
    let normalized_path = if path.starts_with('/') {
        path.to_string()
    } else {
        format!("/{path}")
    };
    let bytes = general_purpose::STANDARD.decode(bytes_base64)?;
    let key = format!("{size}:{normalized_path}");
    conn.execute(
        "insert or replace into image_cache(
           cache_key, provider, file_path, size, url, content_type, bytes,
           byte_count, fetched_at
         )
         values (?1, 'tmdb', ?2, ?3, ?4, ?5, ?6, ?7, ?8)",
        params![
            key,
            normalized_path,
            size,
            url,
            content_type,
            bytes.as_slice(),
            bytes.len() as i64,
            now_ms()
        ],
    )?;
    Ok(())
}

pub fn query_home_json(db_path: &str) -> Result<String> {
    let conn = open(db_path)?;
    let mut stmt = conn.prepare(
        "select
           sf.id,
           sf.source_id,
           sf.path,
           s.id,
           s.tmdb_id,
           s.name,
           s.overview,
           s.poster_path,
           s.backdrop_path,
           s.vote_average,
           s.first_air_date,
           s.number_of_episodes,
           count(distinct mf.id),
           max(pp.last_played_at),
           coalesce(sf.search_hint, min(mf.guess_title), sf.path)
         from source_folders sf
         join media_files mf on mf.folder_id = sf.id and mf.scan_status = 'active'
         left join source_folder_matches sfm on sfm.folder_id = sf.id
         left join tmdb_tv_shows s on s.id = sfm.show_id
         left join playback_progress pp on pp.file_id = mf.id
         group by sf.id, s.id
         order by s.id is null, max(pp.last_played_at) is null, max(pp.last_played_at) desc, coalesce(s.name, sf.path)",
    )?;
    let rows = stmt.query_map([], |row| {
        let mut object = Map::new();
        object.insert("folderId".to_string(), Value::from(row.get::<_, i64>(0)?));
        object.insert(
            "sourceId".to_string(),
            Value::from(row.get::<_, String>(1)?),
        );
        object.insert(
            "folderPath".to_string(),
            Value::from(row.get::<_, String>(2)?),
        );
        let show_id = row.get::<_, Option<i64>>(3)?;
        let tmdb_id = row.get::<_, Option<i64>>(4)?;
        insert_optional_i64(&mut object, "showId", show_id);
        insert_optional_i64(&mut object, "tmdbId", tmdb_id);
        let fallback_title = row.get::<_, String>(14)?;
        let title = row
            .get::<_, Option<String>>(5)?
            .filter(|value| !value.trim().is_empty())
            .unwrap_or_else(|| display_name_from_path(&fallback_title));
        object.insert("title".to_string(), Value::from(title));
        insert_optional_string(&mut object, "overview", row.get::<_, Option<String>>(6)?);
        insert_optional_string(&mut object, "posterPath", row.get::<_, Option<String>>(7)?);
        insert_optional_string(
            &mut object,
            "backdropPath",
            row.get::<_, Option<String>>(8)?,
        );
        insert_optional_f64(&mut object, "voteAverage", row.get::<_, Option<f64>>(9)?);
        insert_optional_string(
            &mut object,
            "releaseDate",
            row.get::<_, Option<String>>(10)?,
        );
        insert_optional_i64(&mut object, "totalEpisodes", row.get::<_, Option<i64>>(11)?);
        object.insert(
            "localFileCount".to_string(),
            Value::from(row.get::<_, i64>(12)?),
        );
        insert_optional_i64(
            &mut object,
            "latestPlayedAt",
            row.get::<_, Option<i64>>(13)?,
        );
        object.insert("matched".to_string(), Value::from(show_id.is_some()));
        Ok(Value::Object(object))
    })?;
    let mut values = Vec::new();
    for row in rows {
        values.push(row?);
    }
    Ok(Value::Array(values).to_string())
}

pub fn query_show_detail_json(db_path: &str, folder_key: &str) -> Result<String> {
    let conn = open(db_path)?;
    let (source_id, group_path) = parse_group_key(folder_key).unwrap_or_default();
    let like = if group_path.ends_with('/') {
        format!("{group_path}%")
    } else {
        format!("{group_path}/%")
    };
    let mut stmt = conn.prepare(
        "select
           mf.id,
           mf.legacy_item_id,
           mf.relative_path,
           mf.filename,
           mf.size,
           mf.guess_season,
           mf.guess_episode,
           pp.position_ms,
           pp.duration_ms,
           pp.last_played_at,
           s.id,
           s.tmdb_id,
           s.name,
           s.original_name,
           s.overview,
           s.poster_path,
           s.backdrop_path,
           s.logo_path,
           s.vote_average,
           s.first_air_date,
           s.number_of_seasons,
           s.number_of_episodes,
           e.id,
           e.season_number,
           e.episode_number,
           e.name,
           e.overview,
           e.air_date,
           e.runtime,
           e.still_path
         from media_files mf
         left join playback_progress pp on pp.file_id = mf.id
         left join media_file_matches mfm on mfm.file_id = mf.id
         left join tmdb_tv_shows s on s.id = mfm.show_id
         left join tmdb_tv_episodes e on e.id = mfm.episode_id
         where mf.scan_status = 'active'
           and (?1 = '' or mf.source_id = ?1)
           and (?2 = '' or mf.relative_path = ?2 or mf.relative_path like ?3)
         order by coalesce(e.season_number, mf.guess_season, 1),
                  coalesce(e.episode_number, mf.guess_episode, 999999),
                  mf.filename",
    )?;
    let rows = stmt.query_map(params![source_id, group_path, like], |row| {
        let mut object = Map::new();
        object.insert("fileId".to_string(), Value::from(row.get::<_, i64>(0)?));
        object.insert(
            "legacyItemId".to_string(),
            Value::from(row.get::<_, String>(1)?),
        );
        object.insert(
            "relativePath".to_string(),
            Value::from(row.get::<_, String>(2)?),
        );
        object.insert(
            "filename".to_string(),
            Value::from(row.get::<_, String>(3)?),
        );
        insert_optional_i64(&mut object, "size", row.get::<_, Option<i64>>(4)?);
        insert_optional_i64(&mut object, "guessSeason", row.get::<_, Option<i64>>(5)?);
        insert_optional_i64(&mut object, "guessEpisode", row.get::<_, Option<i64>>(6)?);
        insert_optional_i64(&mut object, "positionMs", row.get::<_, Option<i64>>(7)?);
        insert_optional_i64(&mut object, "durationMs", row.get::<_, Option<i64>>(8)?);
        insert_optional_i64(&mut object, "lastPlayedAt", row.get::<_, Option<i64>>(9)?);
        insert_optional_i64(&mut object, "showId", row.get::<_, Option<i64>>(10)?);
        insert_optional_i64(&mut object, "tmdbId", row.get::<_, Option<i64>>(11)?);
        insert_optional_string(&mut object, "showTitle", row.get::<_, Option<String>>(12)?);
        insert_optional_string(
            &mut object,
            "originalTitle",
            row.get::<_, Option<String>>(13)?,
        );
        insert_optional_string(
            &mut object,
            "showOverview",
            row.get::<_, Option<String>>(14)?,
        );
        insert_optional_string(&mut object, "posterPath", row.get::<_, Option<String>>(15)?);
        insert_optional_string(
            &mut object,
            "backdropPath",
            row.get::<_, Option<String>>(16)?,
        );
        insert_optional_string(&mut object, "logoPath", row.get::<_, Option<String>>(17)?);
        insert_optional_f64(&mut object, "voteAverage", row.get::<_, Option<f64>>(18)?);
        insert_optional_string(
            &mut object,
            "releaseDate",
            row.get::<_, Option<String>>(19)?,
        );
        insert_optional_i64(&mut object, "totalSeasons", row.get::<_, Option<i64>>(20)?);
        insert_optional_i64(&mut object, "totalEpisodes", row.get::<_, Option<i64>>(21)?);
        insert_optional_i64(&mut object, "episodeId", row.get::<_, Option<i64>>(22)?);
        insert_optional_i64(&mut object, "seasonNumber", row.get::<_, Option<i64>>(23)?);
        insert_optional_i64(&mut object, "episodeNumber", row.get::<_, Option<i64>>(24)?);
        insert_optional_string(
            &mut object,
            "episodeName",
            row.get::<_, Option<String>>(25)?,
        );
        insert_optional_string(
            &mut object,
            "episodeOverview",
            row.get::<_, Option<String>>(26)?,
        );
        insert_optional_string(
            &mut object,
            "episodeAirDate",
            row.get::<_, Option<String>>(27)?,
        );
        insert_optional_i64(&mut object, "runtime", row.get::<_, Option<i64>>(28)?);
        insert_optional_string(&mut object, "stillPath", row.get::<_, Option<String>>(29)?);
        Ok(Value::Object(object))
    })?;
    let mut files = Vec::new();
    for row in rows {
        files.push(row?);
    }
    let show_id = files
        .iter()
        .filter_map(|value| value.get("showId").and_then(Value::as_i64))
        .next();
    let mut object = Map::new();
    object.insert("folderKey".to_string(), Value::from(folder_key));
    if let Some(show_id) = show_id {
        object.insert("castNames".to_string(), query_cast_names(&conn, show_id)?);
        object.insert(
            "profilePaths".to_string(),
            query_profile_paths(&conn, show_id)?,
        );
        object.insert("genres".to_string(), query_show_genres(&conn, show_id)?);
    }
    object.insert("files".to_string(), Value::Array(files));
    Ok(Value::Object(object).to_string())
}

pub fn query_recent_json(db_path: &str) -> Result<String> {
    let conn = open(db_path)?;
    let mut stmt = conn.prepare(
        "select
           mf.id,
           mf.legacy_item_id,
           mf.relative_path,
           mf.filename,
           mf.size,
           pp.position_ms,
           pp.duration_ms,
           pp.last_played_at,
           s.name,
           s.poster_path,
           s.backdrop_path,
           e.season_number,
           e.episode_number,
           e.name,
           e.still_path
         from playback_progress pp
         join media_files mf on mf.id = pp.file_id and mf.scan_status = 'active'
         left join media_file_matches mfm on mfm.file_id = mf.id
         left join tmdb_tv_shows s on s.id = mfm.show_id
         left join tmdb_tv_episodes e on e.id = mfm.episode_id
         where pp.last_played_at is not null
         order by pp.last_played_at desc",
    )?;
    let rows = stmt.query_map([], |row| {
        let mut object = Map::new();
        object.insert("fileId".to_string(), Value::from(row.get::<_, i64>(0)?));
        object.insert(
            "legacyItemId".to_string(),
            Value::from(row.get::<_, String>(1)?),
        );
        object.insert(
            "relativePath".to_string(),
            Value::from(row.get::<_, String>(2)?),
        );
        object.insert(
            "filename".to_string(),
            Value::from(row.get::<_, String>(3)?),
        );
        insert_optional_i64(&mut object, "size", row.get::<_, Option<i64>>(4)?);
        object.insert("positionMs".to_string(), Value::from(row.get::<_, i64>(5)?));
        insert_optional_i64(&mut object, "durationMs", row.get::<_, Option<i64>>(6)?);
        insert_optional_i64(&mut object, "lastPlayedAt", row.get::<_, Option<i64>>(7)?);
        insert_optional_string(&mut object, "showTitle", row.get::<_, Option<String>>(8)?);
        insert_optional_string(&mut object, "posterPath", row.get::<_, Option<String>>(9)?);
        insert_optional_string(
            &mut object,
            "backdropPath",
            row.get::<_, Option<String>>(10)?,
        );
        insert_optional_i64(&mut object, "seasonNumber", row.get::<_, Option<i64>>(11)?);
        insert_optional_i64(&mut object, "episodeNumber", row.get::<_, Option<i64>>(12)?);
        insert_optional_string(
            &mut object,
            "episodeName",
            row.get::<_, Option<String>>(13)?,
        );
        insert_optional_string(&mut object, "stillPath", row.get::<_, Option<String>>(14)?);
        Ok(Value::Object(object))
    })?;
    let mut values = Vec::new();
    for row in rows {
        values.push(row?);
    }
    Ok(Value::Array(values).to_string())
}

pub fn replace_all_metadata_json(db_path: &str, metadata_map_json: &str) -> Result<()> {
    let value: Value = serde_json::from_str(metadata_map_json)?;
    let object = value.as_object().cloned().unwrap_or_default();
    let mut conn = open(db_path)?;
    let tx = conn.transaction()?;
    tx.execute("delete from metadata_titles", [])?;
    tx.execute("delete from metadata_episodes", [])?;
    for (item_id, value) in object {
        let title_key = item_id.clone();
        let tmdb_id = value.get("tmdbId").and_then(Value::as_i64);
        let media_type = value.get("mediaType").and_then(Value::as_str);
        let updated_at = value.get("updatedAt").and_then(Value::as_i64);
        tx.execute(
            "insert into metadata_titles(title_key, tmdb_id, media_type, json, updated_at)
             values (?1, ?2, ?3, ?4, ?5)",
            params![
                title_key,
                tmdb_id,
                media_type,
                title_json(&value).to_string(),
                updated_at
            ],
        )?;
        tx.execute(
            "insert into metadata_episodes(item_id, title_key, json, updated_at)
             values (?1, ?2, ?3, ?4)",
            params![
                item_id,
                item_id,
                episode_json(&value).to_string(),
                updated_at
            ],
        )?;
    }
    tx.commit()?;
    Ok(())
}

pub fn prune_metadata_json(
    db_path: &str,
    live_item_ids_json: &str,
    live_title_keys_json: &str,
) -> Result<()> {
    let live_item_ids = string_set_from_json(live_item_ids_json)?;
    let live_title_keys = string_set_from_json(live_title_keys_json)?;
    let conn = open(db_path)?;
    migrate_legacy_metadata(&conn)?;

    let episode_ids = query_string_column(&conn, "select item_id from metadata_episodes")?;
    for item_id in episode_ids {
        if !live_item_ids.contains(&item_id) {
            conn.execute(
                "delete from metadata_episodes where item_id=?1",
                params![item_id],
            )?;
        }
    }

    let legacy_ids = query_string_column(&conn, "select item_id from metadata")?;
    for item_id in legacy_ids {
        if !live_item_ids.contains(&item_id) {
            conn.execute("delete from metadata where item_id=?1", params![item_id])?;
        }
    }

    let title_keys = query_string_column(&conn, "select title_key from metadata_titles")?;
    for title_key in title_keys {
        let has_episode: bool = conn.query_row(
            "select exists(select 1 from metadata_episodes where title_key=?1)",
            params![title_key],
            |row| row.get(0),
        )?;
        if !has_episode || !live_title_keys.contains(&title_key) {
            conn.execute(
                "delete from metadata_titles where title_key=?1",
                params![title_key],
            )?;
        }
    }

    prune_unreferenced_images(&conn)?;
    Ok(())
}

pub async fn cache_images_json(db_path: &str, metadata_json: &str, proxy_url: &str) -> Result<()> {
    let value: Value = serde_json::from_str(metadata_json)?;
    let images = image_specs(&value);
    if images.is_empty() {
        return Ok(());
    }
    let mut builder = reqwest::Client::builder()
        .timeout(std::time::Duration::from_secs(12))
        .user_agent("player_flutter/0.1");
    if !proxy_url.trim().is_empty() {
        builder = builder.proxy(reqwest::Proxy::all(proxy_url.trim())?);
    }
    let client = builder.build()?;
    let conn = open(db_path)?;
    for (path, size) in images {
        let key = format!("{size}:{path}");
        let exists: bool = conn.query_row(
            "select exists(select 1 from metadata_images where image_key=?1)",
            params![key],
            |row| row.get(0),
        )?;
        if exists {
            continue;
        }
        let url = format!(
            "https://image.tmdb.org/t/p/{size}{}",
            if path.starts_with('/') {
                path.clone()
            } else {
                format!("/{path}")
            }
        );
        let response = client.get(&url).send().await?;
        let status = response.status();
        if !status.is_success() {
            continue;
        }
        let content_type = response
            .headers()
            .get(reqwest::header::CONTENT_TYPE)
            .and_then(|value| value.to_str().ok())
            .map(str::to_string);
        let bytes = response.bytes().await?;
        conn.execute(
            "insert or replace into metadata_images(image_key, path, size, url, content_type, bytes, updated_at)
             values (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
            params![
                key,
                path,
                size,
                url,
                content_type,
                bytes.as_ref(),
                now_ms()
            ],
        )?;
        conn.execute(
            "insert or replace into image_cache(
               cache_key, provider, file_path, size, url, content_type, bytes,
               byte_count, fetched_at
             )
             values (?1, 'tmdb', ?2, ?3, ?4, ?5, ?6, ?7, ?8)",
            params![
                key,
                path,
                size,
                url,
                content_type,
                bytes.as_ref(),
                bytes.len() as i64,
                now_ms()
            ],
        )?;
    }
    Ok(())
}

fn open(db_path: &str) -> Result<Connection> {
    let conn = Connection::open(db_path)?;
    conn.execute_batch(
        "create table if not exists metadata(
           item_id text primary key,
           tmdb_id integer,
           media_type text,
           json text not null,
           updated_at integer
         );
         create table if not exists metadata_titles(
           title_key text primary key,
           tmdb_id integer,
           media_type text,
           json text not null,
           updated_at integer
         );
         create table if not exists metadata_episodes(
           item_id text primary key,
           title_key text not null,
           json text not null,
           updated_at integer
         );
         create table if not exists metadata_images(
           image_key text primary key,
           path text not null,
           size text not null,
           url text not null,
           content_type text,
           bytes blob not null,
           updated_at integer
         );
         create table if not exists app_state(
           key text primary key,
           json text not null,
           updated_at integer
         );
         create table if not exists sources(
           id text primary key,
           name text not null,
           type text not null,
           base_url text,
           root_path text default '/',
           username text,
           password text,
           credential_id text,
           created_at integer not null,
           updated_at integer not null
         );
         create table if not exists source_folders(
           id integer primary key autoincrement,
           source_id text not null,
           path text not null,
           selected integer not null default 1,
           search_hint text,
           last_scanned_at integer,
           created_at integer not null,
           updated_at integer not null,
           unique(source_id, path),
           foreign key(source_id) references sources(id) on delete cascade
         );
         create table if not exists media_files(
           id integer primary key autoincrement,
           legacy_item_id text not null unique,
           source_id text not null,
           folder_id integer,
           relative_path text not null,
           filename text not null,
           file_ext text,
           size integer,
           modified_at integer,
           guess_title text,
           guess_season integer,
           guess_episode integer,
           guess_quality text,
           media_kind_hint text,
           scan_status text not null default 'active',
           created_at integer not null,
           updated_at integer not null,
           unique(source_id, relative_path),
           foreign key(source_id) references sources(id) on delete cascade,
           foreign key(folder_id) references source_folders(id) on delete cascade
         );
         create table if not exists playback_progress(
           file_id integer primary key,
           position_ms integer not null default 0,
           duration_ms integer,
           last_played_at integer,
           completed integer not null default 0,
           updated_at integer not null,
           foreign key(file_id) references media_files(id) on delete cascade
         );
         create table if not exists folder_preferences(
           folder_id integer primary key,
           preferred_orientation text,
           sort_mode text,
           view_mode text,
           extra_json text,
           updated_at integer not null,
           foreign key(folder_id) references source_folders(id) on delete cascade
         );
         create table if not exists match_tasks(
           id integer primary key autoincrement,
           folder_id integer,
           search_query text not null,
           detected_seasons text,
           detected_episodes text,
           file_count integer not null default 0,
           status text not null default 'pending',
           selected_show_id integer,
           created_at integer not null,
           updated_at integer not null,
           foreign key(folder_id) references source_folders(id) on delete cascade,
           foreign key(selected_show_id) references tmdb_tv_shows(id) on delete set null
         );
         create table if not exists match_candidates(
           id integer primary key autoincrement,
           task_id integer not null,
           tmdb_id integer not null,
           tmdb_name text,
           tmdb_original_name text,
           first_air_date text,
           overview text,
           poster_path text,
           score real,
           raw_json text,
           created_at integer not null,
           unique(task_id, tmdb_id),
           foreign key(task_id) references match_tasks(id) on delete cascade
         );
         create table if not exists tmdb_tv_shows(
           id integer primary key autoincrement,
           tmdb_id integer not null unique,
           name text not null,
           original_name text,
           overview text,
           first_air_date text,
           last_air_date text,
           status text,
           type text,
           original_language text,
           number_of_seasons integer,
           number_of_episodes integer,
           poster_path text,
           backdrop_path text,
           logo_path text,
           vote_average real,
           vote_count integer,
           popularity real,
           fetched_language text not null,
           raw_json text,
           last_synced_at integer not null,
           created_at integer not null,
           updated_at integer not null
         );
         create table if not exists tmdb_tv_seasons(
           id integer primary key autoincrement,
           show_id integer not null,
           tmdb_id integer,
           season_number integer not null,
           name text,
           overview text,
           air_date text,
           episode_count integer,
           poster_path text,
           vote_average real,
           fetched_language text not null,
           raw_json text,
           last_synced_at integer,
           created_at integer not null,
           updated_at integer not null,
           unique(show_id, season_number),
           foreign key(show_id) references tmdb_tv_shows(id) on delete cascade
         );
         create table if not exists tmdb_tv_episodes(
           id integer primary key autoincrement,
           show_id integer not null,
           season_id integer not null,
           tmdb_id integer,
           season_number integer not null,
           episode_number integer not null,
           name text,
           overview text,
           air_date text,
           runtime integer,
           still_path text,
           episode_type text,
           production_code text,
           vote_average real,
           vote_count integer,
           fetched_language text not null,
           raw_json text,
           last_synced_at integer,
           created_at integer not null,
           updated_at integer not null,
           unique(show_id, season_number, episode_number),
           foreign key(show_id) references tmdb_tv_shows(id) on delete cascade,
           foreign key(season_id) references tmdb_tv_seasons(id) on delete cascade
         );
         create table if not exists source_folder_matches(
           id integer primary key autoincrement,
           folder_id integer not null,
           show_id integer not null,
           provider text not null default 'tmdb',
           match_status text not null,
           search_query text,
           selected_tmdb_id integer not null,
           matched_by text,
           created_at integer not null,
           updated_at integer not null,
           unique(folder_id, provider),
           foreign key(folder_id) references source_folders(id) on delete cascade,
           foreign key(show_id) references tmdb_tv_shows(id) on delete cascade
         );
         create table if not exists media_file_matches(
           id integer primary key autoincrement,
           file_id integer not null,
           show_id integer not null,
           season_id integer,
           episode_id integer,
           provider text not null default 'tmdb',
           match_status text not null,
           match_score real,
           search_query text,
           selected_tmdb_id integer,
           matched_by text,
           created_at integer not null,
           updated_at integer not null,
           unique(file_id),
           foreign key(file_id) references media_files(id) on delete cascade,
           foreign key(show_id) references tmdb_tv_shows(id) on delete cascade,
           foreign key(season_id) references tmdb_tv_seasons(id) on delete set null,
           foreign key(episode_id) references tmdb_tv_episodes(id) on delete set null
         );
         create table if not exists tmdb_images(
           id integer primary key autoincrement,
           owner_type text not null,
           owner_id integer not null,
           image_type text not null,
           file_path text not null,
           width integer,
           height integer,
           language text,
           aspect_ratio real,
           vote_average real,
           vote_count integer,
           created_at integer not null,
           updated_at integer not null,
           unique(owner_type, owner_id, image_type, file_path)
         );
         create table if not exists image_cache(
           cache_key text primary key,
           provider text not null default 'tmdb',
           file_path text not null,
           size text not null,
           url text,
           content_type text,
           bytes blob,
           local_cache_path text,
           byte_count integer,
           fetched_at integer not null,
           expires_at integer,
           unique(provider, file_path, size)
         );
         create table if not exists tmdb_people_cache(
           id integer primary key autoincrement,
           tmdb_id integer unique,
           name text not null,
           profile_path text,
           raw_json text,
           updated_at integer not null
         );
         create table if not exists tmdb_credits(
           id integer primary key autoincrement,
           owner_type text not null,
           owner_id integer not null,
           person_id integer,
           credit_type text not null,
           character_name text,
           job text,
           department text,
           credit_order integer,
           raw_json text,
           unique(owner_type, owner_id, person_id, credit_type, character_name, job),
           foreign key(person_id) references tmdb_people_cache(id) on delete set null
         );
         create table if not exists api_cache(
           cache_key text primary key,
           provider text not null,
           endpoint text not null,
           request_url text,
           params_json text,
           response_json text not null,
           fetched_at integer not null,
           expires_at integer
         );
         create table if not exists metadata_sync_state(
           id integer primary key autoincrement,
           provider text not null,
           entity_type text not null,
           entity_id integer not null,
           language text not null,
           sync_status text not null,
           last_synced_at integer,
           next_sync_at integer,
           retry_count integer default 0,
           error_message text,
           unique(provider, entity_type, entity_id, language)
         );
         create index if not exists idx_metadata_tmdb on metadata(tmdb_id, media_type);
         create index if not exists idx_metadata_titles_tmdb on metadata_titles(tmdb_id, media_type);
         create index if not exists idx_metadata_episodes_title on metadata_episodes(title_key);
         create index if not exists idx_source_folders_source on source_folders(source_id);
         create index if not exists idx_media_files_folder on media_files(folder_id);
         create index if not exists idx_media_files_source_path on media_files(source_id, relative_path);
         create index if not exists idx_media_files_guess on media_files(guess_title, guess_season, guess_episode);
         create index if not exists idx_playback_recent on playback_progress(last_played_at desc);
         create index if not exists idx_folder_matches_folder on source_folder_matches(folder_id);
         create index if not exists idx_folder_matches_show on source_folder_matches(show_id);
         create index if not exists idx_file_matches_episode on media_file_matches(episode_id);
         create index if not exists idx_tmdb_episodes_lookup on tmdb_tv_episodes(show_id, season_number, episode_number);
          create index if not exists idx_image_cache_path_size on image_cache(provider, file_path, size);",
    )?;
    add_column_if_missing(&conn, "sources", "username", "text")?;
    add_column_if_missing(&conn, "sources", "password", "text")?;
    conn.execute_batch("pragma foreign_keys = on;")?;
    Ok(conn)
}

fn add_column_if_missing(
    conn: &Connection,
    table: &str,
    column: &str,
    definition: &str,
) -> Result<()> {
    let mut stmt = conn.prepare(&format!("pragma table_info({table})"))?;
    let rows = stmt.query_map([], |row| row.get::<_, String>(1))?;
    for row in rows {
        if row? == column {
            return Ok(());
        }
    }
    conn.execute_batch(&format!(
        "alter table {table} add column {column} {definition};"
    ))?;
    Ok(())
}

fn export_library_state_json(conn: &Connection) -> Result<String> {
    let mut sources = Vec::new();
    let mut stmt = conn.prepare(
        "select id, name, type, coalesce(base_url, ''), coalesce(root_path, '/'),
                coalesce(username, ''), coalesce(password, '')
         from sources
         order by created_at, id",
    )?;
    let rows = stmt.query_map([], |row| {
        Ok((
            row.get::<_, String>(0)?,
            row.get::<_, String>(1)?,
            row.get::<_, String>(2)?,
            row.get::<_, String>(3)?,
            row.get::<_, String>(4)?,
            row.get::<_, String>(5)?,
            row.get::<_, String>(6)?,
        ))
    })?;
    for row in rows {
        let (id, name, source_type, base_url, root_path, username, password) = row?;
        let selected_paths = query_selected_paths(conn, &id)?;
        let mut object = Map::new();
        object.insert("id".to_string(), Value::String(id));
        object.insert("name".to_string(), Value::String(name));
        object.insert("type".to_string(), Value::String(source_type));
        object.insert("directory".to_string(), Value::String(root_path));
        object.insert("baseUrl".to_string(), Value::String(base_url));
        object.insert("username".to_string(), Value::String(username));
        object.insert("password".to_string(), Value::String(password));
        object.insert(
            "selectedPaths".to_string(),
            Value::Array(selected_paths.into_iter().map(Value::String).collect()),
        );
        sources.push(Value::Object(object));
    }

    let mut items = Vec::new();
    let mut stmt = conn.prepare(
        "select mf.legacy_item_id, mf.source_id, s.name, s.type,
                coalesce(s.base_url, ''), mf.relative_path, mf.filename,
                coalesce(mf.guess_title, ''), mf.guess_season, mf.guess_episode,
                coalesce(mf.media_kind_hint, 'Unknown'), mf.size
         from media_files mf
         join sources s on s.id = mf.source_id
         where mf.scan_status='active'
         order by mf.created_at, mf.id",
    )?;
    let rows = stmt.query_map([], |row| {
        Ok((
            row.get::<_, String>(0)?,
            row.get::<_, String>(1)?,
            row.get::<_, String>(2)?,
            row.get::<_, String>(3)?,
            row.get::<_, String>(4)?,
            row.get::<_, String>(5)?,
            row.get::<_, String>(6)?,
            row.get::<_, String>(7)?,
            row.get::<_, Option<i64>>(8)?,
            row.get::<_, Option<i64>>(9)?,
            row.get::<_, String>(10)?,
            row.get::<_, Option<i64>>(11)?,
        ))
    })?;
    for row in rows {
        let (
            id,
            source_id,
            source_name,
            source_type,
            base_url,
            relative_path,
            filename,
            guess_title,
            guess_season,
            guess_episode,
            media_kind,
            size,
        ) = row?;
        let uri = if source_type == "webdav" {
            webdav_uri(&base_url, &relative_path)
        } else {
            relative_path.clone()
        };
        let mut object = Map::new();
        object.insert("id".to_string(), Value::String(id));
        object.insert("sourceId".to_string(), Value::String(source_id));
        object.insert("sourceName".to_string(), Value::String(source_name));
        object.insert("type".to_string(), Value::String(source_type));
        object.insert(
            "title".to_string(),
            Value::String(file_stem(&filename).unwrap_or(filename)),
        );
        object.insert("uri".to_string(), Value::String(uri));
        object.insert(
            "folderTitle".to_string(),
            Value::String(display_name_from_path(&parent_path(&relative_path))),
        );
        object.insert("matchTitle".to_string(), Value::String(guess_title));
        insert_optional_i64(&mut object, "season", guess_season);
        insert_optional_i64(&mut object, "episode", guess_episode);
        object.insert("mediaKind".to_string(), Value::String(media_kind));
        insert_optional_i64(&mut object, "size", size);
        items.push(Value::Object(object));
    }

    let mut progress = Map::new();
    let mut durations = Map::new();
    let mut last_played_at = Map::new();
    let mut stmt = conn.prepare(
        "select mf.legacy_item_id, p.position_ms, p.duration_ms, p.last_played_at
         from playback_progress p
         join media_files mf on mf.id = p.file_id",
    )?;
    let rows = stmt.query_map([], |row| {
        Ok((
            row.get::<_, String>(0)?,
            row.get::<_, i64>(1)?,
            row.get::<_, Option<i64>>(2)?,
            row.get::<_, Option<i64>>(3)?,
        ))
    })?;
    for row in rows {
        let (item_id, position, duration, last_played) = row?;
        progress.insert(item_id.clone(), Value::from(position));
        if let Some(duration) = duration {
            durations.insert(item_id.clone(), Value::from(duration));
        }
        if let Some(last_played) = last_played {
            last_played_at.insert(item_id, Value::from(last_played));
        }
    }

    let mut folder_orientations = Map::new();
    let mut stmt = conn.prepare(
        "select sf.source_id, s.type, sf.path, fp.preferred_orientation
         from folder_preferences fp
         join source_folders sf on sf.id = fp.folder_id
         join sources s on s.id = sf.source_id
         where fp.preferred_orientation is not null",
    )?;
    let rows = stmt.query_map([], |row| {
        Ok((
            row.get::<_, String>(0)?,
            row.get::<_, String>(1)?,
            row.get::<_, String>(2)?,
            row.get::<_, String>(3)?,
        ))
    })?;
    for row in rows {
        let (source_id, source_type, path, orientation) = row?;
        folder_orientations.insert(
            format!("{source_id}:{source_type}:{path}"),
            Value::String(orientation),
        );
    }

    let mut state = Map::new();
    state.insert("version".to_string(), Value::from(2));
    state.insert("sources".to_string(), Value::Array(sources));
    state.insert("items".to_string(), Value::Array(items));
    state.insert("progress".to_string(), Value::Object(progress));
    state.insert("durations".to_string(), Value::Object(durations));
    state.insert("lastPlayedAt".to_string(), Value::Object(last_played_at));
    state.insert(
        "folderOrientations".to_string(),
        Value::Object(folder_orientations),
    );
    Ok(Value::Object(state).to_string())
}

fn query_selected_paths(conn: &Connection, source_id: &str) -> Result<Vec<String>> {
    let mut stmt = conn.prepare(
        "select path from source_folders
         where source_id=?1 and selected=1
         order by path",
    )?;
    let rows = stmt.query_map(params![source_id], |row| row.get::<_, String>(0))?;
    let mut values = Vec::new();
    for row in rows {
        values.push(row?);
    }
    Ok(values)
}

fn migrate_legacy_metadata(conn: &Connection) -> Result<()> {
    let has_titles: bool = conn.query_row(
        "select exists(select 1 from metadata_titles limit 1)",
        [],
        |row| row.get(0),
    )?;
    if has_titles {
        return Ok(());
    }
    let mut stmt = conn.prepare("select item_id, json from metadata")?;
    let rows = stmt.query_map([], |row| {
        Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?))
    })?;
    for row in rows {
        let (item_id, json) = row?;
        let value: Value = serde_json::from_str(&json)?;
        let tmdb_id = value.get("tmdbId").and_then(Value::as_i64);
        let media_type = value.get("mediaType").and_then(Value::as_str);
        let updated_at = value.get("updatedAt").and_then(Value::as_i64);
        conn.execute(
            "insert or ignore into metadata_titles(title_key, tmdb_id, media_type, json, updated_at)
             values (?1, ?2, ?3, ?4, ?5)",
            params![item_id, tmdb_id, media_type, title_json(&value).to_string(), updated_at],
        )?;
        conn.execute(
            "insert or ignore into metadata_episodes(item_id, title_key, json, updated_at)
             values (?1, ?2, ?3, ?4)",
            params![
                item_id,
                item_id,
                episode_json(&value).to_string(),
                updated_at
            ],
        )?;
    }
    Ok(())
}

fn sync_library_from_state_json(conn: &Connection, state_json: &str) -> Result<()> {
    let state: Value = serde_json::from_str(state_json)?;
    let now = now_ms();
    let sources = state
        .get("sources")
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default();
    let items = state
        .get("items")
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default();
    let progress = state
        .get("progress")
        .and_then(Value::as_object)
        .cloned()
        .unwrap_or_default();
    let durations = state
        .get("durations")
        .and_then(Value::as_object)
        .cloned()
        .unwrap_or_default();
    let last_played = state
        .get("lastPlayedAt")
        .and_then(Value::as_object)
        .cloned()
        .unwrap_or_default();
    let folder_orientations = state
        .get("folderOrientations")
        .and_then(Value::as_object)
        .cloned()
        .unwrap_or_default();

    let mut live_source_ids = HashSet::new();
    let mut live_folder_keys = HashSet::new();
    let mut live_item_ids = HashSet::new();

    for source in &sources {
        let Some(source_id) = source.get("id").and_then(Value::as_str) else {
            continue;
        };
        let source_type = source
            .get("type")
            .and_then(Value::as_str)
            .unwrap_or("local");
        let name = source
            .get("name")
            .and_then(Value::as_str)
            .unwrap_or(source_id);
        let base_url = source.get("baseUrl").and_then(Value::as_str).unwrap_or("");
        let root_path = source
            .get("directory")
            .and_then(Value::as_str)
            .unwrap_or(if source_type == "webdav" { "/" } else { "" });
        let username = source.get("username").and_then(Value::as_str).unwrap_or("");
        let password = source.get("password").and_then(Value::as_str).unwrap_or("");
        let credential_id = if source_type == "webdav" {
            Some(format!("source:{source_id}"))
        } else {
            None
        };
        live_source_ids.insert(source_id.to_string());
        conn.execute(
            "insert into sources(id, name, type, base_url, root_path, username, password, credential_id, created_at, updated_at)
             values (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?9)
             on conflict(id) do update set
               name=excluded.name,
               type=excluded.type,
               base_url=excluded.base_url,
               root_path=excluded.root_path,
               username=excluded.username,
               password=excluded.password,
               credential_id=excluded.credential_id,
               updated_at=excluded.updated_at",
            params![
                source_id,
                name,
                source_type,
                empty_to_null(base_url),
                normalize_folder_path(root_path),
                empty_to_null(username),
                empty_to_null(password),
                credential_id,
                now
            ],
        )?;

        let selected_paths: Vec<String> = source
            .get("selectedPaths")
            .and_then(Value::as_array)
            .into_iter()
            .flatten()
            .filter_map(Value::as_str)
            .map(str::to_string)
            .collect();
        for path in selected_paths {
            let normalized = normalize_resource_path(&path);
            let (folder_path, search_hint) = if is_video_resource_path(&normalized) {
                (parent_path(&normalized), file_stem(&normalized))
            } else {
                (normalize_folder_path(&normalized), None)
            };
            upsert_source_folder(conn, source_id, &folder_path, search_hint.as_deref(), now)?;
            live_folder_keys.insert(format!("{source_id}\n{folder_path}"));
        }
    }

    for item in &items {
        let Some(item_id) = item.get("id").and_then(Value::as_str) else {
            continue;
        };
        let Some(source_id) = item.get("sourceId").and_then(Value::as_str) else {
            continue;
        };
        let item_type = item.get("type").and_then(Value::as_str).unwrap_or("local");
        let uri = item.get("uri").and_then(Value::as_str).unwrap_or("");
        let relative_path = item_relative_path(item_type, uri);
        let folder_path = parent_path(&relative_path);
        let folder_id = upsert_source_folder(
            conn,
            source_id,
            &folder_path,
            item.get("matchTitle").and_then(Value::as_str),
            now,
        )?;
        live_folder_keys.insert(format!("{source_id}\n{folder_path}"));
        live_item_ids.insert(item_id.to_string());
        conn.execute(
            "insert into media_files(
               legacy_item_id, source_id, folder_id, relative_path, filename, file_ext,
               size, guess_title, guess_season, guess_episode, guess_quality,
               media_kind_hint, scan_status, created_at, updated_at
             )
             values (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, 'active', ?13, ?13)
             on conflict(legacy_item_id) do update set
               source_id=excluded.source_id,
               folder_id=excluded.folder_id,
               relative_path=excluded.relative_path,
               filename=excluded.filename,
               file_ext=excluded.file_ext,
               size=excluded.size,
               guess_title=excluded.guess_title,
               guess_season=excluded.guess_season,
               guess_episode=excluded.guess_episode,
               guess_quality=excluded.guess_quality,
               media_kind_hint=excluded.media_kind_hint,
               scan_status='active',
               updated_at=excluded.updated_at",
            params![
                item_id,
                source_id,
                folder_id,
                relative_path,
                file_name(&relative_path),
                file_ext(&relative_path),
                item.get("size").and_then(Value::as_i64),
                item.get("matchTitle")
                    .and_then(Value::as_str)
                    .or_else(|| item.get("title").and_then(Value::as_str)),
                item.get("season").and_then(Value::as_i64),
                item.get("episode").and_then(Value::as_i64),
                guess_quality(&relative_path),
                item.get("mediaKind").and_then(Value::as_str),
                now
            ],
        )?;
        let file_id = media_file_id(conn, item_id)?;
        let position = progress.get(item_id).and_then(Value::as_i64).unwrap_or(0);
        let duration = durations.get(item_id).and_then(Value::as_i64);
        let last_played_at = last_played.get(item_id).and_then(Value::as_i64);
        if position > 0 || duration.is_some() || last_played_at.is_some() {
            let completed = duration
                .filter(|duration| *duration > 0)
                .map(|duration| position >= duration.saturating_mul(9) / 10)
                .unwrap_or(false);
            conn.execute(
                "insert into playback_progress(file_id, position_ms, duration_ms, last_played_at, completed, updated_at)
                 values (?1, ?2, ?3, ?4, ?5, ?6)
                 on conflict(file_id) do update set
                   position_ms=excluded.position_ms,
                   duration_ms=excluded.duration_ms,
                   last_played_at=excluded.last_played_at,
                   completed=excluded.completed,
                   updated_at=excluded.updated_at",
                params![file_id, position, duration, last_played_at, completed as i64, now],
            )?;
        }
    }

    for (folder_key, value) in folder_orientations {
        let Some(orientation) = value.as_str() else {
            continue;
        };
        if let Some((source_id, path)) = legacy_folder_key_parts(&folder_key) {
            let folder_id = upsert_source_folder(conn, &source_id, &path, None, now)?;
            live_folder_keys.insert(format!("{source_id}\n{path}"));
            conn.execute(
                "insert into folder_preferences(folder_id, preferred_orientation, updated_at)
                 values (?1, ?2, ?3)
                 on conflict(folder_id) do update set
                   preferred_orientation=excluded.preferred_orientation,
                   updated_at=excluded.updated_at",
                params![folder_id, orientation, now],
            )?;
        }
    }

    for legacy_item_id in query_string_column(conn, "select legacy_item_id from media_files")? {
        if !live_item_ids.contains(&legacy_item_id) {
            conn.execute(
                "delete from media_files where legacy_item_id=?1",
                params![legacy_item_id],
            )?;
        }
    }
    for (source_id, path) in query_source_folders(conn)? {
        if !live_folder_keys.contains(&format!("{source_id}\n{path}")) {
            conn.execute(
                "delete from source_folders where source_id=?1 and path=?2",
                params![source_id, path],
            )?;
        }
    }
    for source_id in query_string_column(conn, "select id from sources")? {
        if !live_source_ids.contains(&source_id) {
            conn.execute("delete from sources where id=?1", params![source_id])?;
        }
    }
    cleanup_orphan_resources(conn)?;
    cleanup_orphan_tmdb(conn)?;
    Ok(())
}

fn upsert_tmdb_metadata(
    conn: &Connection,
    title_key: &str,
    item_id: &str,
    value: &Value,
) -> Result<()> {
    if value.get("mediaType").and_then(Value::as_str) != Some("tv") {
        return Ok(());
    }
    let Some(tmdb_id) = value.get("tmdbId").and_then(Value::as_i64) else {
        return Ok(());
    };
    let now = now_ms();
    let title = value
        .get("title")
        .and_then(Value::as_str)
        .filter(|text| !text.trim().is_empty())
        .unwrap_or("TMDB TV");
    conn.execute(
        "insert into tmdb_tv_shows(
           tmdb_id, name, original_name, overview, first_air_date,
           number_of_seasons, number_of_episodes, poster_path, backdrop_path,
           logo_path, vote_average, fetched_language, raw_json, last_synced_at,
           created_at, updated_at
         )
         values (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, 'unknown', ?12, ?13, ?13, ?13)
         on conflict(tmdb_id) do update set
           name=excluded.name,
           original_name=excluded.original_name,
           overview=excluded.overview,
           first_air_date=excluded.first_air_date,
           number_of_seasons=excluded.number_of_seasons,
           number_of_episodes=excluded.number_of_episodes,
           poster_path=excluded.poster_path,
           backdrop_path=excluded.backdrop_path,
           logo_path=excluded.logo_path,
           vote_average=excluded.vote_average,
           raw_json=excluded.raw_json,
           last_synced_at=excluded.last_synced_at,
           updated_at=excluded.updated_at",
        params![
            tmdb_id,
            title,
            value.get("originalTitle").and_then(Value::as_str),
            value.get("overview").and_then(Value::as_str),
            value.get("releaseDate").and_then(Value::as_str),
            value.get("totalSeasons").and_then(Value::as_i64),
            value.get("totalEpisodes").and_then(Value::as_i64),
            value.get("posterPath").and_then(Value::as_str),
            value.get("backdropPath").and_then(Value::as_str),
            value.get("logoPath").and_then(Value::as_str),
            value.get("voteAverage").and_then(Value::as_f64),
            title_json(value).to_string(),
            now
        ],
    )?;
    let show_id = query_row_id(
        conn,
        "select id from tmdb_tv_shows where tmdb_id=?1",
        tmdb_id,
    )?;
    upsert_tmdb_images(conn, "show", show_id, value, now)?;
    upsert_people_and_credits(conn, show_id, value, now)?;

    let file_id = match media_file_id(conn, item_id) {
        Ok(file_id) => file_id,
        Err(_) => return Ok(()),
    };
    let (folder_id, season, episode, guess_title) = conn.query_row(
        "select folder_id, guess_season, guess_episode, guess_title from media_files where id=?1",
        params![file_id],
        |row| {
            Ok((
                row.get::<_, Option<i64>>(0)?,
                row.get::<_, Option<i64>>(1)?,
                row.get::<_, Option<i64>>(2)?,
                row.get::<_, Option<String>>(3)?,
            ))
        },
    )?;
    if let Some(folder_id) = folder_id {
        conn.execute(
            "insert into source_folder_matches(
               folder_id, show_id, match_status, search_query, selected_tmdb_id,
               matched_by, created_at, updated_at
             )
             values (?1, ?2, 'auto', ?3, ?4, 'metadata-cache', ?5, ?5)
             on conflict(folder_id, provider) do update set
               show_id=excluded.show_id,
               match_status=excluded.match_status,
               search_query=excluded.search_query,
               selected_tmdb_id=excluded.selected_tmdb_id,
               matched_by=excluded.matched_by,
               updated_at=excluded.updated_at",
            params![folder_id, show_id, guess_title, tmdb_id, now],
        )?;
    }

    let season_number = season.unwrap_or(1);
    conn.execute(
        "insert into tmdb_tv_seasons(
           show_id, season_number, fetched_language, last_synced_at, created_at, updated_at
         )
         values (?1, ?2, 'unknown', ?3, ?3, ?3)
         on conflict(show_id, season_number) do update set
           last_synced_at=excluded.last_synced_at,
           updated_at=excluded.updated_at",
        params![show_id, season_number, now],
    )?;
    let season_id: i64 = conn.query_row(
        "select id from tmdb_tv_seasons where show_id=?1 and season_number=?2",
        params![show_id, season_number],
        |row| row.get(0),
    )?;
    let episode_id = if let Some(episode_number) = episode {
        conn.execute(
            "insert into tmdb_tv_episodes(
               show_id, season_id, season_number, episode_number, name, air_date,
               still_path, vote_average, fetched_language, raw_json,
               last_synced_at, created_at, updated_at
             )
             values (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, 'unknown', ?9, ?10, ?10, ?10)
             on conflict(show_id, season_number, episode_number) do update set
               season_id=excluded.season_id,
               name=excluded.name,
               air_date=excluded.air_date,
               still_path=excluded.still_path,
               vote_average=excluded.vote_average,
               raw_json=excluded.raw_json,
               last_synced_at=excluded.last_synced_at,
               updated_at=excluded.updated_at",
            params![
                show_id,
                season_id,
                season_number,
                episode_number,
                value.get("episodeName").and_then(Value::as_str),
                value.get("releaseDate").and_then(Value::as_str),
                value.get("stillPath").and_then(Value::as_str),
                value.get("voteAverage").and_then(Value::as_f64),
                episode_json(value).to_string(),
                now
            ],
        )?;
        Some(conn.query_row(
            "select id from tmdb_tv_episodes where show_id=?1 and season_number=?2 and episode_number=?3",
            params![show_id, season_number, episode_number],
            |row| row.get::<_, i64>(0),
        )?)
    } else {
        None
    };
    conn.execute(
        "insert into media_file_matches(
           file_id, show_id, season_id, episode_id, match_status, match_score,
           search_query, selected_tmdb_id, matched_by, created_at, updated_at
         )
         values (?1, ?2, ?3, ?4, ?5, 1.0, ?6, ?7, 'metadata-cache', ?8, ?8)
         on conflict(file_id) do update set
           show_id=excluded.show_id,
           season_id=excluded.season_id,
           episode_id=excluded.episode_id,
           match_status=excluded.match_status,
           match_score=excluded.match_score,
           search_query=excluded.search_query,
           selected_tmdb_id=excluded.selected_tmdb_id,
           matched_by=excluded.matched_by,
           updated_at=excluded.updated_at",
        params![
            file_id,
            show_id,
            season_id,
            episode_id,
            if episode_id.is_some() {
                "auto"
            } else {
                "unmatched"
            },
            title_key,
            tmdb_id,
            now
        ],
    )?;
    Ok(())
}

fn title_json(value: &Value) -> Value {
    let mut output = value.clone();
    if let Value::Object(object) = &mut output {
        object.remove("itemId");
        object.remove("stillPath");
        object.remove("episodeName");
    }
    output
}

fn episode_json(value: &Value) -> Value {
    let mut object = Map::new();
    for key in [
        "itemId",
        "stillPath",
        "episodeName",
        "releaseDate",
        "voteAverage",
        "updatedAt",
        "schemaVersion",
    ] {
        if let Some(value) = value.get(key) {
            object.insert(key.to_string(), value.clone());
        }
    }
    Value::Object(object)
}

fn merge_json(base: &mut Value, overlay: Value) {
    let (Value::Object(base), Value::Object(overlay)) = (base, overlay) else {
        return;
    };
    for (key, value) in overlay {
        base.insert(key, value);
    }
}

fn image_specs(value: &Value) -> Vec<(String, String)> {
    let mut specs = Vec::new();
    for (key, size) in [
        ("posterPath", "w500"),
        ("backdropPath", "w780"),
        ("stillPath", "w780"),
        ("logoPath", "w300"),
    ] {
        if let Some(path) = value.get(key).and_then(Value::as_str) {
            specs.push((path.to_string(), size.to_string()));
        }
    }
    if let Some(paths) = value.get("profilePaths").and_then(Value::as_array) {
        for path in paths.iter().filter_map(Value::as_str).take(12) {
            specs.push((path.to_string(), "w185".to_string()));
        }
    }
    specs.sort();
    specs.dedup();
    specs
}

fn string_set_from_json(text: &str) -> Result<HashSet<String>> {
    let value: Value = serde_json::from_str(text)?;
    Ok(value
        .as_array()
        .into_iter()
        .flatten()
        .filter_map(Value::as_str)
        .map(str::to_string)
        .collect())
}

fn query_string_column(conn: &Connection, sql: &str) -> Result<Vec<String>> {
    let mut stmt = conn.prepare(sql)?;
    let rows = stmt.query_map([], |row| row.get::<_, String>(0))?;
    let mut values = Vec::new();
    for row in rows {
        values.push(row?);
    }
    Ok(values)
}

fn prune_unreferenced_images(conn: &Connection) -> Result<()> {
    let mut referenced = HashSet::new();
    for sql in [
        "select json from metadata_titles",
        "select json from metadata_episodes",
        "select json from metadata",
    ] {
        let mut stmt = conn.prepare(sql)?;
        let rows = stmt.query_map([], |row| row.get::<_, String>(0))?;
        for row in rows {
            let json = row?;
            let value: Value = serde_json::from_str(&json)?;
            for (path, size) in image_specs(&value) {
                referenced.insert(format!("{size}:{path}"));
            }
        }
    }

    let image_keys = query_string_column(conn, "select image_key from metadata_images")?;
    for image_key in image_keys {
        if !referenced.contains(&image_key) {
            conn.execute(
                "delete from metadata_images where image_key=?1",
                params![image_key],
            )?;
        }
    }
    Ok(())
}

fn upsert_source_folder(
    conn: &Connection,
    source_id: &str,
    path: &str,
    search_hint: Option<&str>,
    now: i64,
) -> Result<i64> {
    conn.execute(
        "insert into source_folders(source_id, path, selected, search_hint, created_at, updated_at)
         values (?1, ?2, 1, ?3, ?4, ?4)
         on conflict(source_id, path) do update set
           selected=1,
           search_hint=coalesce(excluded.search_hint, source_folders.search_hint),
           updated_at=excluded.updated_at",
        params![source_id, normalize_folder_path(path), search_hint, now],
    )?;
    Ok(conn.query_row(
        "select id from source_folders where source_id=?1 and path=?2",
        params![source_id, normalize_folder_path(path)],
        |row| row.get(0),
    )?)
}

fn media_file_id(conn: &Connection, legacy_item_id: &str) -> Result<i64> {
    Ok(conn.query_row(
        "select id from media_files where legacy_item_id=?1",
        params![legacy_item_id],
        |row| row.get(0),
    )?)
}

fn query_row_id(conn: &Connection, sql: &str, value: i64) -> Result<i64> {
    Ok(conn.query_row(sql, params![value], |row| row.get(0))?)
}

fn query_source_folders(conn: &Connection) -> Result<Vec<(String, String)>> {
    let mut stmt = conn.prepare("select source_id, path from source_folders")?;
    let rows = stmt.query_map([], |row| {
        Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?))
    })?;
    let mut values = Vec::new();
    for row in rows {
        values.push(row?);
    }
    Ok(values)
}

fn upsert_tmdb_images(
    conn: &Connection,
    owner_type: &str,
    owner_id: i64,
    value: &Value,
    now: i64,
) -> Result<()> {
    for (key, image_type) in [
        ("posterPath", "poster"),
        ("backdropPath", "backdrop"),
        ("stillPath", "still"),
        ("logoPath", "logo"),
    ] {
        if let Some(path) = value.get(key).and_then(Value::as_str) {
            conn.execute(
                "insert into tmdb_images(owner_type, owner_id, image_type, file_path, created_at, updated_at)
                 values (?1, ?2, ?3, ?4, ?5, ?5)
                 on conflict(owner_type, owner_id, image_type, file_path) do update set
                   updated_at=excluded.updated_at",
                params![owner_type, owner_id, image_type, path, now],
            )?;
        }
    }
    Ok(())
}

fn upsert_people_and_credits(
    conn: &Connection,
    show_id: i64,
    value: &Value,
    now: i64,
) -> Result<()> {
    let names = value
        .get("castNames")
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default();
    let profiles = value
        .get("profilePaths")
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default();
    for (index, name_value) in names.iter().enumerate().take(12) {
        let Some(name) = name_value.as_str().filter(|name| !name.trim().is_empty()) else {
            continue;
        };
        let profile = profiles.get(index).and_then(Value::as_str);
        let person_id: Option<i64> = conn
            .query_row(
                "select id from tmdb_people_cache
                 where name=?1 and coalesce(profile_path, '')=coalesce(?2, '')
                 limit 1",
                params![name, profile],
                |row| row.get(0),
            )
            .ok();
        let person_id = match person_id {
            Some(person_id) => {
                conn.execute(
                    "update tmdb_people_cache
                     set profile_path=coalesce(?2, profile_path), updated_at=?3
                     where id=?1",
                    params![person_id, profile, now],
                )?;
                person_id
            }
            None => {
                conn.execute(
                    "insert into tmdb_people_cache(name, profile_path, updated_at)
                     values (?1, ?2, ?3)",
                    params![name, profile, now],
                )?;
                conn.last_insert_rowid()
            }
        };
        conn.execute(
            "insert or ignore into tmdb_credits(
               owner_type, owner_id, person_id, credit_type, credit_order
             )
             values ('show', ?1, ?2, 'cast', ?3)",
            params![show_id, person_id, index as i64],
        )?;
        if let Some(profile) = profile {
            conn.execute(
                "insert into tmdb_images(owner_type, owner_id, image_type, file_path, created_at, updated_at)
                 values ('person', ?1, 'profile', ?2, ?3, ?3)
                 on conflict(owner_type, owner_id, image_type, file_path) do update set
                   updated_at=excluded.updated_at",
                params![person_id, profile, now],
            )?;
        }
    }
    Ok(())
}

fn cleanup_orphan_resources(conn: &Connection) -> Result<()> {
    conn.execute(
        "delete from media_files
         where not exists (
           select 1 from sources s where s.id=media_files.source_id
         )
           or not exists (
             select 1 from source_folders sf where sf.id=media_files.folder_id
           )",
        [],
    )?;
    conn.execute(
        "delete from source_folders
         where not exists (
           select 1 from sources s where s.id=source_folders.source_id
         )",
        [],
    )?;
    Ok(())
}

fn cleanup_orphan_tmdb(conn: &Connection) -> Result<()> {
    conn.execute(
        "delete from source_folder_matches
         where not exists (
           select 1 from media_files mf where mf.folder_id=source_folder_matches.folder_id
         )",
        [],
    )?;
    conn.execute(
        "delete from folder_preferences
         where not exists (
           select 1 from media_files mf where mf.folder_id=folder_preferences.folder_id
         )",
        [],
    )?;
    conn.execute(
        "delete from media_file_matches
         where not exists (
           select 1 from media_files mf where mf.id=media_file_matches.file_id
         )",
        [],
    )?;
    conn.execute(
        "delete from metadata_episodes
         where not exists (
           select 1 from media_files mf where mf.legacy_item_id=metadata_episodes.item_id
         )",
        [],
    )?;
    conn.execute(
        "delete from metadata_titles
         where not exists (
           select 1 from metadata_episodes me where me.title_key=metadata_titles.title_key
         )",
        [],
    )?;
    conn.execute(
        "delete from metadata
         where not exists (
           select 1 from media_files mf where mf.legacy_item_id=metadata.item_id
         )",
        [],
    )?;
    conn.execute(
        "delete from tmdb_tv_episodes
         where not exists (
           select 1 from media_file_matches mfm where mfm.episode_id=tmdb_tv_episodes.id
         )",
        [],
    )?;
    conn.execute(
        "delete from tmdb_tv_seasons
         where not exists (
           select 1 from media_file_matches mfm where mfm.season_id=tmdb_tv_seasons.id
         )
           and not exists (
             select 1 from tmdb_tv_episodes e where e.season_id=tmdb_tv_seasons.id
           )",
        [],
    )?;
    conn.execute(
        "delete from tmdb_tv_shows
         where not exists (
           select 1 from source_folder_matches sfm where sfm.show_id=tmdb_tv_shows.id
         )
           and not exists (
             select 1 from media_file_matches mfm where mfm.show_id=tmdb_tv_shows.id
           )",
        [],
    )?;
    conn.execute(
        "delete from tmdb_credits
         where owner_type='show'
           and not exists (
             select 1 from tmdb_tv_shows s where s.id=tmdb_credits.owner_id
           )",
        [],
    )?;
    conn.execute(
        "delete from tmdb_people_cache
         where not exists (
           select 1 from tmdb_credits c where c.person_id=tmdb_people_cache.id
         )",
        [],
    )?;
    conn.execute(
        "delete from tmdb_images
         where (owner_type='show' and not exists (
             select 1 from tmdb_tv_shows s where s.id=tmdb_images.owner_id
           ))
           or (owner_type='season' and not exists (
             select 1 from tmdb_tv_seasons s where s.id=tmdb_images.owner_id
           ))
           or (owner_type='episode' and not exists (
             select 1 from tmdb_tv_episodes e where e.id=tmdb_images.owner_id
           ))
           or (owner_type='person' and not exists (
             select 1 from tmdb_people_cache p where p.id=tmdb_images.owner_id
           ))",
        [],
    )?;
    conn.execute(
        "delete from image_cache
         where provider='tmdb'
           and not exists (
             select 1 from tmdb_images i
             where image_cache.cache_key =
               case i.image_type
                 when 'poster' then 'w500:' || i.file_path
                 when 'backdrop' then 'w780:' || i.file_path
                 when 'still' then 'w780:' || i.file_path
                 when 'logo' then 'w300:' || i.file_path
                 when 'profile' then 'w185:' || i.file_path
                 else image_cache.size || ':' || i.file_path
               end
           )",
        [],
    )?;
    prune_unreferenced_images(conn)?;
    Ok(())
}

fn item_relative_path(item_type: &str, uri: &str) -> String {
    if item_type == "webdav" {
        if let Ok(url) = Url::parse(uri) {
            return normalize_resource_path(&percent_decode(url.path()));
        }
    }
    normalize_resource_path(uri)
}

fn parent_path(path: &str) -> String {
    let normalized = normalize_resource_path(path);
    let trimmed = normalized.trim_end_matches('/');
    let path = match trimmed.rfind('/') {
        Some(0) => "/".to_string(),
        Some(index) => trimmed[..index].to_string(),
        None => ".".to_string(),
    };
    normalize_folder_path(&path)
}

fn file_name(path: &str) -> String {
    normalize_resource_path(path)
        .trim_end_matches('/')
        .rsplit('/')
        .next()
        .unwrap_or(path)
        .to_string()
}

fn file_stem(path: &str) -> Option<String> {
    let name = file_name(path);
    let stem = name.rsplit_once('.').map(|(stem, _)| stem).unwrap_or(&name);
    if stem.is_empty() {
        None
    } else {
        Some(stem.to_string())
    }
}

fn display_name_from_path(path: &str) -> String {
    let name = file_name(path);
    if name.is_empty() || name == "/" || name == "." {
        "其他".to_string()
    } else {
        name
    }
}

fn file_ext(path: &str) -> Option<String> {
    file_name(path)
        .rsplit_once('.')
        .map(|(_, ext)| ext.to_ascii_lowercase())
        .filter(|ext| !ext.is_empty())
}

fn is_video_resource_path(path: &str) -> bool {
    const VIDEO_EXTENSIONS: &[&str] = &[
        "mp4", "mkv", "mov", "avi", "flv", "wmv", "webm", "m4v", "ts", "m2ts", "mts", "mpg",
        "mpeg", "3gp", "rm", "rmvb", "vob", "ogv", "asf",
    ];
    file_ext(path)
        .map(|ext| VIDEO_EXTENSIONS.contains(&ext.as_str()))
        .unwrap_or(false)
}

fn guess_quality(path: &str) -> Option<String> {
    let lower = path.to_ascii_lowercase();
    for quality in ["8k", "4k", "2160p", "1080p", "720p"] {
        if lower.contains(quality) {
            return Some(quality.to_ascii_uppercase());
        }
    }
    None
}

fn normalize_resource_path(path: &str) -> String {
    let mut value = path.replace('\\', "/").trim().to_string();
    if value.is_empty() {
        return "/".to_string();
    }
    while value.contains("//") {
        value = value.replace("//", "/");
    }
    if value == "/dav" {
        return "/".to_string();
    }
    if let Some(rest) = value.strip_prefix("/dav/") {
        value = format!("/{rest}");
    }
    value
}

fn normalize_folder_path(path: &str) -> String {
    let mut value = normalize_resource_path(path);
    if value == "." || value.is_empty() {
        value = "/".to_string();
    }
    if !value.ends_with('/') {
        value.push('/');
    }
    value
}

fn webdav_uri(base_url: &str, path: &str) -> String {
    let normalized_path = normalize_resource_path(path);
    let Ok(mut url) = Url::parse(base_url.trim_end_matches('/')) else {
        return format!("{}{}", base_url.trim_end_matches('/'), normalized_path);
    };
    if let Ok(mut segments) = url.path_segments_mut() {
        for part in normalized_path.split('/').filter(|part| !part.is_empty()) {
            segments.push(part);
        }
    }
    url.to_string()
}

fn percent_decode(value: &str) -> String {
    let mut output = Vec::new();
    let bytes = value.as_bytes();
    let mut index = 0;
    while index < bytes.len() {
        if bytes[index] == b'%' && index + 2 < bytes.len() {
            if let Ok(hex) = std::str::from_utf8(&bytes[index + 1..index + 3]) {
                if let Ok(byte) = u8::from_str_radix(hex, 16) {
                    output.push(byte);
                    index += 3;
                    continue;
                }
            }
        }
        output.push(bytes[index]);
        index += 1;
    }
    String::from_utf8_lossy(&output).to_string()
}

fn legacy_folder_key_parts(value: &str) -> Option<(String, String)> {
    let (source_id, rest) = value.split_once(':')?;
    let path = rest
        .split_once(':')
        .map(|(_, path)| path)
        .unwrap_or(rest)
        .trim();
    if source_id.is_empty() || path.is_empty() {
        return None;
    }
    Some((source_id.to_string(), normalize_folder_path(path)))
}

fn parse_group_key(value: &str) -> Option<(String, String)> {
    let (source_id, rest) = value.split_once(':')?;
    let (_, path) = rest.split_once(':')?;
    Some((source_id.to_string(), normalize_folder_path(path)))
}

fn insert_optional_string(object: &mut Map<String, Value>, key: &str, value: Option<String>) {
    if let Some(value) = value {
        object.insert(key.to_string(), Value::String(value));
    }
}

fn insert_optional_i64(object: &mut Map<String, Value>, key: &str, value: Option<i64>) {
    if let Some(value) = value {
        object.insert(key.to_string(), Value::from(value));
    }
}

fn insert_optional_f64(object: &mut Map<String, Value>, key: &str, value: Option<f64>) {
    if let Some(value) = value {
        object.insert(key.to_string(), Value::from(value));
    }
}

fn query_cast_names(conn: &Connection, show_id: i64) -> Result<Value> {
    let mut stmt = conn.prepare(
        "select p.name
         from tmdb_credits c
         join tmdb_people_cache p on p.id = c.person_id
         where c.owner_type='show' and c.owner_id=?1 and c.credit_type='cast'
         group by p.name
         order by min(c.credit_order)
         limit 12",
    )?;
    let rows = stmt.query_map(params![show_id], |row| row.get::<_, String>(0))?;
    let mut values = Vec::new();
    for row in rows {
        values.push(Value::String(row?));
    }
    Ok(Value::Array(values))
}

fn query_profile_paths(conn: &Connection, show_id: i64) -> Result<Value> {
    let mut stmt = conn.prepare(
        "select p.profile_path
         from tmdb_credits c
         join tmdb_people_cache p on p.id = c.person_id
         where c.owner_type='show' and c.owner_id=?1 and c.credit_type='cast'
         group by p.name
         order by min(c.credit_order)
         limit 12",
    )?;
    let rows = stmt.query_map(params![show_id], |row| row.get::<_, Option<String>>(0))?;
    let mut values = Vec::new();
    for row in rows {
        values.push(row?.map(Value::String).unwrap_or(Value::Null));
    }
    Ok(Value::Array(values))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn app_state_round_trips_through_normalized_tables() {
        let db_path =
            std::env::temp_dir().join(format!("player_core_state_roundtrip_{}.sqlite", now_ms()));
        let state = r#"{
          "version": 1,
          "sources": [
            {
              "id": "source-1",
              "name": "My WebDAV",
              "type": "webdav",
              "directory": "/dav/media/",
              "baseUrl": "https://example.com/dav",
              "username": "admin",
              "password": "secret",
              "selectedPaths": ["/dav/media/Show"]
            }
          ],
          "items": [
            {
              "id": "source-1:/media/Show/01.mp4",
              "sourceId": "source-1",
              "sourceName": "My WebDAV",
              "type": "webdav",
              "title": "01",
              "uri": "https://example.com/dav/media/Show/01.mp4",
              "folderTitle": "Show",
              "matchTitle": "Show",
              "season": 1,
              "episode": 1,
              "mediaKind": "TV",
              "size": 1234
            }
          ],
          "progress": {"source-1:/media/Show/01.mp4": 5000},
          "durations": {"source-1:/media/Show/01.mp4": 60000},
          "lastPlayedAt": {"source-1:/media/Show/01.mp4": 42},
          "folderOrientations": {"source-1:webdav:/dav/media/Show": "landscape"}
        }"#;

        put_app_state_json(db_path.to_str().unwrap(), state).unwrap();
        let exported: Value =
            serde_json::from_str(&get_app_state_json(db_path.to_str().unwrap()).unwrap()).unwrap();
        let sources = exported["sources"].as_array().unwrap();
        assert_eq!(sources.len(), 1);
        assert_eq!(sources[0]["name"], "My WebDAV");
        assert_eq!(sources[0]["directory"], "/media/");
        assert_eq!(sources[0]["username"], "admin");
        assert_eq!(sources[0]["password"], "secret");
        assert_eq!(sources[0]["selectedPaths"][0], "/media/Show/");

        let items = exported["items"].as_array().unwrap();
        assert_eq!(items.len(), 1);
        assert_eq!(items[0]["sourceId"], "source-1");
        assert_eq!(items[0]["uri"], "https://example.com/dav/media/Show/01.mp4");
        assert_eq!(items[0]["size"], 1234);
        assert_eq!(exported["progress"]["source-1:/media/Show/01.mp4"], 5000);
        assert_eq!(exported["durations"]["source-1:/media/Show/01.mp4"], 60000);
        assert_eq!(exported["lastPlayedAt"]["source-1:/media/Show/01.mp4"], 42);
        assert_eq!(
            exported["folderOrientations"]["source-1:webdav:/media/Show/"],
            "landscape"
        );

        let conn = open(db_path.to_str().unwrap()).unwrap();
        let old_json_count: i64 = conn
            .query_row("select count(*) from app_state", [], |row| row.get(0))
            .unwrap();
        assert_eq!(old_json_count, 0);
        let _ = std::fs::remove_file(db_path);
    }

    #[test]
    fn empty_selected_folder_prunes_media_metadata_and_image_cache() {
        let db_path = std::env::temp_dir().join(format!(
            "player_core_empty_folder_prune_{}.sqlite",
            now_ms()
        ));
        let initial_state = r#"{
          "version": 1,
          "sources": [
            {
              "id": "source-1",
              "name": "My WebDAV",
              "type": "webdav",
              "directory": "/dav/",
              "baseUrl": "https://example.com/dav",
              "selectedPaths": ["/dav/Show"]
            }
          ],
          "items": [
            {
              "id": "source-1:/Show/01.mp4",
              "sourceId": "source-1",
              "sourceName": "My WebDAV",
              "type": "webdav",
              "title": "01",
              "uri": "https://example.com/dav/Show/01.mp4",
              "folderTitle": "Show",
              "matchTitle": "Show",
              "season": 1,
              "episode": 1,
              "mediaKind": "TV",
              "size": 1234
            }
          ],
          "folderOrientations": {"source-1:webdav:/Show": "landscape"}
        }"#;
        let metadata = r#"{
          "tmdbId": 100,
          "mediaType": "tv",
          "title": "Show",
          "overview": "Overview",
          "posterPath": "/poster.jpg",
          "backdropPath": "/backdrop.jpg",
          "stillPath": "/still.jpg",
          "episodeName": "Episode 1",
          "season": 1,
          "episode": 1,
          "castNames": ["Actor"],
          "profilePaths": ["/profile.jpg"],
          "updatedAt": 1
        }"#;
        let cached_poster = r#"{
          "path": "/poster.jpg",
          "size": "w500",
          "url": "https://image.tmdb.org/t/p/w500/poster.jpg",
          "contentType": "image/jpeg",
          "bytesBase64": "AQID"
        }"#;

        put_app_state_json(db_path.to_str().unwrap(), initial_state).unwrap();
        put_metadata_json(
            db_path.to_str().unwrap(),
            "source-1:webdav:/Show/",
            "source-1:/Show/01.mp4",
            metadata,
        )
        .unwrap();
        put_cached_image_json(db_path.to_str().unwrap(), cached_poster).unwrap();

        let empty_state = r#"{
          "version": 1,
          "sources": [
            {
              "id": "source-1",
              "name": "My WebDAV",
              "type": "webdav",
              "directory": "/dav/",
              "baseUrl": "https://example.com/dav",
              "selectedPaths": ["/dav/Show"]
            }
          ],
          "items": []
        }"#;
        put_app_state_json(db_path.to_str().unwrap(), empty_state).unwrap();

        let conn = open(db_path.to_str().unwrap()).unwrap();
        assert_eq!(count_rows(&conn, "sources"), 1);
        assert_eq!(count_rows(&conn, "source_folders"), 1);
        assert_eq!(count_rows(&conn, "media_files"), 0);
        assert_eq!(count_rows(&conn, "folder_preferences"), 0);
        assert_eq!(count_rows(&conn, "source_folder_matches"), 0);
        assert_eq!(count_rows(&conn, "media_file_matches"), 0);
        assert_eq!(count_rows(&conn, "metadata_titles"), 0);
        assert_eq!(count_rows(&conn, "metadata_episodes"), 0);
        assert_eq!(count_rows(&conn, "tmdb_tv_shows"), 0);
        assert_eq!(count_rows(&conn, "tmdb_tv_seasons"), 0);
        assert_eq!(count_rows(&conn, "tmdb_tv_episodes"), 0);
        assert_eq!(count_rows(&conn, "tmdb_credits"), 0);
        assert_eq!(count_rows(&conn, "tmdb_people_cache"), 0);
        assert_eq!(count_rows(&conn, "tmdb_images"), 0);
        assert_eq!(count_rows(&conn, "image_cache"), 0);

        let _ = std::fs::remove_file(db_path);
    }

    #[test]
    fn selected_video_file_uses_parent_folder_and_source_delete_prunes_it() {
        let db_path = std::env::temp_dir().join(format!(
            "player_core_selected_file_folder_{}.sqlite",
            now_ms()
        ));
        let state = r#"{
          "version": 1,
          "sources": [
            {
              "id": "source-1",
              "name": "My WebDAV",
              "type": "webdav",
              "directory": "/dav/",
              "baseUrl": "https://example.com/dav",
              "selectedPaths": ["/dav/Show/01.mp4"]
            }
          ],
          "items": [
            {
              "id": "source-1:/Show/01.mp4",
              "sourceId": "source-1",
              "sourceName": "My WebDAV",
              "type": "webdav",
              "title": "01",
              "uri": "https://example.com/dav/Show/01.mp4",
              "folderTitle": "Show",
              "matchTitle": "Show",
              "season": 1,
              "episode": 1,
              "mediaKind": "TV",
              "size": 1234
            }
          ]
        }"#;

        put_app_state_json(db_path.to_str().unwrap(), state).unwrap();
        let conn = open(db_path.to_str().unwrap()).unwrap();
        let (path, search_hint): (String, Option<String>) = conn
            .query_row(
                "select path, search_hint from source_folders where source_id='source-1'",
                [],
                |row| Ok((row.get(0)?, row.get(1)?)),
            )
            .unwrap();
        assert_eq!(path, "/Show/");
        assert_eq!(search_hint.as_deref(), Some("Show"));

        let empty_state = r#"{
          "version": 1,
          "sources": [],
          "items": []
        }"#;
        put_app_state_json(db_path.to_str().unwrap(), empty_state).unwrap();
        let conn = open(db_path.to_str().unwrap()).unwrap();
        assert_eq!(count_rows(&conn, "sources"), 0);
        assert_eq!(count_rows(&conn, "source_folders"), 0);
        assert_eq!(count_rows(&conn, "media_files"), 0);

        let _ = std::fs::remove_file(db_path);
    }

    fn count_rows(conn: &Connection, table: &str) -> i64 {
        conn.query_row(&format!("select count(*) from {table}"), [], |row| {
            row.get(0)
        })
        .unwrap()
    }
}

fn query_show_genres(conn: &Connection, show_id: i64) -> Result<Value> {
    let raw_json: Option<String> = conn
        .query_row(
            "select raw_json from tmdb_tv_shows where id=?1",
            params![show_id],
            |row| row.get(0),
        )
        .unwrap_or(None);
    let Some(raw_json) = raw_json else {
        return Ok(Value::Array(Vec::new()));
    };
    let value: Value = serde_json::from_str(&raw_json)?;
    let values = value
        .get("genres")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .filter_map(Value::as_str)
        .map(|text| Value::String(text.to_string()))
        .collect();
    Ok(Value::Array(values))
}

fn empty_to_null(value: &str) -> Option<&str> {
    if value.trim().is_empty() {
        None
    } else {
        Some(value)
    }
}

fn now_ms() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|value| value.as_millis() as i64)
        .unwrap_or_default()
}
