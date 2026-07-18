use anyhow::Result;
use base64::{engine::general_purpose, Engine as _};
use rusqlite::{params, Connection};
use serde_json::{Map, Value};
use std::{collections::HashSet, fs, path::Path, time::Duration};
use url::Url;

use crate::media::parse_media_path_candidates;

fn current_metadata_schema_version() -> i64 {
    11
}

pub fn put_metadata_json(
    db_path: &str,
    title_key: &str,
    item_id: &str,
    metadata_json: &str,
) -> Result<()> {
    let value: Value = serde_json::from_str(metadata_json)?;
    let conn = open(db_path)?;
    upsert_tmdb_metadata(&conn, title_key, item_id, &value)?;
    Ok(())
}

pub fn get_all_metadata_json(db_path: &str) -> Result<String> {
    let conn = open(db_path)?;
    let mut stmt = conn.prepare(
        "select
           mf.item_id,
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
           se.tmdb_id,
           se.name,
           se.overview,
           se.air_date,
           se.episode_count,
           se.poster_path,
           e.name,
           e.tmdb_id,
           e.overview,
           e.air_date,
           e.runtime,
           e.still_path,
           e.episode_type,
           e.vote_average,
           e.vote_count,
           coalesce(e.last_synced_at, s.last_synced_at),
           s.type
         from media_file_matches mfm
         join media_files mf on mf.id = mfm.file_id and mf.scan_status = 'active'
         join tmdb_tv_shows s on s.id = mfm.show_id
         left join tmdb_tv_seasons se on se.id = mfm.season_id
         left join tmdb_tv_episodes e on e.id = mfm.episode_id
         order by mf.item_id",
    )?;
    let mut rows = stmt.query([])?;
    let mut map = Map::new();
    while let Some(row) = rows.next()? {
        let item_id = row.get::<_, String>(0)?;
        let show_id = row.get::<_, i64>(1)?;
        let mut object = Map::new();
        object.insert("itemId".to_string(), Value::String(item_id.clone()));
        object.insert("tmdbId".to_string(), Value::from(row.get::<_, i64>(2)?));
        object.insert("mediaType".to_string(), Value::String("tv".to_string()));
        object.insert("title".to_string(), Value::String(row.get::<_, String>(3)?));
        insert_optional_string(
            &mut object,
            "originalTitle",
            row.get::<_, Option<String>>(4)?,
        );
        insert_optional_string(&mut object, "overview", row.get::<_, Option<String>>(5)?);
        insert_optional_string(&mut object, "posterPath", row.get::<_, Option<String>>(6)?);
        insert_optional_string(
            &mut object,
            "backdropPath",
            row.get::<_, Option<String>>(7)?,
        );
        insert_optional_string(&mut object, "logoPath", row.get::<_, Option<String>>(8)?);
        object.insert(
            "profilePaths".to_string(),
            query_profile_paths(&conn, show_id)?,
        );
        object.insert("castNames".to_string(), query_cast_names(&conn, show_id)?);
        object.insert("genres".to_string(), query_show_genres(&conn, show_id)?);
        insert_optional_string(
            &mut object,
            "releaseDate",
            row.get::<_, Option<String>>(22)?
                .or_else(|| row.get::<_, Option<String>>(10).ok().flatten()),
        );
        insert_optional_f64(
            &mut object,
            "voteAverage",
            row.get::<_, Option<f64>>(26)?
                .or_else(|| row.get::<_, Option<f64>>(9).ok().flatten()),
        );
        insert_optional_i64(&mut object, "totalSeasons", row.get::<_, Option<i64>>(11)?);
        insert_optional_i64(&mut object, "totalEpisodes", row.get::<_, Option<i64>>(12)?);
        insert_optional_i64(&mut object, "seasonTmdbId", row.get::<_, Option<i64>>(13)?);
        insert_optional_string(&mut object, "seasonName", row.get::<_, Option<String>>(14)?);
        insert_optional_string(
            &mut object,
            "seasonOverview",
            row.get::<_, Option<String>>(15)?,
        );
        insert_optional_string(
            &mut object,
            "seasonAirDate",
            row.get::<_, Option<String>>(16)?,
        );
        insert_optional_i64(
            &mut object,
            "seasonEpisodeCount",
            row.get::<_, Option<i64>>(17)?,
        );
        insert_optional_string(
            &mut object,
            "seasonPosterPath",
            row.get::<_, Option<String>>(18)?,
        );
        insert_optional_string(
            &mut object,
            "episodeName",
            row.get::<_, Option<String>>(19)?,
        );
        insert_optional_i64(&mut object, "episodeTmdbId", row.get::<_, Option<i64>>(20)?);
        insert_optional_string(
            &mut object,
            "episodeOverview",
            row.get::<_, Option<String>>(21)?,
        );
        insert_optional_i64(
            &mut object,
            "episodeRuntime",
            row.get::<_, Option<i64>>(23)?,
        );
        insert_optional_string(&mut object, "stillPath", row.get::<_, Option<String>>(24)?);
        insert_optional_string(
            &mut object,
            "episodeType",
            row.get::<_, Option<String>>(25)?,
        );
        insert_optional_i64(
            &mut object,
            "episodeVoteCount",
            row.get::<_, Option<i64>>(27)?,
        );
        insert_optional_i64(&mut object, "updatedAt", row.get::<_, Option<i64>>(28)?);
        insert_optional_string(&mut object, "tmdbType", row.get::<_, Option<String>>(29)?);
        object.insert(
            "schemaVersion".to_string(),
            Value::from(current_metadata_schema_version()),
        );
        map.insert(item_id, Value::Object(object));
    }
    let mut movie_stmt = conn.prepare(
        "select
           mf.item_id,
           m.tmdb_id,
           m.title,
           m.original_title,
           m.overview,
           m.poster_path,
           m.backdrop_path,
           m.logo_path,
           m.vote_average,
           m.release_date,
           m.last_synced_at
         from media_file_movie_matches mfmm
         join media_files mf on mf.id = mfmm.file_id and mf.scan_status = 'active'
         join tmdb_movies m on m.id = mfmm.movie_id
         order by mf.item_id",
    )?;
    let mut movie_rows = movie_stmt.query([])?;
    while let Some(row) = movie_rows.next()? {
        let item_id = row.get::<_, String>(0)?;
        let mut object = Map::new();
        object.insert("itemId".to_string(), Value::String(item_id.clone()));
        object.insert("tmdbId".to_string(), Value::from(row.get::<_, i64>(1)?));
        object.insert("mediaType".to_string(), Value::String("movie".to_string()));
        object.insert("title".to_string(), Value::String(row.get::<_, String>(2)?));
        insert_optional_string(
            &mut object,
            "originalTitle",
            row.get::<_, Option<String>>(3)?,
        );
        insert_optional_string(&mut object, "overview", row.get::<_, Option<String>>(4)?);
        insert_optional_string(&mut object, "posterPath", row.get::<_, Option<String>>(5)?);
        insert_optional_string(
            &mut object,
            "backdropPath",
            row.get::<_, Option<String>>(6)?,
        );
        insert_optional_string(&mut object, "logoPath", row.get::<_, Option<String>>(7)?);
        object.insert("profilePaths".to_string(), Value::Array(Vec::new()));
        object.insert("castNames".to_string(), Value::Array(Vec::new()));
        object.insert("genres".to_string(), Value::Array(Vec::new()));
        insert_optional_f64(&mut object, "voteAverage", row.get::<_, Option<f64>>(8)?);
        insert_optional_string(&mut object, "releaseDate", row.get::<_, Option<String>>(9)?);
        object.insert("totalEpisodes".to_string(), Value::from(1));
        object.insert("updatedAt".to_string(), Value::from(row.get::<_, i64>(10)?));
        object.insert(
            "schemaVersion".to_string(),
            Value::from(current_metadata_schema_version()),
        );
        map.insert(item_id, Value::Object(object));
    }
    Ok(Value::Object(map).to_string())
}

pub fn put_app_state_json(db_path: &str, state_json: &str) -> Result<()> {
    let conn = open(db_path)?;
    sync_library_from_state_json(&conn, state_json)?;
    Ok(())
}

pub fn put_playback_progress_json(
    db_path: &str,
    item_id: &str,
    position_ms: i64,
    duration_ms: Option<i64>,
) -> Result<()> {
    let conn = open(db_path)?;
    let now = now_ms();
    let completed = duration_ms
        .filter(|duration| *duration > 0)
        .map(|duration| position_ms >= duration.saturating_mul(9) / 10)
        .unwrap_or(false);
    conn.execute(
        "insert into playback_progress(file_id, position_ms, duration_ms, last_played_at, completed, updated_at)
         select id, ?2, ?3, ?4, ?5, ?4 from media_files where item_id=?1
         on conflict(file_id) do update set
           position_ms=excluded.position_ms,
           duration_ms=coalesce(excluded.duration_ms, playback_progress.duration_ms),
           last_played_at=excluded.last_played_at,
           completed=excluded.completed,
           updated_at=excluded.updated_at",
        params![item_id, position_ms.max(0), duration_ms, now, completed as i64],
    )?;
    Ok(())
}

pub fn clear_playback_recent_json(db_path: &str, item_ids_json: &str) -> Result<()> {
    let item_ids: Vec<String> = serde_json::from_str(item_ids_json)?;
    let mut conn = open(db_path)?;
    let transaction = conn.transaction()?;
    for item_id in item_ids {
        transaction.execute(
            "update playback_progress set last_played_at=null, updated_at=?2
             where file_id=(select id from media_files where item_id=?1)",
            params![item_id, now_ms()],
        )?;
    }
    transaction.commit()?;
    Ok(())
}

pub fn put_playback_duration_json(db_path: &str, item_id: &str, duration_ms: i64) -> Result<()> {
    if duration_ms <= 0 {
        return Ok(());
    }
    let conn = open(db_path)?;
    let now = now_ms();
    conn.execute(
        "insert into playback_progress(file_id, position_ms, duration_ms, updated_at)
         select id, 0, ?2, ?3 from media_files where item_id=?1
         on conflict(file_id) do update set
           duration_ms=excluded.duration_ms,
           updated_at=excluded.updated_at",
        params![item_id, duration_ms, now],
    )?;
    Ok(())
}

pub fn put_folder_orientation_json(
    db_path: &str,
    folder_key: &str,
    orientation: &str,
) -> Result<()> {
    let Some((source_id, path)) = folder_preference_key_parts(folder_key) else {
        return Ok(());
    };
    if orientation != "landscape" && orientation != "portrait" {
        return Ok(());
    }
    let conn = open(db_path)?;
    let now = now_ms();
    let folder_id = upsert_source_folder(&conn, &source_id, &path, None, false, false, now)?;
    conn.execute(
        "insert into folder_preferences(folder_id, preferred_orientation, updated_at)
         values (?1, ?2, ?3)
         on conflict(folder_id) do update set
           preferred_orientation=excluded.preferred_orientation,
           updated_at=excluded.updated_at",
        params![folder_id, orientation, now],
    )?;
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
        "select content_type, bytes from image_cache
         where cache_key=?1 and bytes is not null
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

pub fn get_metadata_flag_json(db_path: &str, key: &str) -> Result<String> {
    let conn = open(db_path)?;
    let value = conn.query_row(
        "select value from metadata_flags where key=?1",
        params![key],
        |row| row.get::<_, String>(0),
    );
    match value {
        Ok(value) => Ok(value),
        Err(rusqlite::Error::QueryReturnedNoRows) => Ok("null".to_string()),
        Err(error) => Err(error.into()),
    }
}

pub fn put_metadata_flag_json(db_path: &str, key: &str, value_json: &str) -> Result<()> {
    let conn = open(db_path)?;
    let _: Value = serde_json::from_str(value_json)?;
    conn.execute(
        "insert into metadata_flags(key, value, updated_at)
         values (?1, ?2, ?3)
         on conflict(key) do update set
           value=excluded.value,
           updated_at=excluded.updated_at",
        params![key, value_json, now_ms()],
    )?;
    Ok(())
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
           m.id,
           coalesce(s.tmdb_id, m.tmdb_id),
           coalesce(s.name, m.title),
           coalesce(s.overview, m.overview),
           coalesce(s.poster_path, m.poster_path),
           coalesce(s.backdrop_path, m.backdrop_path),
           coalesce(s.vote_average, m.vote_average),
           coalesce(s.first_air_date, m.release_date),
           coalesce(s.number_of_episodes, 1),
           s.type,
           count(distinct mf.id),
           max(pp.last_played_at),
           coalesce(sf.search_hint, min(mf.guess_title), sf.path),
           min(mf.filename),
           min(mf.item_id)
         from source_folders sf
         join media_files mf on mf.folder_id = sf.id and mf.scan_status = 'active'
         left join source_folder_matches sfm on sfm.folder_id = sf.id
         left join tmdb_tv_shows s on s.id = sfm.show_id
         left join source_folder_movie_matches sfmm on sfmm.folder_id = sf.id
         left join tmdb_movies m on m.id = sfmm.movie_id
         left join playback_progress pp on pp.file_id = mf.id
         group by
           case
             when s.id is null and m.id is null and mf.explicitly_selected=1 then mf.id
             else sf.id
           end,
           sf.id, s.id, m.id
         order by (s.id is null and m.id is null), max(pp.last_played_at) is null, max(pp.last_played_at) desc, coalesce(s.name, m.title, sf.path)",
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
        let movie_id = row.get::<_, Option<i64>>(4)?;
        let tmdb_id = row.get::<_, Option<i64>>(5)?;
        insert_optional_i64(&mut object, "showId", show_id);
        insert_optional_i64(&mut object, "movieId", movie_id);
        insert_optional_i64(&mut object, "tmdbId", tmdb_id);
        let file_count = row.get::<_, i64>(14)?;
        let fallback_title = row.get::<_, String>(16)?;
        let title = row
            .get::<_, Option<String>>(6)?
            .filter(|value| !value.trim().is_empty())
            .unwrap_or_else(|| {
                if show_id.is_none() && movie_id.is_none() && file_count == 1 {
                    row.get::<_, Option<String>>(17)
                        .ok()
                        .flatten()
                        .and_then(|filename| file_stem(&filename))
                        .filter(|value| !value.trim().is_empty())
                        .unwrap_or_else(|| display_name_from_path(&fallback_title))
                } else {
                    display_name_from_path(&fallback_title)
                }
            });
        object.insert("title".to_string(), Value::from(title));
        insert_optional_string(&mut object, "itemId", row.get::<_, Option<String>>(18)?);
        insert_optional_string(&mut object, "overview", row.get::<_, Option<String>>(7)?);
        insert_optional_string(&mut object, "posterPath", row.get::<_, Option<String>>(8)?);
        insert_optional_string(
            &mut object,
            "backdropPath",
            row.get::<_, Option<String>>(9)?,
        );
        insert_optional_f64(&mut object, "voteAverage", row.get::<_, Option<f64>>(10)?);
        insert_optional_string(
            &mut object,
            "releaseDate",
            row.get::<_, Option<String>>(11)?,
        );
        insert_optional_i64(&mut object, "totalEpisodes", row.get::<_, Option<i64>>(12)?);
        insert_optional_string(&mut object, "tmdbType", row.get::<_, Option<String>>(13)?);
        if let Some(show_id) = show_id {
            object.insert(
                "genres".to_string(),
                query_show_genres(&conn, show_id).unwrap_or_else(|_| Value::Array(Vec::new())),
            );
        } else if let Some(movie_id) = movie_id {
            object.insert(
                "genres".to_string(),
                query_movie_genres(&conn, movie_id).unwrap_or_else(|_| Value::Array(Vec::new())),
            );
        }
        object.insert("localFileCount".to_string(), Value::from(file_count));
        insert_optional_i64(
            &mut object,
            "latestPlayedAt",
            row.get::<_, Option<i64>>(15)?,
        );
        let matched = show_id.is_some() || movie_id.is_some();
        object.insert("matched".to_string(), Value::from(matched));
        if show_id.is_some() {
            object.insert("mediaType".to_string(), Value::from("tv"));
        } else if movie_id.is_some() {
            object.insert("mediaType".to_string(), Value::from("movie"));
        }
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
    let folder_id = match parse_group_key(folder_key) {
        Some((source_id, group_path)) => match conn.query_row(
            "select id from source_folders where source_id=?1 and path=?2",
            params![source_id, group_path],
            |row| row.get::<_, i64>(0),
        ) {
            Ok(id) => id,
            Err(rusqlite::Error::QueryReturnedNoRows) => -1,
            Err(error) => return Err(error.into()),
        },
        None => -1,
    };
    let mut stmt = conn.prepare(
        "select
           mf.id,
           mf.item_id,
           mf.relative_path,
           mf.filename,
           mf.size,
           mf.guess_season,
           mf.guess_episode,
           pp.position_ms,
           pp.duration_ms,
           pp.last_played_at,
           s.id,
           coalesce(s.tmdb_id, m.tmdb_id),
           coalesce(s.name, m.title),
           coalesce(s.original_name, m.original_title),
           coalesce(s.overview, m.overview),
           coalesce(s.poster_path, m.poster_path),
           coalesce(s.backdrop_path, m.backdrop_path),
           coalesce(s.logo_path, m.logo_path),
           coalesce(s.vote_average, m.vote_average),
           coalesce(s.first_air_date, m.release_date),
           s.number_of_seasons,
           coalesce(s.number_of_episodes, case when m.id is not null then 1 end),
           e.id,
           e.season_number,
           e.episode_number,
           e.name,
           e.overview,
           e.air_date,
           e.runtime,
           e.still_path,
           m.id,
           case when m.id is not null then 'movie' when s.id is not null then 'tv' end,
           s.type,
           mf.parsed_version_name,
           mf.parsed_version_dir_path
         from media_files mf
         left join playback_progress pp on pp.file_id = mf.id
         left join media_file_matches mfm on mfm.file_id = mf.id
         left join tmdb_tv_shows s on s.id = mfm.show_id
         left join tmdb_tv_episodes e on e.id = mfm.episode_id
         left join media_file_movie_matches mfmm on mfmm.file_id = mf.id
         left join tmdb_movies m on m.id = mfmm.movie_id
         where mf.scan_status = 'active'
           and mf.folder_id = ?1
         order by coalesce(e.season_number, mf.guess_season, 1),
                  coalesce(e.episode_number, mf.guess_episode, 999999),
                  mf.filename",
    )?;
    let rows = stmt.query_map(params![folder_id], |row| {
        let mut object = Map::new();
        object.insert("fileId".to_string(), Value::from(row.get::<_, i64>(0)?));
        object.insert("itemId".to_string(), Value::from(row.get::<_, String>(1)?));
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
        insert_optional_i64(&mut object, "movieId", row.get::<_, Option<i64>>(30)?);
        insert_optional_string(&mut object, "mediaType", row.get::<_, Option<String>>(31)?);
        insert_optional_string(&mut object, "tmdbType", row.get::<_, Option<String>>(32)?);
        insert_optional_string(
            &mut object,
            "versionName",
            row.get::<_, Option<String>>(33)?,
        );
        insert_optional_string(
            &mut object,
            "versionDirPath",
            row.get::<_, Option<String>>(34)?,
        );
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
           mf.item_id,
           mf.relative_path,
           mf.filename,
           mf.size,
           pp.position_ms,
           pp.duration_ms,
           pp.last_played_at,
           coalesce(s.name, m.title),
           coalesce(s.poster_path, m.poster_path),
           coalesce(s.backdrop_path, m.backdrop_path),
           e.season_number,
           e.episode_number,
           e.name,
           e.still_path,
           case when m.id is not null then 'movie' when s.id is not null then 'tv' end
         from playback_progress pp
         join media_files mf on mf.id = pp.file_id and mf.scan_status = 'active'
         left join media_file_matches mfm on mfm.file_id = mf.id
         left join tmdb_tv_shows s on s.id = mfm.show_id
         left join tmdb_tv_episodes e on e.id = mfm.episode_id
         left join media_file_movie_matches mfmm on mfmm.file_id = mf.id
         left join tmdb_movies m on m.id = mfmm.movie_id
         where pp.last_played_at is not null
         order by pp.last_played_at desc",
    )?;
    let rows = stmt.query_map([], |row| {
        let mut object = Map::new();
        object.insert("fileId".to_string(), Value::from(row.get::<_, i64>(0)?));
        object.insert("itemId".to_string(), Value::from(row.get::<_, String>(1)?));
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
        insert_optional_string(&mut object, "mediaType", row.get::<_, Option<String>>(15)?);
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
    let conn = open(db_path)?;
    conn.execute("delete from media_file_movie_matches", [])?;
    conn.execute("delete from media_file_matches", [])?;
    conn.execute("delete from source_folder_movie_matches", [])?;
    conn.execute("delete from source_folder_matches", [])?;
    conn.execute("delete from tmdb_credits", [])?;
    conn.execute("delete from tmdb_people_cache", [])?;
    conn.execute("delete from tmdb_images", [])?;
    conn.execute("delete from tmdb_movies", [])?;
    conn.execute("delete from tmdb_tv_episodes", [])?;
    conn.execute("delete from tmdb_tv_seasons", [])?;
    conn.execute("delete from tmdb_tv_shows", [])?;
    for (item_id, value) in object {
        upsert_tmdb_metadata(&conn, &item_id, &item_id, &value)?;
    }
    cleanup_orphan_tmdb(&conn)?;
    Ok(())
}

pub fn prune_metadata_json(
    db_path: &str,
    live_item_ids_json: &str,
    _live_title_keys_json: &str,
) -> Result<()> {
    let live_item_ids = string_set_from_json(live_item_ids_json)?;
    let conn = open(db_path)?;
    let item_ids = query_string_column(&conn, "select item_id from media_files")?;
    for item_id in item_ids {
        if !live_item_ids.contains(&item_id) {
            conn.execute("delete from media_files where item_id=?1", params![item_id])?;
        }
    }
    cleanup_orphan_tmdb(&conn)?;
    Ok(())
}

pub async fn cache_images_json(
    db_path: &str,
    metadata_json: &str,
    image_base_url: &str,
) -> Result<()> {
    let value: Value = serde_json::from_str(metadata_json)?;
    let images = image_specs(&value);
    if images.is_empty() {
        return Ok(());
    }
    let client = reqwest::Client::builder()
        .timeout(std::time::Duration::from_secs(12))
        .user_agent("player_flutter/0.1")
        .build()?;
    let image_base_url = image_base_url.trim().trim_end_matches('/');
    let image_base_url = if image_base_url.is_empty() {
        "https://image.tmdb.org/t/p"
    } else {
        image_base_url
    };
    let conn = open(db_path)?;
    for (path, size) in images {
        let key = format!("{size}:{path}");
        let exists: bool = conn.query_row(
            "select exists(select 1 from image_cache where cache_key=?1)",
            params![key],
            |row| row.get(0),
        )?;
        if exists {
            continue;
        }
        let normalized_path = if path.starts_with('/') {
            path.clone()
        } else {
            format!("/{path}")
        };
        let url = format!("{image_base_url}/{size}{normalized_path}");
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
    if let Some(parent) = Path::new(db_path).parent() {
        if !parent.as_os_str().is_empty() {
            fs::create_dir_all(parent)?;
        }
    }
    let conn = Connection::open(db_path)?;
    conn.busy_timeout(Duration::from_secs(30))?;
    conn.execute_batch(
        "pragma journal_mode = truncate;
         pragma synchronous = normal;",
    )?;
    reset_incompatible_legacy_schema(&conn)?;
    conn.execute_batch(
        "create table if not exists sources(
           id text primary key,
           name text not null,
           type text not null,
           base_url text,
           root_path text default '/',
           username text,
           password text,
           otp_code text,
           credential_id text,
           created_at integer not null,
           updated_at integer not null
         );
         create table if not exists source_folders(
           id integer primary key autoincrement,
           source_id text not null,
           path text not null,
           selected integer not null default 1,
           manual_series integer not null default 0,
           search_hint text,
           last_scanned_at integer,
           created_at integer not null,
           updated_at integer not null,
           unique(source_id, path),
           foreign key(source_id) references sources(id) on delete cascade
         );
         create table if not exists media_files(
           id integer primary key autoincrement,
           item_id text not null unique,
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
           show_id integer,
           season_id integer,
           episode_id integer,
           movie_id integer,
           media_type text,
           version_id integer,
           parse_source text,
           parse_confidence real,
           parse_warnings_json text,
           parsed_version_name text,
           parsed_version_tags_json text,
           parsed_version_dir_path text,
           media_kind_hint text,
           manual_series integer not null default 0,
           explicitly_selected integer not null default 0,
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
           genres_json text,
           last_synced_at integer not null,
           created_at integer not null,
           updated_at integer not null
         );
         create table if not exists tmdb_movies(
           id integer primary key autoincrement,
           tmdb_id integer not null unique,
           title text not null,
           original_title text,
           overview text,
           release_date text,
           poster_path text,
           backdrop_path text,
           logo_path text,
           vote_average real,
           vote_count integer,
           popularity real,
           fetched_language text not null,
           genres_json text,
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
           last_synced_at integer,
           created_at integer not null,
           updated_at integer not null,
           unique(show_id, season_number, episode_number),
           foreign key(show_id) references tmdb_tv_shows(id) on delete cascade,
           foreign key(season_id) references tmdb_tv_seasons(id) on delete cascade
         );
         create table if not exists media_versions(
           id integer primary key autoincrement,
           media_type text not null default 'tv',
           show_id integer,
           movie_id integer,
           source_id text,
           version_name text not null,
           version_dir_path text,
           resolution text,
           quality_tag text,
           source_tag text,
           codec text,
           audio_tag text,
           subtitle_tag text,
           extra_tags_json text,
           created_at integer not null,
           updated_at integer not null,
           unique(media_type, show_id, movie_id, source_id, version_dir_path),
           foreign key(show_id) references tmdb_tv_shows(id) on delete cascade,
           foreign key(movie_id) references tmdb_movies(id) on delete cascade
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
           title_dir_path text,
           normalized_title text,
           parse_source text,
           parse_warnings_json text,
           created_at integer not null,
           updated_at integer not null,
           unique(folder_id, provider),
           foreign key(folder_id) references source_folders(id) on delete cascade,
           foreign key(show_id) references tmdb_tv_shows(id) on delete cascade
         );
         create table if not exists source_folder_movie_matches(
           id integer primary key autoincrement,
           folder_id integer not null,
           movie_id integer not null,
           provider text not null default 'tmdb',
           match_status text not null,
           search_query text,
           selected_tmdb_id integer not null,
           matched_by text,
           title_dir_path text,
           normalized_title text,
           parse_source text,
           parse_warnings_json text,
           created_at integer not null,
           updated_at integer not null,
           unique(folder_id, provider),
           foreign key(folder_id) references source_folders(id) on delete cascade,
           foreign key(movie_id) references tmdb_movies(id) on delete cascade
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
           version_id integer,
           parse_source text,
           parse_confidence real,
           parse_warnings_json text,
           created_at integer not null,
           updated_at integer not null,
           unique(file_id),
           foreign key(file_id) references media_files(id) on delete cascade,
           foreign key(show_id) references tmdb_tv_shows(id) on delete cascade,
           foreign key(season_id) references tmdb_tv_seasons(id) on delete set null,
           foreign key(episode_id) references tmdb_tv_episodes(id) on delete set null,
           foreign key(version_id) references media_versions(id) on delete set null
         );
         create table if not exists media_file_movie_matches(
           id integer primary key autoincrement,
           file_id integer not null,
           movie_id integer not null,
           provider text not null default 'tmdb',
           match_status text not null,
           match_score real,
           search_query text,
           selected_tmdb_id integer,
           matched_by text,
           version_id integer,
           parse_source text,
           parse_confidence real,
           parse_warnings_json text,
           created_at integer not null,
           updated_at integer not null,
           unique(file_id),
           foreign key(file_id) references media_files(id) on delete cascade,
           foreign key(movie_id) references tmdb_movies(id) on delete cascade,
           foreign key(version_id) references media_versions(id) on delete set null
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
         create table if not exists metadata_flags(
           key text primary key,
           value text not null,
           updated_at integer not null
         );
         create index if not exists idx_source_folders_source on source_folders(source_id);
         create index if not exists idx_media_files_folder on media_files(folder_id);
         create index if not exists idx_media_files_source_path on media_files(source_id, relative_path);
         create index if not exists idx_media_files_guess on media_files(guess_title, guess_season, guess_episode);
         create index if not exists idx_media_files_show_season_version on media_files(show_id, guess_season, version_id);
         create index if not exists idx_media_files_episode_version on media_files(show_id, season_id, episode_id, version_id);
         create index if not exists idx_media_versions_tv on media_versions(media_type, show_id);
         create index if not exists idx_media_versions_movie on media_versions(media_type, movie_id);
         create index if not exists idx_media_versions_tv_source on media_versions(media_type, show_id, source_id);
         create index if not exists idx_media_versions_movie_source on media_versions(media_type, movie_id, source_id);
         create index if not exists idx_playback_recent on playback_progress(last_played_at desc);
         create index if not exists idx_folder_matches_folder on source_folder_matches(folder_id);
         create index if not exists idx_folder_matches_show on source_folder_matches(show_id);
         create index if not exists idx_source_folder_matches_title_dir on source_folder_matches(title_dir_path);
         create index if not exists idx_folder_movie_matches_folder on source_folder_movie_matches(folder_id);
         create index if not exists idx_folder_movie_matches_movie on source_folder_movie_matches(movie_id);
         create index if not exists idx_source_folder_movie_matches_title_dir on source_folder_movie_matches(title_dir_path);
         create index if not exists idx_file_matches_episode on media_file_matches(episode_id);
         create index if not exists idx_media_file_matches_version on media_file_matches(version_id);
         create index if not exists idx_file_movie_matches_movie on media_file_movie_matches(movie_id);
         create index if not exists idx_media_file_movie_matches_version on media_file_movie_matches(version_id);
         create index if not exists idx_tmdb_episodes_lookup on tmdb_tv_episodes(show_id, season_number, episode_number);
          create index if not exists idx_image_cache_path_size on image_cache(provider, file_path, size);",
    )?;
    add_column_if_missing(&conn, "sources", "username", "text")?;
    add_column_if_missing(&conn, "sources", "password", "text")?;
    add_column_if_missing(&conn, "sources", "otp_code", "text")?;
    add_column_if_missing(
        &conn,
        "source_folders",
        "manual_series",
        "integer not null default 0",
    )?;
    add_column_if_missing(&conn, "tmdb_tv_shows", "genres_json", "text")?;
    add_column_if_missing(&conn, "tmdb_movies", "genres_json", "text")?;
    for (column, ty) in [
        ("show_id", "integer"),
        ("season_id", "integer"),
        ("episode_id", "integer"),
        ("movie_id", "integer"),
        ("media_type", "text"),
        ("version_id", "integer"),
        ("parse_source", "text"),
        ("parse_confidence", "real"),
        ("parse_warnings_json", "text"),
        ("parsed_version_name", "text"),
        ("parsed_version_tags_json", "text"),
        ("parsed_version_dir_path", "text"),
        ("manual_series", "integer not null default 0"),
        ("explicitly_selected", "integer not null default 0"),
    ] {
        add_column_if_missing(&conn, "media_files", column, ty)?;
    }
    for (column, ty) in [("media_type", "text"), ("movie_id", "integer")] {
        add_column_if_missing(&conn, "media_versions", column, ty)?;
    }
    conn.execute(
        "update media_versions set media_type='tv' where media_type is null or media_type=''",
        [],
    )?;
    for (column, ty) in [
        ("title_dir_path", "text"),
        ("normalized_title", "text"),
        ("parse_source", "text"),
        ("parse_warnings_json", "text"),
    ] {
        add_column_if_missing(&conn, "source_folder_matches", column, ty)?;
    }
    for (column, ty) in [
        ("title_dir_path", "text"),
        ("normalized_title", "text"),
        ("parse_source", "text"),
        ("parse_warnings_json", "text"),
    ] {
        add_column_if_missing(&conn, "source_folder_movie_matches", column, ty)?;
    }
    for (column, ty) in [
        ("version_id", "integer"),
        ("parse_source", "text"),
        ("parse_confidence", "real"),
        ("parse_warnings_json", "text"),
    ] {
        add_column_if_missing(&conn, "media_file_matches", column, ty)?;
    }
    for (column, ty) in [
        ("version_id", "integer"),
        ("parse_source", "text"),
        ("parse_confidence", "real"),
        ("parse_warnings_json", "text"),
    ] {
        add_column_if_missing(&conn, "media_file_movie_matches", column, ty)?;
    }
    drop_column_if_exists(&conn, "tmdb_tv_shows", "raw_json")?;
    drop_column_if_exists(&conn, "tmdb_movies", "raw_json")?;
    drop_column_if_exists(&conn, "match_candidates", "raw_json")?;
    drop_column_if_exists(&conn, "tmdb_tv_seasons", "raw_json")?;
    drop_column_if_exists(&conn, "tmdb_tv_episodes", "raw_json")?;
    drop_column_if_exists(&conn, "tmdb_people_cache", "raw_json")?;
    drop_column_if_exists(&conn, "tmdb_credits", "raw_json")?;
    conn.execute_batch("pragma foreign_keys = on;")?;
    Ok(conn)
}

fn reset_incompatible_legacy_schema(conn: &Connection) -> Result<()> {
    let has_legacy_metadata = [
        "metadata",
        "metadata_titles",
        "metadata_episodes",
        "metadata_images",
        "app_state",
    ]
    .iter()
    .any(|table| table_exists(conn, table).unwrap_or(false));
    let has_legacy_media_files =
        table_exists(conn, "media_files")? && column_exists(conn, "media_files", "legacy_item_id")?;
    if !has_legacy_metadata && !has_legacy_media_files {
        return Ok(());
    }

    conn.execute_batch(
        "pragma foreign_keys = off;
         drop table if exists metadata_sync_state;
         drop table if exists api_cache;
         drop table if exists tmdb_credits;
         drop table if exists tmdb_people_cache;
         drop table if exists image_cache;
         drop table if exists tmdb_images;
         drop table if exists media_file_movie_matches;
         drop table if exists media_file_matches;
         drop table if exists media_versions;
         drop table if exists source_folder_movie_matches;
         drop table if exists source_folder_matches;
         drop table if exists match_candidates;
         drop table if exists match_tasks;
         drop table if exists folder_preferences;
         drop table if exists playback_progress;
         drop table if exists tmdb_tv_episodes;
         drop table if exists tmdb_tv_seasons;
         drop table if exists tmdb_tv_shows;
         drop table if exists tmdb_movies;
         drop table if exists media_files;
         drop table if exists source_folders;
         drop table if exists sources;
         drop table if exists metadata_images;
         drop table if exists metadata_episodes;
         drop table if exists metadata_titles;
         drop table if exists metadata;
         drop table if exists app_state;
         pragma foreign_keys = on;",
    )?;
    Ok(())
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

fn table_exists(conn: &Connection, table: &str) -> Result<bool> {
    Ok(conn.query_row(
        "select exists(select 1 from sqlite_master where type='table' and name=?1)",
        params![table],
        |row| row.get(0),
    )?)
}

fn column_exists(conn: &Connection, table: &str, column: &str) -> Result<bool> {
    let mut stmt = conn.prepare(&format!("pragma table_info({table})"))?;
    let rows = stmt.query_map([], |row| row.get::<_, String>(1))?;
    for row in rows {
        if row? == column {
            return Ok(true);
        }
    }
    Ok(false)
}

fn drop_column_if_exists(conn: &Connection, table: &str, column: &str) -> Result<()> {
    if column_exists(conn, table, column)? {
        conn.execute_batch(&format!("alter table {table} drop column {column};"))?;
    }
    Ok(())
}

fn export_library_state_json(conn: &Connection) -> Result<String> {
    let mut sources = Vec::new();
    let mut stmt = conn.prepare(
        "select id, name, type, coalesce(base_url, ''), coalesce(root_path, '/'),
                coalesce(username, ''), coalesce(password, ''), coalesce(otp_code, '')
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
            row.get::<_, String>(7)?,
        ))
    })?;
    for row in rows {
        let (id, name, source_type, base_url, root_path, username, password, otp_code) = row?;
        let selected_paths = query_selected_paths(conn, &id)?;
        let series_paths = query_series_paths(conn, &id)?;
        let mut object = Map::new();
        object.insert("id".to_string(), Value::String(id));
        object.insert("name".to_string(), Value::String(name));
        object.insert("type".to_string(), Value::String(source_type));
        object.insert("directory".to_string(), Value::String(root_path));
        object.insert("baseUrl".to_string(), Value::String(base_url));
        object.insert("username".to_string(), Value::String(username));
        object.insert("password".to_string(), Value::String(password));
        object.insert("otpCode".to_string(), Value::String(otp_code));
        object.insert(
            "selectedPaths".to_string(),
            Value::Array(selected_paths.into_iter().map(Value::String).collect()),
        );
        object.insert(
            "seriesPaths".to_string(),
            Value::Array(series_paths.into_iter().map(Value::String).collect()),
        );
        sources.push(Value::Object(object));
    }

    let mut items = Vec::new();
    let mut stmt = conn.prepare(
        "select mf.item_id, mf.source_id, s.name, s.type,
                coalesce(s.base_url, ''), mf.relative_path, mf.filename,
                coalesce(mf.guess_title, ''), mf.guess_season, mf.guess_episode,
                coalesce(mf.media_kind_hint, 'Unknown'), mf.size, sf.path,
                mf.parsed_version_name, mf.parsed_version_dir_path,
                mf.manual_series
         from media_files mf
         join sources s on s.id = mf.source_id
         join source_folders sf on sf.id = mf.folder_id
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
            row.get::<_, String>(12)?,
            row.get::<_, Option<String>>(13)?,
            row.get::<_, Option<String>>(14)?,
            row.get::<_, i64>(15)?,
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
            group_path,
            version_name,
            version_dir_path,
            manual_series,
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
            Value::String(if manual_series != 0 {
                display_name_from_path(&group_path)
            } else {
                display_name_from_path(&parent_path(&relative_path))
            }),
        );
        object.insert("matchTitle".to_string(), Value::String(guess_title));
        insert_optional_i64(&mut object, "season", guess_season);
        insert_optional_i64(&mut object, "episode", guess_episode);
        object.insert("mediaKind".to_string(), Value::String(media_kind));
        object.insert("groupPath".to_string(), Value::String(group_path));
        insert_optional_string(&mut object, "versionName", version_name);
        insert_optional_string(&mut object, "versionDirPath", version_dir_path);
        object.insert("manualSeries".to_string(), Value::Bool(manual_series != 0));
        insert_optional_i64(&mut object, "size", size);
        items.push(Value::Object(object));
    }

    let mut progress = Map::new();
    let mut durations = Map::new();
    let mut last_played_at = Map::new();
    let mut stmt = conn.prepare(
        "select mf.item_id, p.position_ms, p.duration_ms, p.last_played_at
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
        "select mf.relative_path
         from media_files mf
         where mf.source_id=?1 and mf.scan_status='active' and mf.explicitly_selected=1
         union
         select sf.path
         from source_folders sf
         where sf.source_id=?1 and sf.selected=1
           and not exists(
             select 1 from media_files mf
             where mf.folder_id=sf.id
               and mf.scan_status='active'
               and mf.explicitly_selected=1
           )
         order by 1",
    )?;
    let rows = stmt.query_map(params![source_id], |row| row.get::<_, String>(0))?;
    let mut values = Vec::new();
    for row in rows {
        values.push(row?);
    }
    Ok(values)
}

fn query_series_paths(conn: &Connection, source_id: &str) -> Result<Vec<String>> {
    let mut stmt = conn.prepare(
        "select mf.relative_path
         from media_files mf
         where mf.source_id=?1
           and mf.scan_status='active'
           and mf.manual_series=1
           and mf.explicitly_selected=1
         union
         select sf.path
         from source_folders sf
         where sf.source_id=?1 and sf.manual_series=1
         order by 1",
    )?;
    let rows = stmt.query_map(params![source_id], |row| row.get::<_, String>(0))?;
    let mut values = Vec::new();
    for row in rows {
        values.push(row?);
    }
    Ok(values)
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
    let mut explicitly_selected_files = HashSet::new();

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
        let root_path = source.get("directory").and_then(Value::as_str).unwrap_or(
            if is_remote_source_type(source_type) {
                "/"
            } else {
                ""
            },
        );
        let username = source.get("username").and_then(Value::as_str).unwrap_or("");
        let password = source.get("password").and_then(Value::as_str).unwrap_or("");
        let otp_code = source.get("otpCode").and_then(Value::as_str).unwrap_or("");
        let credential_id = if is_remote_source_type(source_type) {
            Some(format!("source:{source_id}"))
        } else {
            None
        };
        live_source_ids.insert(source_id.to_string());
        conn.execute(
            "insert into sources(id, name, type, base_url, root_path, username, password, otp_code, credential_id, created_at, updated_at)
             values (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?10)
             on conflict(id) do update set
               name=excluded.name,
               type=excluded.type,
               base_url=excluded.base_url,
               root_path=excluded.root_path,
               username=excluded.username,
               password=excluded.password,
               otp_code=excluded.otp_code,
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
                empty_to_null(otp_code),
                credential_id,
                now
            ],
        )?;
        conn.execute(
            "update source_folders set selected=0, manual_series=0, updated_at=?2 where source_id=?1",
            params![source_id, now],
        )?;

        let series_paths: HashSet<String> = source
            .get("seriesPaths")
            .and_then(Value::as_array)
            .into_iter()
            .flatten()
            .filter_map(Value::as_str)
            .map(normalize_resource_path)
            .collect();
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
                explicitly_selected_files.insert(format!("{source_id}\n{normalized}"));
                (parent_path(&normalized), file_stem(&normalized))
            } else {
                (normalize_folder_path(&normalized), None)
            };
            let manual_series =
                !is_video_resource_path(&normalized) && series_paths.contains(&normalized);
            upsert_source_folder(
                conn,
                source_id,
                &folder_path,
                search_hint.as_deref(),
                true,
                manual_series,
                now,
            )?;
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
        let parsed_candidates =
            parse_media_path_candidates(parser_source_type(item_type), &relative_path)
                .unwrap_or_default();
        let parsed = parsed_candidates.first();
        let manual_series = item
            .get("manualSeries")
            .and_then(Value::as_bool)
            .unwrap_or(false);
        let manual_group_path = if manual_series {
            item.get("groupPath")
                .and_then(Value::as_str)
                .filter(|value| !value.trim().is_empty())
        } else {
            None
        };
        let manual_title = if manual_series {
            item.get("matchTitle")
                .and_then(Value::as_str)
                .filter(|value| !value.trim().is_empty())
                .or_else(|| item.get("folderTitle").and_then(Value::as_str))
                .or_else(|| item.get("title").and_then(Value::as_str))
        } else {
            None
        };
        let guess_title = manual_title.or_else(|| {
            parsed
                .map(|candidate| candidate.title.as_str())
                .filter(|value| !value.trim().is_empty())
                .or_else(|| item.get("matchTitle").and_then(Value::as_str))
                .or_else(|| item.get("title").and_then(Value::as_str))
        });
        let guess_season = parsed
            .and_then(|candidate| candidate.season_number.map(i64::from))
            .or_else(|| item.get("season").and_then(Value::as_i64));
        let guess_episode = parsed
            .and_then(|candidate| candidate.episode_number.map(i64::from))
            .or_else(|| item.get("episode").and_then(Value::as_i64));
        let parse_source = parsed.map(|candidate| candidate.source_type.as_str());
        let parse_confidence = parsed.map(|candidate| candidate.confidence);
        let parse_warnings_json = parsed
            .map(|candidate| serde_json::to_string(&candidate.warnings))
            .transpose()?;
        let parsed_version_name = if manual_series {
            item.get("versionName")
                .and_then(Value::as_str)
                .filter(|value| !value.trim().is_empty())
        } else {
            parsed.map(|candidate| candidate.version_name.as_str())
        };
        let parsed_version_tags_json = parsed
            .map(|candidate| serde_json::to_string(&candidate.version_tags))
            .transpose()?;
        let parsed_version_dir_path = if manual_series {
            item.get("versionDirPath")
                .and_then(Value::as_str)
                .filter(|value| !value.trim().is_empty())
        } else {
            parsed
                .map(|candidate| candidate.version_dir_path.as_str())
                .filter(|value| !value.trim().is_empty())
        };
        let media_type_hint = if manual_series {
            Some("tv")
        } else {
            parsed
                .map(|candidate| candidate.media_type_hint.as_str())
                .filter(|value| *value == "tv" || *value == "movie")
        };
        let folder_path = manual_group_path
            .map(normalize_folder_path)
            .unwrap_or_else(|| {
                parsed
                    .map(|candidate| {
                        parsed_source_folder_path(&relative_path, &candidate.source_path)
                    })
                    .filter(|value| !value.trim().is_empty())
                    .unwrap_or_else(|| parent_path(&relative_path))
            });
        let folder_id = upsert_source_folder(
            conn,
            source_id,
            &folder_path,
            guess_title,
            false,
            manual_series,
            now,
        )?;
        live_folder_keys.insert(format!("{source_id}\n{folder_path}"));
        live_item_ids.insert(item_id.to_string());
        let explicitly_selected =
            explicitly_selected_files.contains(&format!("{source_id}\n{relative_path}"));
        conn.execute(
            "insert into media_files(
               item_id, source_id, folder_id, relative_path, filename, file_ext,
               size, guess_title, guess_season, guess_episode, guess_quality,
               media_type,
               parse_source, parse_confidence, parse_warnings_json,
               parsed_version_name, parsed_version_tags_json, parsed_version_dir_path,
               media_kind_hint, manual_series, explicitly_selected, scan_status, created_at, updated_at
             )
             values (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16, ?17, ?18, ?19, ?20, ?21, 'active', ?22, ?22)
             on conflict(item_id) do update set
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
               media_type=coalesce(excluded.media_type, media_files.media_type),
               parse_source=excluded.parse_source,
               parse_confidence=excluded.parse_confidence,
               parse_warnings_json=excluded.parse_warnings_json,
               parsed_version_name=excluded.parsed_version_name,
               parsed_version_tags_json=excluded.parsed_version_tags_json,
               parsed_version_dir_path=excluded.parsed_version_dir_path,
               media_kind_hint=excluded.media_kind_hint,
               manual_series=excluded.manual_series,
               explicitly_selected=excluded.explicitly_selected,
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
                guess_title,
                guess_season,
                guess_episode,
                guess_quality(&relative_path),
                media_type_hint,
                parse_source,
                parse_confidence,
                parse_warnings_json,
                parsed_version_name,
                parsed_version_tags_json,
                parsed_version_dir_path,
                item.get("mediaKind").and_then(Value::as_str),
                manual_series as i64,
                explicitly_selected as i64,
                now
            ],
        )?;
        let file_id = media_file_id(conn, item_id)?;
        auto_bind_media_file_to_cached_tmdb(conn, file_id, now)?;
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
        if let Some((source_id, path)) = folder_preference_key_parts(&folder_key) {
            let folder_id = upsert_source_folder(conn, &source_id, &path, None, false, false, now)?;
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

    for item_id in query_string_column(conn, "select item_id from media_files")? {
        if !live_item_ids.contains(&item_id) {
            conn.execute("delete from media_files where item_id=?1", params![item_id])?;
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
    match value.get("mediaType").and_then(Value::as_str) {
        Some("tv") => upsert_tmdb_tv_metadata(conn, title_key, item_id, value),
        Some("movie") => upsert_tmdb_movie_metadata(conn, title_key, item_id, value),
        _ => Ok(()),
    }
}

fn upsert_tmdb_tv_metadata(
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
           tmdb_id, name, original_name, overview, first_air_date, type,
           number_of_seasons, number_of_episodes, poster_path, backdrop_path,
           logo_path, vote_average, fetched_language, genres_json, last_synced_at,
           created_at, updated_at
         )
         values (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, 'unknown', ?13, ?14, ?14, ?14)
         on conflict(tmdb_id) do update set
           name=excluded.name,
           original_name=excluded.original_name,
           overview=excluded.overview,
           first_air_date=excluded.first_air_date,
           type=excluded.type,
           number_of_seasons=excluded.number_of_seasons,
           number_of_episodes=excluded.number_of_episodes,
           poster_path=excluded.poster_path,
           backdrop_path=excluded.backdrop_path,
           logo_path=excluded.logo_path,
           vote_average=excluded.vote_average,
           genres_json=excluded.genres_json,
           last_synced_at=excluded.last_synced_at,
           updated_at=excluded.updated_at",
        params![
            tmdb_id,
            title,
            value.get("originalTitle").and_then(Value::as_str),
            value.get("overview").and_then(Value::as_str),
            value.get("releaseDate").and_then(Value::as_str),
            value.get("tmdbType").and_then(Value::as_str),
            value.get("totalSeasons").and_then(Value::as_i64),
            value.get("totalEpisodes").and_then(Value::as_i64),
            value.get("posterPath").and_then(Value::as_str),
            value.get("backdropPath").and_then(Value::as_str),
            value.get("logoPath").and_then(Value::as_str),
            value.get("voteAverage").and_then(Value::as_f64),
            genres_json(value),
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
    upsert_tmdb_show_seasons(conn, show_id, value, now)?;

    let file_id = match media_file_id(conn, item_id) {
        Ok(file_id) => file_id,
        Err(_) => return Ok(()),
    };
    let (
        folder_id,
        season,
        episode,
        guess_title,
        parse_source,
        parse_confidence,
        parse_warnings_json,
        title_dir_path,
    ) = conn.query_row(
        "select folder_id, guess_season, guess_episode, guess_title,
                parse_source, parse_confidence, parse_warnings_json, parsed_version_dir_path
         from media_files where id=?1",
        params![file_id],
        |row| {
            Ok((
                row.get::<_, Option<i64>>(0)?,
                row.get::<_, Option<i64>>(1)?,
                row.get::<_, Option<i64>>(2)?,
                row.get::<_, Option<String>>(3)?,
                row.get::<_, Option<String>>(4)?,
                row.get::<_, Option<f64>>(5)?,
                row.get::<_, Option<String>>(6)?,
                row.get::<_, Option<String>>(7)?,
            ))
        },
    )?;
    if let Some(folder_id) = folder_id {
        conn.execute(
            "delete from source_folder_movie_matches where folder_id=?1",
            params![folder_id],
        )?;
        conn.execute(
            "insert into source_folder_matches(
               folder_id, show_id, match_status, search_query, selected_tmdb_id,
               matched_by, title_dir_path, normalized_title, parse_source, parse_warnings_json,
               created_at, updated_at
             )
             values (?1, ?2, 'auto', ?3, ?4, 'tmdb-api', ?5, ?6, ?7, ?8, ?9, ?9)
             on conflict(folder_id, provider) do update set
               show_id=excluded.show_id,
               match_status=excluded.match_status,
               search_query=excluded.search_query,
               selected_tmdb_id=excluded.selected_tmdb_id,
               matched_by=excluded.matched_by,
               title_dir_path=excluded.title_dir_path,
               normalized_title=excluded.normalized_title,
               parse_source=excluded.parse_source,
               parse_warnings_json=excluded.parse_warnings_json,
               updated_at=excluded.updated_at",
            params![
                folder_id,
                show_id,
                guess_title,
                tmdb_id,
                title_dir_path,
                guess_title,
                parse_source,
                parse_warnings_json,
                now
            ],
        )?;
    }

    let season_number = season.unwrap_or(1);
    upsert_tmdb_season_summary(
        conn,
        show_id,
        season_number,
        value.get("seasonTmdbId").and_then(Value::as_i64),
        value.get("seasonName").and_then(Value::as_str),
        value.get("seasonOverview").and_then(Value::as_str),
        value.get("seasonAirDate").and_then(Value::as_str),
        value.get("seasonEpisodeCount").and_then(Value::as_i64),
        value.get("seasonPosterPath").and_then(Value::as_str),
        value.get("seasonVoteAverage").and_then(Value::as_f64),
        now,
    )?;
    let season_id: i64 = conn.query_row(
        "select id from tmdb_tv_seasons where show_id=?1 and season_number=?2",
        params![show_id, season_number],
        |row| row.get(0),
    )?;
    insert_tmdb_image(
        conn,
        "season",
        season_id,
        "poster",
        value.get("seasonPosterPath").and_then(Value::as_str),
        now,
    )?;
    upsert_tmdb_season_episodes(conn, show_id, season_id, season_number, value, now)?;
    let episode_id = if let Some(episode_number) = episode {
        conn.execute(
            "insert into tmdb_tv_episodes(
               show_id, season_id, tmdb_id, season_number, episode_number,
               name, overview, air_date, runtime, still_path, episode_type,
               vote_average, vote_count, fetched_language,
               last_synced_at, created_at, updated_at
             )
             values (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, 'tmdb', ?14, ?14, ?14)
             on conflict(show_id, season_number, episode_number) do update set
               season_id=excluded.season_id,
               tmdb_id=coalesce(excluded.tmdb_id, tmdb_tv_episodes.tmdb_id),
               name=excluded.name,
               overview=coalesce(excluded.overview, tmdb_tv_episodes.overview),
               air_date=excluded.air_date,
               runtime=coalesce(excluded.runtime, tmdb_tv_episodes.runtime),
               still_path=excluded.still_path,
               episode_type=coalesce(excluded.episode_type, tmdb_tv_episodes.episode_type),
               vote_average=excluded.vote_average,
               vote_count=coalesce(excluded.vote_count, tmdb_tv_episodes.vote_count),
               fetched_language=excluded.fetched_language,
               last_synced_at=excluded.last_synced_at,
               updated_at=excluded.updated_at",
            params![
                show_id,
                season_id,
                value.get("episodeTmdbId").and_then(Value::as_i64),
                season_number,
                episode_number,
                value.get("episodeName").and_then(Value::as_str),
                value.get("episodeOverview").and_then(Value::as_str),
                value.get("releaseDate").and_then(Value::as_str),
                value.get("episodeRuntime").and_then(Value::as_i64),
                value.get("stillPath").and_then(Value::as_str),
                value.get("episodeType").and_then(Value::as_str),
                value.get("voteAverage").and_then(Value::as_f64),
                value.get("episodeVoteCount").and_then(Value::as_i64),
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
        "delete from media_file_movie_matches where file_id=?1",
        params![file_id],
    )?;
    let version_id = ensure_media_version(conn, file_id, "tv", Some(show_id), None, now)?;
    conn.execute(
        "insert into media_file_matches(
           file_id, show_id, season_id, episode_id, match_status, match_score,
           search_query, selected_tmdb_id, matched_by, version_id,
           parse_source, parse_confidence, parse_warnings_json,
           created_at, updated_at
         )
         values (?1, ?2, ?3, ?4, ?5, 1.0, ?6, ?7, 'tmdb-api', ?8, ?9, ?10, ?11, ?12, ?12)
         on conflict(file_id) do update set
           show_id=excluded.show_id,
           season_id=excluded.season_id,
           episode_id=excluded.episode_id,
           match_status=excluded.match_status,
           match_score=excluded.match_score,
           search_query=excluded.search_query,
           selected_tmdb_id=excluded.selected_tmdb_id,
           matched_by=excluded.matched_by,
           version_id=excluded.version_id,
           parse_source=excluded.parse_source,
           parse_confidence=excluded.parse_confidence,
           parse_warnings_json=excluded.parse_warnings_json,
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
            version_id,
            parse_source,
            parse_confidence,
            parse_warnings_json,
            now
        ],
    )?;
    conn.execute(
        "update media_files
         set media_type='tv', show_id=?2, season_id=?3, episode_id=?4, movie_id=null,
             version_id=?5, updated_at=?6
         where id=?1",
        params![file_id, show_id, season_id, episode_id, version_id, now],
    )?;
    Ok(())
}

fn upsert_tmdb_movie_metadata(
    conn: &Connection,
    title_key: &str,
    item_id: &str,
    value: &Value,
) -> Result<()> {
    let Some(tmdb_id) = value.get("tmdbId").and_then(Value::as_i64) else {
        return Ok(());
    };
    let now = now_ms();
    let title = value
        .get("title")
        .and_then(Value::as_str)
        .filter(|text| !text.trim().is_empty())
        .unwrap_or("TMDB Movie");
    conn.execute(
        "insert into tmdb_movies(
           tmdb_id, title, original_title, overview, release_date,
           poster_path, backdrop_path, logo_path, vote_average,
           fetched_language, genres_json, last_synced_at, created_at, updated_at
         )
         values (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, 'unknown', ?10, ?11, ?11, ?11)
         on conflict(tmdb_id) do update set
           title=excluded.title,
           original_title=excluded.original_title,
           overview=excluded.overview,
           release_date=excluded.release_date,
           poster_path=excluded.poster_path,
           backdrop_path=excluded.backdrop_path,
           logo_path=excluded.logo_path,
           vote_average=excluded.vote_average,
           genres_json=excluded.genres_json,
           last_synced_at=excluded.last_synced_at,
           updated_at=excluded.updated_at",
        params![
            tmdb_id,
            title,
            value.get("originalTitle").and_then(Value::as_str),
            value.get("overview").and_then(Value::as_str),
            value.get("releaseDate").and_then(Value::as_str),
            value.get("posterPath").and_then(Value::as_str),
            value.get("backdropPath").and_then(Value::as_str),
            value.get("logoPath").and_then(Value::as_str),
            value.get("voteAverage").and_then(Value::as_f64),
            genres_json(value),
            now
        ],
    )?;
    let movie_id = query_row_id(conn, "select id from tmdb_movies where tmdb_id=?1", tmdb_id)?;
    upsert_tmdb_images(conn, "movie", movie_id, value, now)?;

    let file_id = match media_file_id(conn, item_id) {
        Ok(file_id) => file_id,
        Err(_) => return Ok(()),
    };
    let (
        folder_id,
        guess_title,
        parse_source,
        parse_confidence,
        parse_warnings_json,
        title_dir_path,
    ) = conn.query_row(
        "select folder_id, guess_title, parse_source, parse_confidence,
                parse_warnings_json, parsed_version_dir_path
         from media_files where id=?1",
        params![file_id],
        |row| {
            Ok((
                row.get::<_, Option<i64>>(0)?,
                row.get::<_, Option<String>>(1)?,
                row.get::<_, Option<String>>(2)?,
                row.get::<_, Option<f64>>(3)?,
                row.get::<_, Option<String>>(4)?,
                row.get::<_, Option<String>>(5)?,
            ))
        },
    )?;
    if let Some(folder_id) = folder_id {
        conn.execute(
            "delete from source_folder_matches where folder_id=?1",
            params![folder_id],
        )?;
        conn.execute(
            "insert into source_folder_movie_matches(
               folder_id, movie_id, match_status, search_query, selected_tmdb_id,
               matched_by, title_dir_path, normalized_title, parse_source, parse_warnings_json,
               created_at, updated_at
             )
             values (?1, ?2, 'auto', ?3, ?4, 'tmdb-api', ?5, ?6, ?7, ?8, ?9, ?9)
             on conflict(folder_id, provider) do update set
               movie_id=excluded.movie_id,
               match_status=excluded.match_status,
               search_query=excluded.search_query,
               selected_tmdb_id=excluded.selected_tmdb_id,
               matched_by=excluded.matched_by,
               title_dir_path=excluded.title_dir_path,
               normalized_title=excluded.normalized_title,
               parse_source=excluded.parse_source,
               parse_warnings_json=excluded.parse_warnings_json,
               updated_at=excluded.updated_at",
            params![
                folder_id,
                movie_id,
                guess_title,
                tmdb_id,
                title_dir_path,
                guess_title,
                parse_source,
                parse_warnings_json,
                now
            ],
        )?;
    }
    conn.execute(
        "delete from media_file_matches where file_id=?1",
        params![file_id],
    )?;
    let version_id = ensure_media_version(conn, file_id, "movie", None, Some(movie_id), now)?;
    conn.execute(
        "insert into media_file_movie_matches(
           file_id, movie_id, match_status, match_score, search_query,
           selected_tmdb_id, matched_by, version_id, parse_source, parse_confidence,
           parse_warnings_json, created_at, updated_at
         )
         values (?1, ?2, 'auto', 1.0, ?3, ?4, 'tmdb-api', ?5, ?6, ?7, ?8, ?9, ?9)
         on conflict(file_id) do update set
           movie_id=excluded.movie_id,
           match_status=excluded.match_status,
           match_score=excluded.match_score,
           search_query=excluded.search_query,
           selected_tmdb_id=excluded.selected_tmdb_id,
           matched_by=excluded.matched_by,
           version_id=excluded.version_id,
           parse_source=excluded.parse_source,
           parse_confidence=excluded.parse_confidence,
           parse_warnings_json=excluded.parse_warnings_json,
           updated_at=excluded.updated_at",
        params![
            file_id,
            movie_id,
            title_key,
            tmdb_id,
            version_id,
            parse_source,
            parse_confidence,
            parse_warnings_json,
            now
        ],
    )?;
    conn.execute(
        "update media_files
         set media_type='movie', movie_id=?2, show_id=null, season_id=null, episode_id=null,
             version_id=?3, updated_at=?4
         where id=?1",
        params![file_id, movie_id, version_id, now],
    )?;
    Ok(())
}

fn upsert_tmdb_season_episodes(
    conn: &Connection,
    show_id: i64,
    season_id: i64,
    season_number: i64,
    value: &Value,
    now: i64,
) -> Result<()> {
    let Some(episodes) = value.get("seasonEpisodes").and_then(Value::as_array) else {
        return Ok(());
    };
    for episode in episodes {
        let Some(episode_number) = episode.get("episodeNumber").and_then(Value::as_i64) else {
            continue;
        };
        upsert_tmdb_episode(
            conn,
            show_id,
            season_id,
            season_number,
            episode_number,
            episode,
            now,
        )?;
    }
    Ok(())
}

fn upsert_tmdb_show_seasons(
    conn: &Connection,
    show_id: i64,
    value: &Value,
    now: i64,
) -> Result<()> {
    let Some(seasons) = value.get("showSeasons").and_then(Value::as_array) else {
        return Ok(());
    };
    for season in seasons {
        let Some(season_number) = season.get("seasonNumber").and_then(Value::as_i64) else {
            continue;
        };
        upsert_tmdb_season_summary(
            conn,
            show_id,
            season_number,
            season.get("seasonTmdbId").and_then(Value::as_i64),
            season.get("seasonName").and_then(Value::as_str),
            season.get("seasonOverview").and_then(Value::as_str),
            season.get("seasonAirDate").and_then(Value::as_str),
            season.get("seasonEpisodeCount").and_then(Value::as_i64),
            season.get("seasonPosterPath").and_then(Value::as_str),
            season.get("seasonVoteAverage").and_then(Value::as_f64),
            now,
        )?;
    }
    Ok(())
}

#[allow(clippy::too_many_arguments)]
fn upsert_tmdb_season_summary(
    conn: &Connection,
    show_id: i64,
    season_number: i64,
    season_tmdb_id: Option<i64>,
    name: Option<&str>,
    overview: Option<&str>,
    air_date: Option<&str>,
    episode_count: Option<i64>,
    poster_path: Option<&str>,
    vote_average: Option<f64>,
    now: i64,
) -> Result<()> {
    conn.execute(
        "insert into tmdb_tv_seasons(
           show_id, tmdb_id, season_number, name, overview, air_date,
           episode_count, poster_path, vote_average, fetched_language,
           last_synced_at, created_at, updated_at
         )
         values (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, 'tmdb', ?10, ?10, ?10)
         on conflict(show_id, season_number) do update set
           tmdb_id=coalesce(excluded.tmdb_id, tmdb_tv_seasons.tmdb_id),
           name=coalesce(excluded.name, tmdb_tv_seasons.name),
           overview=coalesce(excluded.overview, tmdb_tv_seasons.overview),
           air_date=coalesce(excluded.air_date, tmdb_tv_seasons.air_date),
           episode_count=coalesce(excluded.episode_count, tmdb_tv_seasons.episode_count),
           poster_path=coalesce(excluded.poster_path, tmdb_tv_seasons.poster_path),
           vote_average=coalesce(excluded.vote_average, tmdb_tv_seasons.vote_average),
           fetched_language=excluded.fetched_language,
           last_synced_at=excluded.last_synced_at,
           updated_at=excluded.updated_at",
        params![
            show_id,
            season_tmdb_id,
            season_number,
            name,
            overview,
            air_date,
            episode_count,
            poster_path,
            vote_average,
            now
        ],
    )?;
    let season_id = conn.query_row(
        "select id from tmdb_tv_seasons where show_id=?1 and season_number=?2",
        params![show_id, season_number],
        |row| row.get::<_, i64>(0),
    )?;
    insert_tmdb_image(conn, "season", season_id, "poster", poster_path, now)?;
    Ok(())
}

fn upsert_tmdb_episode(
    conn: &Connection,
    show_id: i64,
    season_id: i64,
    season_number: i64,
    episode_number: i64,
    episode: &Value,
    now: i64,
) -> Result<()> {
    conn.execute(
        "insert into tmdb_tv_episodes(
           show_id, season_id, tmdb_id, season_number, episode_number,
           name, overview, air_date, runtime, still_path, episode_type,
           vote_average, vote_count, fetched_language,
           last_synced_at, created_at, updated_at
         )
         values (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, 'tmdb', ?14, ?14, ?14)
         on conflict(show_id, season_number, episode_number) do update set
           season_id=excluded.season_id,
           tmdb_id=coalesce(excluded.tmdb_id, tmdb_tv_episodes.tmdb_id),
           name=excluded.name,
           overview=coalesce(excluded.overview, tmdb_tv_episodes.overview),
           air_date=excluded.air_date,
           runtime=coalesce(excluded.runtime, tmdb_tv_episodes.runtime),
           still_path=excluded.still_path,
           episode_type=coalesce(excluded.episode_type, tmdb_tv_episodes.episode_type),
           vote_average=excluded.vote_average,
           vote_count=coalesce(excluded.vote_count, tmdb_tv_episodes.vote_count),
           fetched_language=excluded.fetched_language,
           last_synced_at=excluded.last_synced_at,
           updated_at=excluded.updated_at",
        params![
            show_id,
            season_id,
            episode.get("episodeTmdbId").and_then(Value::as_i64),
            season_number,
            episode_number,
            episode.get("episodeName").and_then(Value::as_str),
            episode.get("episodeOverview").and_then(Value::as_str),
            episode.get("releaseDate").and_then(Value::as_str),
            episode.get("episodeRuntime").and_then(Value::as_i64),
            episode.get("stillPath").and_then(Value::as_str),
            episode.get("episodeType").and_then(Value::as_str),
            episode.get("voteAverage").and_then(Value::as_f64),
            episode.get("episodeVoteCount").and_then(Value::as_i64),
            now
        ],
    )?;
    let episode_id = conn.query_row(
        "select id from tmdb_tv_episodes where show_id=?1 and season_number=?2 and episode_number=?3",
        params![show_id, season_number, episode_number],
        |row| row.get::<_, i64>(0),
    )?;
    insert_tmdb_image(
        conn,
        "episode",
        episode_id,
        "still",
        episode.get("stillPath").and_then(Value::as_str),
        now,
    )?;
    Ok(())
}

fn genres_json(value: &Value) -> String {
    value
        .get("genres")
        .and_then(Value::as_array)
        .map(|genres| Value::Array(genres.clone()).to_string())
        .unwrap_or_else(|| "[]".to_string())
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

fn upsert_source_folder(
    conn: &Connection,
    source_id: &str,
    path: &str,
    search_hint: Option<&str>,
    selected: bool,
    manual_series: bool,
    now: i64,
) -> Result<i64> {
    conn.execute(
        "insert into source_folders(source_id, path, selected, manual_series, search_hint, created_at, updated_at)
         values (?1, ?2, ?3, ?4, ?5, ?6, ?6)
         on conflict(source_id, path) do update set
           selected=max(source_folders.selected, excluded.selected),
           manual_series=max(source_folders.manual_series, excluded.manual_series),
           search_hint=case
             when excluded.selected=1 then excluded.search_hint
             when source_folders.selected=1 and source_folders.search_hint is not null
               then source_folders.search_hint
             else coalesce(excluded.search_hint, source_folders.search_hint)
           end,
           updated_at=excluded.updated_at",
        params![
            source_id,
            normalize_folder_path(path),
            selected as i64,
            manual_series as i64,
            search_hint,
            now
        ],
    )?;
    Ok(conn.query_row(
        "select id from source_folders where source_id=?1 and path=?2",
        params![source_id, normalize_folder_path(path)],
        |row| row.get(0),
    )?)
}

fn media_file_id(conn: &Connection, item_id: &str) -> Result<i64> {
    Ok(conn.query_row(
        "select id from media_files where item_id=?1",
        params![item_id],
        |row| row.get(0),
    )?)
}

fn ensure_media_version(
    conn: &Connection,
    file_id: i64,
    media_type: &str,
    show_id: Option<i64>,
    movie_id: Option<i64>,
    now: i64,
) -> Result<i64> {
    let (source_id, version_name, version_dir_path, tags_json): (
        String,
        Option<String>,
        Option<String>,
        Option<String>,
    ) = conn.query_row(
        "select source_id, parsed_version_name, parsed_version_dir_path, parsed_version_tags_json
         from media_files where id=?1",
        params![file_id],
        |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?)),
    )?;
    let normalized_name = version_name
        .filter(|value| !value.trim().is_empty())
        .unwrap_or_else(|| "Original".to_string());
    let normalized_dir = version_dir_path
        .filter(|value| !value.trim().is_empty())
        .unwrap_or_default();
    match media_type {
        "tv" => {
            let Some(show_id) = show_id else {
                anyhow::bail!("tv media version requires show_id");
            };
            let existing = conn.query_row(
                "select id from media_versions
                 where media_type='tv' and show_id=?1 and source_id=?2 and version_dir_path=?3
                 limit 1",
                params![show_id, source_id, normalized_dir],
                |row| row.get(0),
            );
            match existing {
                Ok(version_id) => {
                    conn.execute(
                        "update media_versions
                         set version_name=?2, extra_tags_json=?3, updated_at=?4
                         where id=?1",
                        params![version_id, normalized_name, tags_json, now],
                    )?;
                    Ok(version_id)
                }
                Err(rusqlite::Error::QueryReturnedNoRows) => {
                    conn.execute(
                        "insert into media_versions(
                           media_type, show_id, movie_id, source_id, version_name,
                           version_dir_path, extra_tags_json, created_at, updated_at
                         )
                         values ('tv', ?1, null, ?2, ?3, ?4, ?5, ?6, ?6)",
                        params![
                            show_id,
                            source_id,
                            normalized_name,
                            normalized_dir,
                            tags_json,
                            now
                        ],
                    )?;
                    Ok(conn.last_insert_rowid())
                }
                Err(error) => Err(error.into()),
            }
        }
        "movie" => {
            let Some(movie_id) = movie_id else {
                anyhow::bail!("movie media version requires movie_id");
            };
            let existing = conn.query_row(
                "select id from media_versions
                 where media_type='movie' and movie_id=?1 and source_id=?2 and version_dir_path=?3
                 limit 1",
                params![movie_id, source_id, normalized_dir],
                |row| row.get(0),
            );
            match existing {
                Ok(version_id) => {
                    conn.execute(
                        "update media_versions
                         set version_name=?2, extra_tags_json=?3, updated_at=?4
                         where id=?1",
                        params![version_id, normalized_name, tags_json, now],
                    )?;
                    Ok(version_id)
                }
                Err(rusqlite::Error::QueryReturnedNoRows) => {
                    conn.execute(
                        "insert into media_versions(
                           media_type, show_id, movie_id, source_id, version_name,
                           version_dir_path, extra_tags_json, created_at, updated_at
                         )
                         values ('movie', null, ?1, ?2, ?3, ?4, ?5, ?6, ?6)",
                        params![
                            movie_id,
                            source_id,
                            normalized_name,
                            normalized_dir,
                            tags_json,
                            now
                        ],
                    )?;
                    Ok(conn.last_insert_rowid())
                }
                Err(error) => Err(error.into()),
            }
        }
        _ => anyhow::bail!("unsupported media version type: {media_type}"),
    }
}

fn auto_bind_media_file_to_cached_tmdb(conn: &Connection, file_id: i64, now: i64) -> Result<()> {
    let already_matched: i64 = conn.query_row(
        "select
           (select count(*) from media_file_matches where file_id=?1) +
           (select count(*) from media_file_movie_matches where file_id=?1)",
        params![file_id],
        |row| row.get(0),
    )?;
    if already_matched > 0 {
        return Ok(());
    }

    let (folder_id, guess_season, guess_episode, guess_title) = conn.query_row(
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
    let Some(folder_id) = folder_id else {
        return Ok(());
    };

    if let (Some(season_number), Some(episode_number)) = (guess_season, guess_episode) {
        let tv_match = conn.query_row(
            "select sfm.show_id, sfm.selected_tmdb_id, e.season_id, e.id
             from source_folder_matches sfm
             join tmdb_tv_episodes e
               on e.show_id=sfm.show_id
              and e.season_number=?2
              and e.episode_number=?3
             where sfm.folder_id=?1
             limit 1",
            params![folder_id, season_number, episode_number],
            |row| {
                Ok((
                    row.get::<_, i64>(0)?,
                    row.get::<_, i64>(1)?,
                    row.get::<_, i64>(2)?,
                    row.get::<_, i64>(3)?,
                ))
            },
        );
        match tv_match {
            Ok((show_id, tmdb_id, season_id, episode_id)) => {
                let version_id =
                    ensure_media_version(conn, file_id, "tv", Some(show_id), None, now)?;
                let (parse_source, parse_confidence, parse_warnings_json) = conn.query_row(
                    "select parse_source, parse_confidence, parse_warnings_json from media_files where id=?1",
                    params![file_id],
                    |row| {
                        Ok((
                            row.get::<_, Option<String>>(0)?,
                            row.get::<_, Option<f64>>(1)?,
                            row.get::<_, Option<String>>(2)?,
                        ))
                    },
                )?;
                conn.execute(
                    "insert into media_file_matches(
                       file_id, show_id, season_id, episode_id, match_status, match_score,
                       search_query, selected_tmdb_id, matched_by, version_id,
                       parse_source, parse_confidence, parse_warnings_json,
                       created_at, updated_at
                     )
                     values (?1, ?2, ?3, ?4, 'auto', 1.0, ?5, ?6, 'cached-tmdb', ?7, ?8, ?9, ?10, ?11, ?11)
                     on conflict(file_id) do update set
                       show_id=excluded.show_id,
                       season_id=excluded.season_id,
                       episode_id=excluded.episode_id,
                       match_status=excluded.match_status,
                       match_score=excluded.match_score,
                       search_query=excluded.search_query,
                       selected_tmdb_id=excluded.selected_tmdb_id,
                       matched_by=excluded.matched_by,
                       version_id=excluded.version_id,
                       parse_source=excluded.parse_source,
                       parse_confidence=excluded.parse_confidence,
                       parse_warnings_json=excluded.parse_warnings_json,
                       updated_at=excluded.updated_at",
                    params![
                        file_id,
                        show_id,
                        season_id,
                        episode_id,
                        guess_title,
                        tmdb_id,
                        version_id,
                        parse_source,
                        parse_confidence,
                        parse_warnings_json,
                        now
                    ],
                )?;
                conn.execute(
                    "update media_files
                     set media_type='tv', show_id=?2, season_id=?3, episode_id=?4, movie_id=null,
                         version_id=?5, updated_at=?6
                     where id=?1",
                    params![file_id, show_id, season_id, episode_id, version_id, now],
                )?;
                return Ok(());
            }
            Err(rusqlite::Error::QueryReturnedNoRows) => {}
            Err(error) => return Err(error.into()),
        }
    }

    let movie_match = conn.query_row(
        "select sfmm.movie_id, sfmm.selected_tmdb_id
         from source_folder_movie_matches sfmm
         where sfmm.folder_id=?1
         limit 1",
        params![folder_id],
        |row| Ok((row.get::<_, i64>(0)?, row.get::<_, i64>(1)?)),
    );
    match movie_match {
        Ok((movie_id, tmdb_id)) => {
            let version_id =
                ensure_media_version(conn, file_id, "movie", None, Some(movie_id), now)?;
            let (parse_source, parse_confidence, parse_warnings_json) = conn.query_row(
                "select parse_source, parse_confidence, parse_warnings_json from media_files where id=?1",
                params![file_id],
                |row| {
                    Ok((
                        row.get::<_, Option<String>>(0)?,
                        row.get::<_, Option<f64>>(1)?,
                        row.get::<_, Option<String>>(2)?,
                    ))
                },
            )?;
            conn.execute(
                "insert into media_file_movie_matches(
                   file_id, movie_id, match_status, match_score, search_query,
                   selected_tmdb_id, matched_by, version_id, parse_source, parse_confidence,
                   parse_warnings_json, created_at, updated_at
                 )
                 values (?1, ?2, 'auto', 1.0, ?3, ?4, 'cached-tmdb', ?5, ?6, ?7, ?8, ?9, ?9)
                 on conflict(file_id) do update set
                   movie_id=excluded.movie_id,
                   match_status=excluded.match_status,
                   match_score=excluded.match_score,
                   search_query=excluded.search_query,
                   selected_tmdb_id=excluded.selected_tmdb_id,
                   matched_by=excluded.matched_by,
                   version_id=excluded.version_id,
                   parse_source=excluded.parse_source,
                   parse_confidence=excluded.parse_confidence,
                   parse_warnings_json=excluded.parse_warnings_json,
                   updated_at=excluded.updated_at",
                params![
                    file_id,
                    movie_id,
                    guess_title,
                    tmdb_id,
                    version_id,
                    parse_source,
                    parse_confidence,
                    parse_warnings_json,
                    now
                ],
            )?;
            conn.execute(
                "update media_files
                 set media_type='movie', movie_id=?2, show_id=null, season_id=null, episode_id=null,
                     version_id=?3, updated_at=?4
                 where id=?1",
                params![file_id, movie_id, version_id, now],
            )?;
        }
        Err(rusqlite::Error::QueryReturnedNoRows) => {}
        Err(error) => return Err(error.into()),
    }
    Ok(())
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
            insert_tmdb_image(conn, owner_type, owner_id, image_type, Some(path), now)?;
        }
    }
    Ok(())
}

fn insert_tmdb_image(
    conn: &Connection,
    owner_type: &str,
    owner_id: i64,
    image_type: &str,
    path: Option<&str>,
    now: i64,
) -> Result<()> {
    let Some(path) = path.filter(|value| !value.trim().is_empty()) else {
        return Ok(());
    };
    conn.execute(
        "insert into tmdb_images(owner_type, owner_id, image_type, file_path, created_at, updated_at)
         values (?1, ?2, ?3, ?4, ?5, ?5)
         on conflict(owner_type, owner_id, image_type, file_path) do update set
           updated_at=excluded.updated_at",
        params![owner_type, owner_id, image_type, path, now],
    )?;
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
        "delete from source_folder_movie_matches
         where not exists (
           select 1 from media_files mf where mf.folder_id=source_folder_movie_matches.folder_id
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
        "delete from media_file_movie_matches
         where not exists (
           select 1 from media_files mf where mf.id=media_file_movie_matches.file_id
         )",
        [],
    )?;
    conn.execute(
        "delete from media_versions
         where not exists (
           select 1 from media_files mf where mf.version_id=media_versions.id
         )
         and not exists (
           select 1 from media_file_matches mfm where mfm.version_id=media_versions.id
         )
         and not exists (
           select 1 from media_file_movie_matches mfmm where mfmm.version_id=media_versions.id
         )",
        [],
    )?;
    conn.execute(
        "delete from tmdb_tv_episodes
         where not exists (
           select 1 from media_file_matches mfm where mfm.episode_id=tmdb_tv_episodes.id
         )
         and not exists (
           select 1 from source_folder_matches sfm where sfm.show_id=tmdb_tv_episodes.show_id
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
         )
         and not exists (
           select 1 from source_folder_matches sfm where sfm.show_id=tmdb_tv_seasons.show_id
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
        "delete from tmdb_movies
         where not exists (
           select 1 from source_folder_movie_matches sfmm where sfmm.movie_id=tmdb_movies.id
         )
           and not exists (
             select 1 from media_file_movie_matches mfmm where mfmm.movie_id=tmdb_movies.id
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
           or (owner_type='movie' and not exists (
             select 1 from tmdb_movies m where m.id=tmdb_images.owner_id
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
    Ok(())
}

fn item_relative_path(item_type: &str, uri: &str) -> String {
    if is_remote_source_type(item_type) {
        if let Ok(url) = Url::parse(uri) {
            return normalize_resource_path(&percent_decode(url.path()));
        }
    }
    normalize_resource_path(uri)
}

fn is_remote_source_type(source_type: &str) -> bool {
    source_type == "webdav" || source_type == "openlist"
}

fn parser_source_type(source_type: &str) -> &str {
    if is_remote_source_type(source_type) {
        "webdav"
    } else {
        "local"
    }
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

fn parsed_source_folder_path(relative_path: &str, parsed_source_path: &str) -> String {
    let mut value = normalize_resource_path(parsed_source_path);
    if relative_path.starts_with('/') && !value.starts_with('/') {
        value = format!("/{value}");
    }
    normalize_folder_path(&value)
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

fn folder_preference_key_parts(value: &str) -> Option<(String, String)> {
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
    fn metadata_flag_round_trips() {
        let db_path =
            std::env::temp_dir().join(format!("player_core_metadata_flag_{}.sqlite", now_ms()));
        assert_eq!(
            get_metadata_flag_json(db_path.to_str().unwrap(), "tmdb").unwrap(),
            "null"
        );
        put_metadata_flag_json(
            db_path.to_str().unwrap(),
            "tmdb",
            r#"{"fingerprint":"abc","itemCount":2}"#,
        )
        .unwrap();
        let value: Value = serde_json::from_str(
            &get_metadata_flag_json(db_path.to_str().unwrap(), "tmdb").unwrap(),
        )
        .unwrap();
        assert_eq!(value["fingerprint"], "abc");
        assert_eq!(value["itemCount"], 2);
    }

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
        assert_eq!(items[0]["groupPath"], "/media/Show/");
        assert_eq!(items[0]["size"], 1234);
        assert_eq!(exported["progress"]["source-1:/media/Show/01.mp4"], 5000);
        assert_eq!(exported["durations"]["source-1:/media/Show/01.mp4"], 60000);
        assert_eq!(exported["lastPlayedAt"]["source-1:/media/Show/01.mp4"], 42);
        assert_eq!(
            exported["folderOrientations"]["source-1:webdav:/media/Show/"],
            "landscape"
        );

        let conn = open(db_path.to_str().unwrap()).unwrap();
        assert!(!table_exists(&conn, "app_state"));
        let _ = std::fs::remove_file(db_path);
    }

    #[test]
    fn playback_state_updates_without_full_state_replace() {
        let db_path =
            std::env::temp_dir().join(format!("player_core_playback_fast_{}.sqlite", now_ms()));
        let state = r#"{
          "version": 1,
          "sources": [
            {"id": "source-1", "name": "Local", "type": "local", "directory": "/media"}
          ],
          "items": [
            {
              "id": "source-1:/media/Show/01.mp4",
              "sourceId": "source-1",
              "sourceName": "Local",
              "type": "local",
              "title": "01",
              "uri": "/media/Show/01.mp4",
              "folderTitle": "Show",
              "matchTitle": "Show",
              "groupPath": "/media/Show",
              "mediaKind": "TV"
            }
          ],
          "progress": {},
          "durations": {},
          "lastPlayedAt": {},
          "folderOrientations": {}
        }"#;
        put_app_state_json(db_path.to_str().unwrap(), state).unwrap();

        put_playback_progress_json(
            db_path.to_str().unwrap(),
            "source-1:/media/Show/01.mp4",
            42000,
            Some(60000),
        )
        .unwrap();
        assert_eq!(
            serde_json::from_str::<Value>(&query_recent_json(db_path.to_str().unwrap()).unwrap())
                .unwrap()
                .as_array()
                .unwrap()
                .len(),
            1
        );
        clear_playback_recent_json(
            db_path.to_str().unwrap(),
            r#"["source-1:/media/Show/01.mp4"]"#,
        )
        .unwrap();
        put_folder_orientation_json(
            db_path.to_str().unwrap(),
            "source-1:local:/media/Show",
            "landscape",
        )
        .unwrap();

        let exported: Value =
            serde_json::from_str(&get_app_state_json(db_path.to_str().unwrap()).unwrap()).unwrap();
        assert_eq!(exported["items"].as_array().unwrap().len(), 1);
        assert_eq!(exported["progress"]["source-1:/media/Show/01.mp4"], 42000);
        assert_eq!(exported["durations"]["source-1:/media/Show/01.mp4"], 60000);
        assert!(exported["lastPlayedAt"]
            .get("source-1:/media/Show/01.mp4")
            .is_none());
        assert!(serde_json::from_str::<Value>(
            &query_recent_json(db_path.to_str().unwrap()).unwrap()
        )
        .unwrap()
        .as_array()
        .unwrap()
        .is_empty());
        assert_eq!(
            exported["folderOrientations"]["source-1:local:/media/Show/"],
            "landscape"
        );
        let _ = std::fs::remove_file(db_path);
    }

    #[test]
    fn manual_series_item_uses_declared_group_and_version() {
        let db_path =
            std::env::temp_dir().join(format!("player_core_manual_series_{}.sqlite", now_ms()));
        let state = r#"{
          "version": 1,
          "sources": [
            {
              "id": "source-1",
              "name": "My WebDAV",
              "type": "webdav",
              "directory": "/",
              "baseUrl": "https://example.com/dav",
              "selectedPaths": ["/Course/"],
              "seriesPaths": ["/Course/"]
            }
          ],
          "items": [
            {
              "id": "source-1:/Course/Chapter 01/001.mp4",
              "sourceId": "source-1",
              "sourceName": "My WebDAV",
              "type": "webdav",
              "title": "001",
              "uri": "https://example.com/dav/Course/Chapter%2001/001.mp4",
              "folderTitle": "Course",
              "matchTitle": "Course",
              "groupPath": "/Course",
              "versionName": "Chapter 01",
              "versionDirPath": "/Course/Chapter 01",
              "manualSeries": true,
              "mediaKind": "TvEpisode",
              "size": 1234
            }
          ],
          "progress": {},
          "durations": {},
          "lastPlayedAt": {},
          "folderOrientations": {}
        }"#;

        put_app_state_json(db_path.to_str().unwrap(), state).unwrap();
        let conn = open(db_path.to_str().unwrap()).unwrap();
        let row: (String, String, String, String) = conn
            .query_row(
                "select sf.path, mf.guess_title, mf.media_kind_hint, mf.parsed_version_name
                   from media_files mf
                   join source_folders sf on sf.id=mf.folder_id
                  where mf.item_id=?1",
                params!["source-1:/Course/Chapter 01/001.mp4"],
                |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?)),
            )
            .unwrap();
        assert_eq!(row.0, "/Course/");
        assert_eq!(row.1, "Course");
        assert_eq!(row.2, "TvEpisode");
        assert_eq!(row.3, "Chapter 01");
        drop(conn);

        let exported: Value =
            serde_json::from_str(&get_app_state_json(db_path.to_str().unwrap()).unwrap()).unwrap();
        assert_eq!(exported["sources"][0]["seriesPaths"][0], "/Course/");
        assert_eq!(exported["items"][0]["folderTitle"], "Course");
        assert_eq!(exported["items"][0]["matchTitle"], "Course");
        assert_eq!(exported["items"][0]["groupPath"], "/Course/");
        assert_eq!(exported["items"][0]["versionName"], "Chapter 01");
        assert_eq!(exported["items"][0]["manualSeries"], true);

        let _ = std::fs::remove_file(db_path);
    }

    #[test]
    fn show_detail_does_not_include_child_folder_files() {
        let db_path =
            std::env::temp_dir().join(format!("player_core_exact_folder_{}.sqlite", now_ms()));
        let conn = open(db_path.to_str().unwrap()).unwrap();
        let now = now_ms();
        conn.execute(
            "insert into sources(id, name, type, root_path, created_at, updated_at)
             values ('local-1', 'Local', 'local', 'D:/Root', ?1, ?1)",
            params![now],
        )
        .unwrap();
        let parent_id =
            upsert_source_folder(&conn, "local-1", "D:/Root/", None, true, false, now).unwrap();
        let child_id = upsert_source_folder(
            &conn,
            "local-1",
            "D:/Root/Show/",
            Some("Show"),
            false,
            false,
            now,
        )
        .unwrap();
        assert_ne!(parent_id, child_id);
        conn.execute(
            "insert into media_files(
               item_id, source_id, folder_id, relative_path, filename, scan_status,
               created_at, updated_at
             )
             values ('local-1:D:/Root/Show/01.mp4', 'local-1', ?1,
                     'D:/Root/Show/01.mp4', '01.mp4', 'active', ?2, ?2)",
            params![child_id, now],
        )
        .unwrap();
        drop(conn);

        let detail: Value = serde_json::from_str(
            &query_show_detail_json(db_path.to_str().unwrap(), "local-1:db:D:/Root/").unwrap(),
        )
        .unwrap();
        let files = detail["files"].as_array().unwrap();
        assert!(files.is_empty());

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
        assert_eq!(count_rows(&conn, "source_folder_movie_matches"), 0);
        assert_eq!(count_rows(&conn, "media_file_matches"), 0);
        assert_eq!(count_rows(&conn, "media_file_movie_matches"), 0);
        assert_eq!(count_rows(&conn, "tmdb_tv_shows"), 0);
        assert_eq!(count_rows(&conn, "tmdb_movies"), 0);
        assert_eq!(count_rows(&conn, "tmdb_tv_seasons"), 0);
        assert_eq!(count_rows(&conn, "tmdb_tv_episodes"), 0);
        assert_eq!(count_rows(&conn, "tmdb_credits"), 0);
        assert_eq!(count_rows(&conn, "tmdb_people_cache"), 0);
        assert_eq!(count_rows(&conn, "tmdb_images"), 0);
        assert_eq!(count_rows(&conn, "image_cache"), 0);

        let _ = std::fs::remove_file(db_path);
    }

    #[test]
    fn movie_metadata_round_trips_to_home_and_cache() {
        let db_path =
            std::env::temp_dir().join(format!("player_core_movie_metadata_{}.sqlite", now_ms()));
        let state = r#"{
          "version": 1,
          "sources": [
            {
              "id": "local-1",
              "name": "Local",
              "type": "local",
              "directory": "D:/Movies",
              "selectedPaths": ["D:/Movies/Films"]
            }
          ],
          "items": [
            {
              "id": "local-1:D:/Movies/Films/Movie.mp4",
              "sourceId": "local-1",
              "sourceName": "Local",
              "type": "local",
              "title": "Movie",
              "uri": "D:/Movies/Films/Movie.mp4",
              "folderTitle": "Films",
              "matchTitle": "Movie",
              "mediaKind": "Movie",
              "size": 1234
            }
          ]
        }"#;
        let metadata = r#"{
          "tmdbId": 200,
          "mediaType": "movie",
          "title": "TMDB Movie",
          "originalTitle": "Original Movie",
          "overview": "Movie overview",
          "posterPath": "/movie-poster.jpg",
          "backdropPath": "/movie-backdrop.jpg",
          "releaseDate": "2026-01-02",
          "voteAverage": 8.1,
          "updatedAt": 1
        }"#;

        put_app_state_json(db_path.to_str().unwrap(), state).unwrap();
        put_metadata_json(
            db_path.to_str().unwrap(),
            "local-1:local:D:/Movies/Films/",
            "local-1:D:/Movies/Films/Movie.mp4",
            metadata,
        )
        .unwrap();

        let home: Value =
            serde_json::from_str(&query_home_json(db_path.to_str().unwrap()).unwrap()).unwrap();
        assert_eq!(home[0]["mediaType"], "movie");
        assert_eq!(home[0]["title"], "TMDB Movie");
        assert_eq!(home[0]["matched"], true);
        assert_eq!(home[0]["totalEpisodes"], 1);

        let cache: Value =
            serde_json::from_str(&get_all_metadata_json(db_path.to_str().unwrap()).unwrap())
                .unwrap();
        let cached = &cache["local-1:D:/Movies/Films/Movie.mp4"];
        assert_eq!(cached["mediaType"], "movie");
        assert_eq!(cached["title"], "TMDB Movie");
        assert_eq!(cached["posterPath"], "/movie-poster.jpg");

        let conn = open(db_path.to_str().unwrap()).unwrap();
        assert_eq!(count_rows(&conn, "media_file_matches"), 0);
        assert_eq!(count_rows(&conn, "media_file_movie_matches"), 1);
        assert_eq!(count_rows(&conn, "tmdb_movies"), 1);
        assert_eq!(count_rows(&conn, "media_versions"), 1);
        assert_eq!(
            conn.query_row("select media_type from media_versions limit 1", [], |row| {
                row.get::<_, String>(0)
            },)
                .unwrap(),
            "movie"
        );

        drop(conn);
        let state_with_new_file = r#"{
          "version": 1,
          "sources": [
            {
              "id": "local-1",
              "name": "Local",
              "type": "local",
              "directory": "D:/Movies",
              "selectedPaths": ["D:/Movies/Films"]
            }
          ],
          "items": [
            {
              "id": "local-1:D:/Movies/Films/Movie.mp4",
              "sourceId": "local-1",
              "sourceName": "Local",
              "type": "local",
              "title": "Movie",
              "uri": "D:/Movies/Films/Movie.mp4",
              "folderTitle": "Films",
              "matchTitle": "Movie",
              "mediaKind": "Movie",
              "size": 1234
            },
            {
              "id": "local-1:D:/Movies/Films/Movie 1080p.mp4",
              "sourceId": "local-1",
              "sourceName": "Local",
              "type": "local",
              "title": "Movie 1080p",
              "uri": "D:/Movies/Films/Movie 1080p.mp4",
              "folderTitle": "Films",
              "matchTitle": "Movie",
              "mediaKind": "Movie",
              "size": 2345
            }
          ]
        }"#;
        put_app_state_json(db_path.to_str().unwrap(), state_with_new_file).unwrap();
        let conn = open(db_path.to_str().unwrap()).unwrap();
        assert_eq!(count_rows(&conn, "tmdb_movies"), 1);
        assert_eq!(count_rows(&conn, "media_file_movie_matches"), 2);
        assert_eq!(
            conn.query_row(
                "select count(*) from media_files
                 where media_type='movie' and movie_id is not null and version_id is not null",
                [],
                |row| row.get::<_, i64>(0),
            )
            .unwrap(),
            2
        );

        let _ = std::fs::remove_file(db_path);
    }

    #[test]
    fn tv_metadata_persists_full_season_episode_payload() {
        let db_path =
            std::env::temp_dir().join(format!("player_core_full_season_{}.sqlite", now_ms()));
        let state = r#"{
          "version": 1,
          "sources": [
            {
              "id": "local-1",
              "name": "Local",
              "type": "local",
              "directory": "D:/Shows",
              "selectedPaths": ["D:/Shows/Show"]
            }
          ],
          "items": [
            {
              "id": "local-1:D:/Shows/Show/01.mp4",
              "sourceId": "local-1",
              "sourceName": "Local",
              "type": "local",
              "title": "01",
              "uri": "D:/Shows/Show/01.mp4",
              "folderTitle": "Show",
              "matchTitle": "Show",
              "season": 1,
              "episode": 1,
              "mediaKind": "TvEpisode",
              "size": 1234
            }
          ]
        }"#;
        let metadata = r#"{
          "tmdbId": 100,
          "mediaType": "tv",
          "title": "TMDB Show",
          "overview": "Show overview",
          "posterPath": "/poster.jpg",
          "backdropPath": "/backdrop.jpg",
          "totalSeasons": 1,
          "totalEpisodes": 2,
          "showSeasons": [
            {
              "seasonTmdbId": 10,
              "seasonNumber": 1,
              "seasonName": "Season 1",
              "seasonOverview": "First season",
              "seasonAirDate": "2026-01-01",
              "seasonEpisodeCount": 2,
              "seasonPosterPath": "/season-1.jpg",
              "seasonVoteAverage": 8.0
            },
            {
              "seasonTmdbId": 20,
              "seasonNumber": 2,
              "seasonName": "Season 2",
              "seasonOverview": "Second season",
              "seasonAirDate": "2027-01-01",
              "seasonEpisodeCount": 2,
              "seasonPosterPath": "/season-2.jpg",
              "seasonVoteAverage": 8.2
            }
          ],
          "seasonTmdbId": 10,
          "seasonName": "Season 1",
          "seasonEpisodeCount": 2,
          "seasonEpisodes": [
            {
              "episodeTmdbId": 101,
              "seasonNumber": 1,
              "episodeNumber": 1,
              "episodeName": "Episode 1",
              "episodeOverview": "First episode",
              "releaseDate": "2026-01-01",
              "episodeRuntime": 45,
              "stillPath": "/still-1.jpg",
              "episodeType": "standard",
              "voteAverage": 8.0,
              "episodeVoteCount": 2
            },
            {
              "episodeTmdbId": 102,
              "seasonNumber": 1,
              "episodeNumber": 2,
              "episodeName": "Episode 2",
              "episodeOverview": "Second episode",
              "releaseDate": "2026-01-08",
              "episodeRuntime": 46,
              "stillPath": "/still-2.jpg",
              "episodeType": "standard",
              "voteAverage": 8.2,
              "episodeVoteCount": 3
            }
          ],
          "episodeTmdbId": 101,
          "episodeName": "Episode 1",
          "episodeOverview": "First episode",
          "releaseDate": "2026-01-01",
          "episodeRuntime": 45,
          "stillPath": "/still-1.jpg",
          "episodeType": "standard",
          "episodeVoteCount": 2,
          "updatedAt": 1,
          "schemaVersion": 11
        }"#;

        put_app_state_json(db_path.to_str().unwrap(), state).unwrap();
        put_metadata_json(
            db_path.to_str().unwrap(),
            "local-1:local:D:/Shows/Show/",
            "local-1:D:/Shows/Show/01.mp4",
            metadata,
        )
        .unwrap();

        let conn = open(db_path.to_str().unwrap()).unwrap();
        assert_eq!(count_rows(&conn, "tmdb_tv_seasons"), 2);
        assert_eq!(count_rows(&conn, "tmdb_tv_episodes"), 2);
        assert_eq!(count_rows(&conn, "media_file_matches"), 1);
        assert_eq!(count_rows(&conn, "media_versions"), 1);
        assert_eq!(
            conn.query_row("select media_type from media_versions limit 1", [], |row| {
                row.get::<_, String>(0)
            },)
                .unwrap(),
            "tv"
        );
        assert_eq!(
            conn.query_row(
                "select count(*) from tmdb_images where owner_type='episode'",
                [],
                |row| row.get::<_, i64>(0),
            )
            .unwrap(),
            2
        );

        let cache: Value =
            serde_json::from_str(&get_all_metadata_json(db_path.to_str().unwrap()).unwrap())
                .unwrap();
        let cached = &cache["local-1:D:/Shows/Show/01.mp4"];
        assert_eq!(cached["episodeName"], "Episode 1");
        assert_eq!(cached["schemaVersion"], 11);

        drop(conn);
        let state_with_new_file = r#"{
          "version": 1,
          "sources": [
            {
              "id": "local-1",
              "name": "Local",
              "type": "local",
              "directory": "D:/Shows",
              "selectedPaths": ["D:/Shows/Show"]
            }
          ],
          "items": [
            {
              "id": "local-1:D:/Shows/Show/01.mp4",
              "sourceId": "local-1",
              "sourceName": "Local",
              "type": "local",
              "title": "01",
              "uri": "D:/Shows/Show/01.mp4",
              "folderTitle": "Show",
              "matchTitle": "Show",
              "season": 1,
              "episode": 1,
              "mediaKind": "TvEpisode",
              "size": 1234
            },
            {
              "id": "local-1:D:/Shows/Show/02.mp4",
              "sourceId": "local-1",
              "sourceName": "Local",
              "type": "local",
              "title": "02",
              "uri": "D:/Shows/Show/02.mp4",
              "folderTitle": "Show",
              "matchTitle": "Show",
              "season": 1,
              "episode": 2,
              "mediaKind": "TvEpisode",
              "size": 2345
            }
          ]
        }"#;
        put_app_state_json(db_path.to_str().unwrap(), state_with_new_file).unwrap();
        let conn = open(db_path.to_str().unwrap()).unwrap();
        assert_eq!(count_rows(&conn, "tmdb_tv_seasons"), 2);
        assert_eq!(count_rows(&conn, "tmdb_tv_episodes"), 2);
        assert_eq!(count_rows(&conn, "media_file_matches"), 2);
        let cached: Value =
            serde_json::from_str(&get_all_metadata_json(db_path.to_str().unwrap()).unwrap())
                .unwrap();
        assert_eq!(
            cached["local-1:D:/Shows/Show/02.mp4"]["episodeName"],
            "Episode 2"
        );

        let _ = std::fs::remove_file(db_path);
    }

    #[test]
    fn selected_video_file_uses_file_stem_for_home_title_and_delete_prunes_it() {
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
        assert_eq!(search_hint.as_deref(), Some("01"));

        let home: Value =
            serde_json::from_str(&query_home_json(db_path.to_str().unwrap()).unwrap()).unwrap();
        assert_eq!(home[0]["title"], "01");

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

    #[test]
    fn single_unmatched_folder_file_home_title_uses_file_stem() {
        let db_path = std::env::temp_dir().join(format!(
            "player_core_single_file_home_title_{}.sqlite",
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
              "selectedPaths": ["/dav/Parent/"]
            }
          ],
          "items": [
            {
              "id": "source-1:/Parent/Movie Name.mp4",
              "sourceId": "source-1",
              "sourceName": "My WebDAV",
              "type": "webdav",
              "title": "Movie Name",
              "uri": "https://example.com/dav/Parent/Movie%20Name.mp4",
              "folderTitle": "Parent",
              "matchTitle": "Parent",
              "mediaKind": "Unknown",
              "size": 1234
            }
          ]
        }"#;

        put_app_state_json(db_path.to_str().unwrap(), state).unwrap();
        let home: Value =
            serde_json::from_str(&query_home_json(db_path.to_str().unwrap()).unwrap()).unwrap();
        assert_eq!(home[0]["title"], "Movie Name");

        let _ = std::fs::remove_file(db_path);
    }

    #[test]
    fn separately_selected_files_in_same_folder_stay_separate_on_home() {
        let db_path = std::env::temp_dir().join(format!(
            "player_core_separate_selected_files_{}.sqlite",
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
              "selectedPaths": ["/dav/Parent/A.mp4", "/dav/Parent/B.mp4"]
            }
          ],
          "items": [
            {
              "id": "source-1:/Parent/A.mp4",
              "sourceId": "source-1",
              "sourceName": "My WebDAV",
              "type": "webdav",
              "title": "A",
              "uri": "https://example.com/dav/Parent/A.mp4",
              "folderTitle": "Parent",
              "matchTitle": "Parent",
              "mediaKind": "Unknown",
              "size": 1234
            },
            {
              "id": "source-1:/Parent/B.mp4",
              "sourceId": "source-1",
              "sourceName": "My WebDAV",
              "type": "webdav",
              "title": "B",
              "uri": "https://example.com/dav/Parent/B.mp4",
              "folderTitle": "Parent",
              "matchTitle": "Parent",
              "mediaKind": "Unknown",
              "size": 2345
            }
          ]
        }"#;

        put_app_state_json(db_path.to_str().unwrap(), state).unwrap();
        let home: Value =
            serde_json::from_str(&query_home_json(db_path.to_str().unwrap()).unwrap()).unwrap();
        assert_eq!(home.as_array().unwrap().len(), 2);
        assert_eq!(home[0]["localFileCount"], 1);
        let mut titles = vec![
            home[0]["title"].as_str().unwrap().to_string(),
            home[1]["title"].as_str().unwrap().to_string(),
        ];
        titles.sort();
        assert_eq!(titles, vec!["A", "B"]);

        let exported: Value =
            serde_json::from_str(&get_app_state_json(db_path.to_str().unwrap()).unwrap()).unwrap();
        let selected = exported["sources"][0]["selectedPaths"].as_array().unwrap();
        assert_eq!(selected.len(), 2);
        assert!(selected.contains(&Value::String("/Parent/A.mp4".to_string())));
        assert!(selected.contains(&Value::String("/Parent/B.mp4".to_string())));

        let _ = std::fs::remove_file(db_path);
    }

    #[test]
    fn source_folder_is_removed_when_selection_and_files_are_empty() {
        let db_path = std::env::temp_dir().join(format!(
            "player_core_unselect_empty_folder_{}.sqlite",
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
              "selectedPaths": ["/dav/Show/"]
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
        put_app_state_json(db_path.to_str().unwrap(), initial_state).unwrap();

        let empty_selection_state = r#"{
          "version": 1,
          "sources": [
            {
              "id": "source-1",
              "name": "My WebDAV",
              "type": "webdav",
              "directory": "/dav/",
              "baseUrl": "https://example.com/dav",
              "selectedPaths": []
            }
          ],
          "items": []
        }"#;
        put_app_state_json(db_path.to_str().unwrap(), empty_selection_state).unwrap();

        let conn = open(db_path.to_str().unwrap()).unwrap();
        assert_eq!(count_rows(&conn, "sources"), 1);
        assert_eq!(count_rows(&conn, "source_folders"), 0);
        assert_eq!(count_rows(&conn, "media_files"), 0);
        let exported: Value =
            serde_json::from_str(&get_app_state_json(db_path.to_str().unwrap()).unwrap()).unwrap();
        assert!(exported["sources"][0]["selectedPaths"]
            .as_array()
            .unwrap()
            .is_empty());

        let _ = std::fs::remove_file(db_path);
    }

    #[test]
    fn legacy_schema_is_reset_without_migration() {
        let db_path =
            std::env::temp_dir().join(format!("player_core_legacy_reset_{}.sqlite", now_ms()));
        let conn = Connection::open(&db_path).unwrap();
        conn.execute_batch(
            "create table metadata_titles(title_key text primary key, json text not null);
             create table metadata_episodes(item_id text primary key, title_key text not null, json text not null);
             create table media_files(
               id integer primary key autoincrement,
               legacy_item_id text not null unique
             );",
        )
        .unwrap();
        drop(conn);

        let conn = open(db_path.to_str().unwrap()).unwrap();
        assert!(!table_exists(&conn, "metadata_titles"));
        assert!(!table_exists(&conn, "metadata_episodes"));
        assert!(column_exists(&conn, "media_files", "item_id").unwrap());
        assert!(!column_exists(&conn, "media_files", "legacy_item_id").unwrap());

        let _ = std::fs::remove_file(db_path);
    }

    #[test]
    fn open_creates_missing_database_parent_directory() {
        let db_dir = std::env::temp_dir().join(format!("player_core_missing_parent_{}", now_ms()));
        let db_path = db_dir.join("nested").join("metadata.sqlite");
        let state = r#"{"version":1,"sources":[],"items":[]}"#;

        put_app_state_json(db_path.to_str().unwrap(), state).unwrap();

        assert!(db_path.exists());
        let _ = std::fs::remove_dir_all(db_dir);
    }

    fn count_rows(conn: &Connection, table: &str) -> i64 {
        conn.query_row(&format!("select count(*) from {table}"), [], |row| {
            row.get(0)
        })
        .unwrap()
    }

    fn table_exists(conn: &Connection, table: &str) -> bool {
        conn.query_row(
            "select exists(select 1 from sqlite_master where type='table' and name=?1)",
            params![table],
            |row| row.get(0),
        )
        .unwrap()
    }
}

fn query_show_genres(conn: &Connection, show_id: i64) -> Result<Value> {
    let genres_json: Option<String> = conn
        .query_row(
            "select genres_json from tmdb_tv_shows where id=?1",
            params![show_id],
            |row| row.get(0),
        )
        .unwrap_or(None);
    genres_from_json_text(genres_json.as_deref())
}

fn query_movie_genres(conn: &Connection, movie_id: i64) -> Result<Value> {
    let genres_json: Option<String> = conn
        .query_row(
            "select genres_json from tmdb_movies where id=?1",
            params![movie_id],
            |row| row.get(0),
        )
        .unwrap_or(None);
    genres_from_json_text(genres_json.as_deref())
}

fn genres_from_json_text(genres_json: Option<&str>) -> Result<Value> {
    if let Some(text) = genres_json.filter(|text| !text.trim().is_empty()) {
        let value: Value = serde_json::from_str(text)?;
        if let Value::Array(_) = value {
            return Ok(normalize_genres_array(&value));
        }
    }
    Ok(Value::Array(Vec::new()))
}

fn normalize_genres_array(value: &Value) -> Value {
    let values = value
        .as_array()
        .into_iter()
        .flatten()
        .filter_map(|entry| {
            entry
                .as_str()
                .or_else(|| entry.get("name").and_then(Value::as_str))
        })
        .filter(|text| !text.trim().is_empty())
        .map(|text| Value::String(text.to_string()))
        .collect();
    Value::Array(values)
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
