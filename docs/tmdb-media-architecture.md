# TMDB 媒体库数据库与 API 调用链重设计

## 核心原则

本地文件和 WebDAV 文件只作为播放资源。文件夹名、文件名只用于解析搜索提示和集数提示，不能作为页面展示的正式元数据。电视剧名、海报、背景图、演员、简介、评分、集名、播出日期等展示信息都必须来自 TMDB，并按 TMDB 实体去重存储。

## 分层模型

### 资源层

保存来源、选中的目录、文件事实和播放 URL 构造所需字段。

- `sources`: 资源源。保存 `id/name/type/base_url/root_path/credential_id`。WebDAV 密码不要明文存 SQLite，SQLite 只存 `credential_id`，真实密钥放 Android Keystore 或加密存储。
- `source_folders`: 每个被用户选中的目录一行。删除目录时级联删除该目录下文件、匹配、播放进度和目录偏好。
- `media_files`: 每个视频文件一行。保存 `source_id/folder_id/relative_path/filename/ext/size/modified_at/guess_title/guess_season/guess_episode/quality/scan_status`。

资源层不存 TMDB 正式标题，不存剧集简介，不存演员，不存海报。

### 状态层

保存用户和播放状态。

- `playback_progress`: 以 `file_id` 为主键，保存 `position_ms/duration_ms/last_played_at/completed/updated_at`。最近播放列表只从 `last_played_at desc` 查询。
- `folder_preferences`: 以 `folder_id` 为主键，保存横竖屏偏好、排序方式、视图方式。
- `image_cache`: 保存已下载图片的缓存，按 `(provider,file_path,size)` 去重，允许存 bytes 或本地 cache path。

### 匹配层

保存“文件/文件夹如何匹配到 TMDB”的过程和结果。

- `match_tasks`: 文件夹级匹配任务，保存 `search_query/detected_seasons/detected_episodes/file_count/status/selected_show_id`。
- `match_candidates`: `/search/tv` 候选结果和评分，方便后续人工确认。
- `source_folder_matches`: 文件夹到 TMDB show 的绑定。新增集数时优先复用这个绑定，不能重新搜索整部剧。
- `media_file_matches`: 文件到 TMDB show/season/episode 的绑定。一个 TMDB episode 可以对应多个不同清晰度或不同来源的视频文件。

### TMDB 元数据层

TMDB 信息按实体存储，不再按本地文件复制。

- `tmdb_tv_shows`: 每部剧一行，按 `tmdb_id` 唯一。
- `tmdb_tv_seasons`: 每季一行，按 `(show_id, season_number)` 唯一。特殊篇保留 `season_number = 0`。
- `tmdb_tv_episodes`: 每集一行，按 `(show_id, season_number, episode_number)` 唯一。
- `tmdb_people_cache` / `tmdb_credits`: 演员和导演信息。
- `tmdb_images`: TMDB 图片元数据，保存 owner、类型和 `file_path`。
- `tmdb_translations` / `tmdb_external_ids`: 翻译和外部 ID。
- `api_cache`: 保存 TMDB 请求响应，避免重复请求并方便调试。
- `metadata_sync_state`: 保存同步状态、失败原因和重试时间。

## 建议 SQLite Schema

核心表如下，完整实现时应放入 Rust core 的迁移函数中，并开启 `PRAGMA foreign_keys = ON`。

```sql
create table if not exists sources(
  id text primary key,
  name text not null,
  type text not null,
  base_url text,
  root_path text default '/',
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

create table if not exists tmdb_tv_shows(
  id integer primary key autoincrement,
  tmdb_id integer not null unique,
  name text not null,
  original_name text,
  overview text,
  first_air_date text,
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
```

索引至少需要：

```sql
create index if not exists idx_playback_recent on playback_progress(last_played_at desc);
create index if not exists idx_media_files_source_path on media_files(source_id, relative_path);
create index if not exists idx_media_files_folder on media_files(folder_id);
create index if not exists idx_tmdb_episodes_lookup on tmdb_tv_episodes(show_id, season_number, episode_number);
create index if not exists idx_file_matches_episode on media_file_matches(episode_id);
```

## TMDB API 调用链

### 首次添加一个电视剧目录

1. 扫描 source，不调用 TMDB。
2. 写入 `sources/source_folders/media_files`，解析 `guess_title/guess_season/guess_episode/quality/size`。
3. 创建 `match_tasks`，搜索词优先取文件夹名。
4. 调用 `GET /3/search/tv?query={search_query}&language={language}`。
5. 保存 `match_candidates` 和评分。
6. 高置信度自动匹配，低置信度需要用户确认。
7. 选定 TMDB show 后调用 `GET /3/tv/{series_id}?language={language}&append_to_response=external_ids,images,translations,content_ratings`。
8. 写入 `tmdb_tv_shows/tmdb_images/tmdb_credits/tmdb_translations/source_folder_matches`。
9. 只对本地文件中出现的季调用 `GET /3/tv/{series_id}/season/{season_number}?language={language}&append_to_response=images,external_ids`。
10. 写入 `tmdb_tv_seasons/tmdb_tv_episodes`。
11. 用 `guess_season + guess_episode` 写入 `media_file_matches`。

### 同一目录后续新增集数

1. 扫描新增文件，写入 `media_files`。
2. 读取 `source_folder_matches` 获取 `show_id/tmdb_id`。
3. 如果 `tmdb_tv_episodes` 已有 `(show_id, season, episode)`，直接写 `media_file_matches`，不调用 TMDB。
4. 如果 episode 缺失，只调用对应季：`GET /3/tv/{series_id}/season/{season_number}`。
5. 如果刷新后仍无该集，标记 `media_file_matches.match_status = 'unmatched'`，不拿本地文件名冒充集名。

### 删除或取消选择

删除不调用 TMDB。

- 删除单集文件：删除 `media_files`，级联删除 `media_file_matches/playback_progress`。
- 删除目录：删除 `source_folders`，级联删除文件、匹配、进度、目录偏好、匹配任务。
- 删除源：删除 `sources`，级联删除所有目录和文件，同时删除安全存储里的 credential。
- 删除后跑孤儿清理：只有当 `tmdb_tv_shows/seasons/episodes/images` 没有任何文件或目录引用时才清理。

## 页面查询规则

### 媒体库首页

按 `source_folder_matches -> tmdb_tv_shows` 聚合显示电视剧。

```sql
select
  s.id as show_id,
  s.name,
  s.poster_path,
  s.backdrop_path,
  s.vote_average,
  s.number_of_episodes,
  count(distinct mf.id) as local_episode_files,
  max(pp.last_played_at) as latest_played_at
from source_folder_matches sfm
join tmdb_tv_shows s on s.id = sfm.show_id
join media_files mf on mf.folder_id = sfm.folder_id and mf.scan_status = 'active'
left join playback_progress pp on pp.file_id = mf.id
group by s.id, sfm.folder_id
order by latest_played_at desc nulls last, s.name;
```

### 电视剧详情页

详情页所有展示字段来自 TMDB 表，文件信息只用于播放按钮、路径、大小和可播放列表。

```sql
select
  s.name,
  s.overview,
  s.poster_path,
  s.backdrop_path,
  s.vote_average,
  s.first_air_date,
  s.number_of_episodes,
  e.season_number,
  e.episode_number,
  e.name as episode_name,
  e.still_path,
  mf.id as file_id,
  mf.relative_path,
  mf.size,
  pp.position_ms,
  pp.duration_ms,
  pp.last_played_at
from source_folder_matches sfm
join tmdb_tv_shows s on s.id = sfm.show_id
join media_files mf on mf.folder_id = sfm.folder_id and mf.scan_status = 'active'
left join media_file_matches mfm on mfm.file_id = mf.id
left join tmdb_tv_episodes e on e.id = mfm.episode_id
left join playback_progress pp on pp.file_id = mf.id
where sfm.folder_id = ?;
```

当前播放按钮取：

```sql
order by pp.last_played_at desc nulls last, e.season_number, e.episode_number
limit 1;
```

### 最近播放

```sql
select *
from playback_progress pp
join media_files mf on mf.id = pp.file_id
left join media_file_matches mfm on mfm.file_id = mf.id
left join tmdb_tv_episodes e on e.id = mfm.episode_id
left join tmdb_tv_shows s on s.id = mfm.show_id
where pp.last_played_at is not null
order by pp.last_played_at desc;
```

## 全新库规则

当前实现按全新 App 数据库处理，不再兼容或导入旧缓存：

1. 不创建、读取或迁移 `metadata`、`metadata_titles`、`metadata_episodes`、`metadata_images`。
2. 不从 `app_state.media_state` 自动导入旧媒体状态；启动时只读取当前 `player_config.json` 和结构化 SQLite 表。
3. `media_files` 使用当前业务标识 `item_id`，不再保留 legacy 映射字段。
4. TMDB 数据只通过当前在线匹配流程写入 `tmdb_tv_shows`、`tmdb_tv_seasons`、`tmdb_tv_episodes`、`tmdb_images` 和匹配表。
5. 图片缓存只使用 `image_cache`；旧 `metadata_images` 不再作为回退来源。
6. 如果已有旧库或旧配置，需要用户主动重新扫描和重新匹配，系统不做自动迁移。

## 实现边界

Rust core 应成为 SQLite 唯一写入层，Flutter 不再把媒体状态整体 JSON 写进 `app_state` 当主存储。建议新增这些 Rust API：

- `player_core_library_upsert_source_json`
- `player_core_library_upsert_folder_json`
- `player_core_library_replace_folder_files_json`
- `player_core_library_delete_source_json`
- `player_core_library_delete_folder_json`
- `player_core_library_delete_file_json`
- `player_core_playback_progress_put_json`
- `player_core_tmdb_upsert_show_json`
- `player_core_tmdb_upsert_season_json`
- `player_core_tmdb_bind_file_episode_json`
- `player_core_library_query_home_json`
- `player_core_library_query_show_detail_json`
- `player_core_library_query_recent_json`

Flutter 的 `AppStore` 只保留内存投影，不再作为数据模型真相来源。页面读取应从 Rust query API 返回的 view model 构建。

## 验收标准

- 断网后媒体库首页和详情页仍能显示已缓存的 TMDB 海报、背景图、演员、简介、集名。
- 同一集有本地和 WebDAV 两个文件时，TMDB episode 只存一份，`media_file_matches` 有两条文件绑定。
- 同一目录新增第 3 集时，如果 show 已匹配，只请求对应 season，不请求 `/search/tv` 和 `/tv/{id}`。
- 删除单集时只删除该文件、该文件匹配和该文件播放进度，不删除整部剧 TMDB 信息。
- 删除整部剧目录时删除该目录下所有文件、匹配、进度和目录偏好；没有其它引用时才清理孤儿 TMDB 信息。
- 最近播放完全由 `playback_progress.last_played_at` 生成。
- 详情页标题、简介、海报、背景、演员、集名均来自 TMDB 表；路径、大小、播放 URL 来自资源层。
