use anyhow::Result;
use rusqlite::{params, Connection};
use serde_json::{Map, Value};

pub fn put_metadata_json(db_path: &str, item_id: &str, metadata_json: &str) -> Result<()> {
    let value: Value = serde_json::from_str(metadata_json)?;
    let tmdb_id = value.get("tmdbId").and_then(Value::as_i64);
    let media_type = value.get("mediaType").and_then(Value::as_str);
    let updated_at = value.get("updatedAt").and_then(Value::as_i64);
    let conn = open(db_path)?;
    conn.execute(
        "insert into metadata(item_id, tmdb_id, media_type, json, updated_at)
         values (?1, ?2, ?3, ?4, ?5)
         on conflict(item_id) do update set
           tmdb_id=excluded.tmdb_id,
           media_type=excluded.media_type,
           json=excluded.json,
           updated_at=excluded.updated_at",
        params![item_id, tmdb_id, media_type, metadata_json, updated_at],
    )?;
    Ok(())
}

pub fn get_all_metadata_json(db_path: &str) -> Result<String> {
    let conn = open(db_path)?;
    let mut stmt = conn.prepare("select item_id, json from metadata order by item_id")?;
    let rows = stmt.query_map([], |row| {
        Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?))
    })?;

    let mut map = Map::new();
    for row in rows {
        let (item_id, json) = row?;
        let value: Value = serde_json::from_str(&json)?;
        map.insert(item_id, value);
    }
    Ok(Value::Object(map).to_string())
}

pub fn replace_all_metadata_json(db_path: &str, metadata_map_json: &str) -> Result<()> {
    let value: Value = serde_json::from_str(metadata_map_json)?;
    let object = value.as_object().cloned().unwrap_or_default();
    let mut conn = open(db_path)?;
    let tx = conn.transaction()?;
    tx.execute("delete from metadata", [])?;
    {
        let mut stmt = tx.prepare(
            "insert into metadata(item_id, tmdb_id, media_type, json, updated_at)
             values (?1, ?2, ?3, ?4, ?5)",
        )?;
        for (item_id, value) in object {
            let tmdb_id = value.get("tmdbId").and_then(Value::as_i64);
            let media_type = value.get("mediaType").and_then(Value::as_str);
            let updated_at = value.get("updatedAt").and_then(Value::as_i64);
            stmt.execute(params![
                item_id,
                tmdb_id,
                media_type,
                value.to_string(),
                updated_at
            ])?;
        }
    }
    tx.commit()?;
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
         create index if not exists idx_metadata_tmdb on metadata(tmdb_id, media_type);",
    )?;
    Ok(conn)
}
