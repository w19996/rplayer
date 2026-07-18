use anyhow::{anyhow, Result};
use reqwest::Client;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::collections::HashMap;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Mutex, OnceLock};
use std::time::Duration;
use url::Url;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DanmuMatchRequest {
    pub title: String,
    pub season: Option<u16>,
    pub episode: Option<u16>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DanmuEvent {
    pub time_ms: u64,
    pub mode: DanmuMode,
    pub color: u32,
    pub text: String,
    pub source: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum DanmuMode {
    Scroll,
    Top,
    Bottom,
    Unknown,
}

#[derive(Clone)]
pub struct DanmuClient {
    http: Client,
    base_url: String,
    token: Option<String>,
}

impl DanmuClient {
    pub fn new(base_url: impl Into<String>, token: Option<String>) -> Self {
        Self {
            http: Client::new(),
            base_url: base_url.into().trim_end_matches('/').to_string(),
            token,
        }
    }

    pub async fn match_media(&self, request: &DanmuMatchRequest) -> Result<serde_json::Value> {
        let url = self.url("/api/v2/match");
        let response = self
            .http
            .post(url)
            .json(request)
            .send()
            .await?
            .error_for_status()?
            .json()
            .await?;
        Ok(response)
    }

    pub async fn get_comment_json(&self, comment_id: &str) -> Result<serde_json::Value> {
        let url = self.url(&format!("/api/v2/comment/{comment_id}"));
        let response = self
            .http
            .get(url)
            .query(&[("format", "json")])
            .send()
            .await?
            .error_for_status()?
            .json()
            .await?;
        Ok(response)
    }

    pub async fn get_comment_by_url(&self, video_url: &str) -> Result<serde_json::Value> {
        let url = self.url("/api/v2/comment");
        let response = self
            .http
            .get(url)
            .query(&[("url", video_url), ("format", "json")])
            .send()
            .await?
            .error_for_status()?
            .json()
            .await?;
        Ok(response)
    }

    fn url(&self, path: &str) -> String {
        match &self.token {
            Some(token) if !token.is_empty() => format!("{}/{token}{path}", self.base_url),
            _ => format!("{}{}", self.base_url, path),
        }
    }
}

#[derive(Debug, Deserialize)]
struct DanmuLoadInput {
    base_url: String,
    title: String,
    file_names: Vec<String>,
    season: Option<u16>,
    episode: Option<u16>,
    episode_id: Option<String>,
    episode_title: Option<String>,
    source: Option<String>,
    headers: Option<HashMap<String, String>>,
}

#[derive(Debug, Deserialize)]
struct DanmuVisibleInput {
    session_id: u64,
    position_ms: u64,
    width: f64,
    height: f64,
    font_size: f64,
    speed: f64,
    offset_ms: i64,
    max_items: Option<usize>,
    max_lines: Option<usize>,
    top_padding: Option<f64>,
}

#[derive(Debug, Serialize)]
struct DanmuLoadOutput {
    session_id: u64,
    count: usize,
    matched_episode_id: String,
    matched_title: String,
    matched_episode: String,
    logs: Vec<String>,
}

#[derive(Debug, Serialize)]
struct DanmuVisibleOutput {
    items: Vec<DanmuRenderItem>,
}

#[derive(Debug, Clone)]
struct DanmuSession {
    events: Vec<DanmuEvent>,
    layout: Option<DanmuLayout>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct DanmuLayoutKey {
    width_px: u32,
    font_px: u32,
    speed_percent: u32,
    lane_count: usize,
    fixed_lane_count: usize,
    top_padding_px: u32,
}

#[derive(Debug, Clone)]
struct DanmuLayout {
    key: DanmuLayoutKey,
    lanes: Vec<Option<u8>>,
}

#[derive(Debug, Serialize)]
struct DanmuRenderItem {
    id: usize,
    time_ms: u64,
    mode: u8,
    color: u32,
    text: String,
    left: f64,
    top: f64,
    text_width: f64,
    sample_ms: i64,
    start_ms: i64,
    end_ms: i64,
    velocity_x: f64,
}

static SESSIONS: OnceLock<Mutex<HashMap<u64, DanmuSession>>> = OnceLock::new();
static NEXT_SESSION_ID: AtomicU64 = AtomicU64::new(1);

pub fn load_danmu_session_json(input_json: &str) -> Result<String> {
    let input: DanmuLoadInput = serde_json::from_str(input_json)?;
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()?;
    let output = runtime.block_on(load_danmu_session(input))?;
    Ok(serde_json::to_string(&output)?)
}

pub fn visible_danmu_json(input_json: &str) -> Result<String> {
    let input: DanmuVisibleInput = serde_json::from_str(input_json)?;
    let mut sessions = SESSIONS
        .get_or_init(|| Mutex::new(HashMap::new()))
        .lock()
        .map_err(|_| anyhow!("danmu session lock poisoned"))?;
    let session = sessions
        .get_mut(&input.session_id)
        .ok_or_else(|| anyhow!("danmu session {} not found", input.session_id))?;
    let output = visible_danmu(session, &input);
    Ok(serde_json::to_string(&output)?)
}

pub fn clear_danmu_session_json(session_id_json: &str) -> Result<String> {
    let session_id: u64 = serde_json::from_str(session_id_json).or_else(|_| {
        session_id_json
            .trim()
            .parse::<u64>()
            .map_err(anyhow::Error::from)
    })?;
    let mut sessions = SESSIONS
        .get_or_init(|| Mutex::new(HashMap::new()))
        .lock()
        .map_err(|_| anyhow!("danmu session lock poisoned"))?;
    let removed = sessions.remove(&session_id).is_some();
    Ok(json!({ "removed": removed }).to_string())
}

async fn load_danmu_session(input: DanmuLoadInput) -> Result<DanmuLoadOutput> {
    let mut logs = Vec::new();
    let client = Client::builder()
        .timeout(Duration::from_secs(18))
        .user_agent("player_flutter/0.1")
        .build()?;
    let base_url = input.base_url.trim_end_matches('/').to_string();
    if let Some(source) = input
        .source
        .as_deref()
        .map(str::trim)
        .filter(|value| !value.is_empty())
    {
        return load_source_danmu(&client, source, input.headers.as_ref()).await;
    }
    logs.push(format!(
        "rust danmu load start: base={} title={} S{:?} E{:?} candidates={:?}",
        base_url, input.title, input.season, input.episode, input.file_names
    ));
    if let Some(episode_id) = input
        .episode_id
        .as_ref()
        .map(|value| value.trim())
        .filter(|value| !value.is_empty())
    {
        return load_danmu_episode(
            &client,
            &base_url,
            episode_id,
            input.title.trim(),
            input.episode_title.as_deref().unwrap_or("").trim(),
            logs,
        )
        .await;
    }

    for (index, file_name) in input.file_names.iter().enumerate() {
        let body = json!({
            "fileName": file_name,
        });
        let match_url = format!("{base_url}/api/v2/match");
        logs.push(format!(
            "rust danmu match request [{}/{}]: POST {} body={}",
            index + 1,
            input.file_names.len(),
            match_url,
            body
        ));
        let response = match client
            .post(&match_url)
            .header("accept", "application/json")
            .json(&body)
            .send()
            .await
        {
            Ok(response) => response,
            Err(error) => {
                logs.push(format!(
                    "rust danmu match request failed [{}/{}]: error={}",
                    index + 1,
                    input.file_names.len(),
                    error
                ));
                continue;
            }
        };
        let status = response.status();
        let text = match response.text().await {
            Ok(text) => text,
            Err(error) => {
                logs.push(format!(
                    "rust danmu match response decode failed [{}/{}]: status={} error={} body=<unavailable>",
                    index + 1,
                    input.file_names.len(),
                    status.as_u16(),
                    error
                ));
                continue;
            }
        };
        logs.push(format!(
            "rust danmu match response [{}/{}]: status={} body={}",
            index + 1,
            input.file_names.len(),
            status.as_u16(),
            short_body(&text)
        ));
        if !status.is_success() {
            logs.push(format!(
                "rust danmu match skipped [{}/{}]: status={}",
                index + 1,
                input.file_names.len(),
                status.as_u16()
            ));
            continue;
        }
        let json: Value = match serde_json::from_str(&text) {
            Ok(json) => json,
            Err(error) => {
                logs.push(format!(
                    "rust danmu match json parse failed [{}/{}]: error={} body={}",
                    index + 1,
                    input.file_names.len(),
                    error,
                    short_body(&text)
                ));
                continue;
            }
        };
        let matches = json
            .get("matches")
            .and_then(Value::as_array)
            .cloned()
            .unwrap_or_default();
        if matches.is_empty() {
            logs.push(format!(
                "rust danmu match empty [{}/{}]: fileName={}",
                index + 1,
                input.file_names.len(),
                file_name
            ));
            continue;
        }

        for matched in matches {
            let Some(episode_id) = matched.get("episodeId").map(value_to_string) else {
                continue;
            };
            let anime_title = matched
                .get("animeTitle")
                .and_then(Value::as_str)
                .unwrap_or("")
                .to_string();
            let episode_title = matched
                .get("episodeTitle")
                .and_then(Value::as_str)
                .unwrap_or("")
                .to_string();
            let comment_url = format!("{base_url}/api/v2/comment/{episode_id}");
            logs.push(format!(
                "rust danmu comment request: {}?format=json&duration=true match={}/{}",
                comment_url, anime_title, episode_title
            ));
            let response = match client
                .get(&comment_url)
                .header("accept", "application/json")
                .query(&[("format", "json"), ("duration", "true")])
                .send()
                .await
            {
                Ok(response) => response,
                Err(error) => {
                    logs.push(format!(
                        "rust danmu comment request failed: episodeId={} error={}",
                        episode_id, error
                    ));
                    continue;
                }
            };
            let status = response.status();
            let text = match response.text().await {
                Ok(text) => text,
                Err(error) => {
                    logs.push(format!(
                        "rust danmu comment response decode failed: episodeId={} status={} error={} body=<unavailable>",
                        episode_id,
                        status.as_u16(),
                        error
                    ));
                    continue;
                }
            };
            logs.push(format!(
                "rust danmu comment response: episodeId={} status={} body={}",
                episode_id,
                status.as_u16(),
                short_body(&text)
            ));
            if !status.is_success() {
                logs.push(format!(
                    "rust danmu comment skipped: episodeId={} status={} empty={}",
                    episode_id,
                    status.as_u16(),
                    empty_comment_response(&text)
                ));
                continue;
            }
            let events = match parse_comment_events(&text) {
                Ok(events) => events,
                Err(error) => {
                    logs.push(format!(
                        "rust danmu comment json parse failed: episodeId={} error={} body={}",
                        episode_id,
                        error,
                        short_body(&text)
                    ));
                    continue;
                }
            };
            if events.is_empty() {
                logs.push(format!(
                    "rust danmu comment empty after parse: episodeId={}",
                    episode_id
                ));
                continue;
            }
            let session_id = NEXT_SESSION_ID.fetch_add(1, Ordering::Relaxed);
            let count = events.len();
            let session = DanmuSession {
                events,
                layout: None,
            };
            SESSIONS
                .get_or_init(|| Mutex::new(HashMap::new()))
                .lock()
                .map_err(|_| anyhow!("danmu session lock poisoned"))?
                .insert(session_id, session);
            logs.push(format!(
                "rust danmu session loaded: session={} count={} episodeId={}",
                session_id, count, episode_id
            ));
            return Ok(DanmuLoadOutput {
                session_id,
                count,
                matched_episode_id: episode_id,
                matched_title: anime_title,
                matched_episode: episode_title,
                logs,
            });
        }
    }
    logs.push("rust danmu load finished without usable comments".to_string());

    Ok(DanmuLoadOutput {
        session_id: 0,
        count: 0,
        matched_episode_id: String::new(),
        matched_title: String::new(),
        matched_episode: String::new(),
        logs,
    })
}

async fn load_source_danmu(
    client: &Client,
    source: &str,
    headers: Option<&HashMap<String, String>>,
) -> Result<DanmuLoadOutput> {
    let mut logs = Vec::new();
    let body = if source.starts_with("http://") || source.starts_with("https://") {
        logs.push(format!("rust tvbox danmu request: {}", source));
        let mut request = client.get(source);
        if let Some(headers) = headers {
            for (name, value) in headers {
                request = request.header(name, value);
            }
        }
        let response = request.send().await?;
        let status = response.status();
        let body = response.text().await?;
        logs.push(format!(
            "rust tvbox danmu response: status={} body={}",
            status.as_u16(),
            short_body(&body)
        ));
        if !status.is_success() {
            return Err(anyhow!("TVBox danmu HTTP {}", status.as_u16()));
        }
        body
    } else if source.starts_with("file:") {
        let path = Url::parse(source)
            .map_err(anyhow::Error::from)?
            .to_file_path()
            .map_err(|_| anyhow!("invalid TVBox danmu file URI"))?;
        logs.push(format!("rust tvbox danmu file: {}", path.display()));
        std::fs::read_to_string(path)?
    } else {
        logs.push(format!(
            "rust tvbox danmu inline xml: length={}",
            source.len()
        ));
        source.to_string()
    };
    let events = parse_bilibili_xml_events(&body)?;
    let count = events.len();
    if count == 0 {
        logs.push("rust tvbox danmu empty after parse".to_string());
        return Ok(DanmuLoadOutput {
            session_id: 0,
            count: 0,
            matched_episode_id: String::new(),
            matched_title: String::new(),
            matched_episode: String::new(),
            logs,
        });
    }
    let session_id = NEXT_SESSION_ID.fetch_add(1, Ordering::Relaxed);
    SESSIONS
        .get_or_init(|| Mutex::new(HashMap::new()))
        .lock()
        .map_err(|_| anyhow!("danmu session lock poisoned"))?
        .insert(
            session_id,
            DanmuSession {
                events,
                layout: None,
            },
        );
    logs.push(format!(
        "rust tvbox danmu session loaded: session={} count={}",
        session_id, count
    ));
    Ok(DanmuLoadOutput {
        session_id,
        count,
        matched_episode_id: String::new(),
        matched_title: String::new(),
        matched_episode: String::new(),
        logs,
    })
}

async fn load_danmu_episode(
    client: &Client,
    base_url: &str,
    episode_id: &str,
    anime_title: &str,
    episode_title: &str,
    mut logs: Vec<String>,
) -> Result<DanmuLoadOutput> {
    let episode_id_is_url = episode_id.starts_with("http://") || episode_id.starts_with("https://");
    let comment_url = if episode_id_is_url {
        format!("{base_url}/api/v2/comment")
    } else {
        format!("{base_url}/api/v2/comment/{episode_id}")
    };
    logs.push(format!(
        "rust danmu manual comment request: {}?format=json&duration=true match={}/{}",
        comment_url, anime_title, episode_title
    ));
    let mut request = client
        .get(&comment_url)
        .header("accept", "application/json");
    request = if episode_id_is_url {
        request.query(&[
            ("url", episode_id),
            ("format", "json"),
            ("duration", "true"),
        ])
    } else {
        request.query(&[("format", "json"), ("duration", "true")])
    };
    let response = request.send().await?;
    let status = response.status();
    let text = response.text().await?;
    logs.push(format!(
        "rust danmu manual comment response: episodeId={} status={} body={}",
        episode_id,
        status.as_u16(),
        short_body(&text)
    ));
    if !status.is_success() || empty_comment_response(&text) {
        logs.push(format!(
            "rust danmu manual comment skipped: episodeId={} status={} empty={}",
            episode_id,
            status.as_u16(),
            empty_comment_response(&text)
        ));
        return Ok(DanmuLoadOutput {
            session_id: 0,
            count: 0,
            matched_episode_id: episode_id.to_string(),
            matched_title: anime_title.to_string(),
            matched_episode: episode_title.to_string(),
            logs,
        });
    }
    let events = parse_comment_events(&text)?;
    if events.is_empty() {
        logs.push(format!(
            "rust danmu manual comment empty after parse: episodeId={}",
            episode_id
        ));
        return Ok(DanmuLoadOutput {
            session_id: 0,
            count: 0,
            matched_episode_id: episode_id.to_string(),
            matched_title: anime_title.to_string(),
            matched_episode: episode_title.to_string(),
            logs,
        });
    }
    let count = events.len();
    let session_id = NEXT_SESSION_ID.fetch_add(1, Ordering::Relaxed);
    let session = DanmuSession {
        events,
        layout: None,
    };
    SESSIONS
        .get_or_init(|| Mutex::new(HashMap::new()))
        .lock()
        .map_err(|_| anyhow!("danmu session lock poisoned"))?
        .insert(session_id, session);
    logs.push(format!(
        "rust danmu manual session loaded: session={} count={} episodeId={}",
        session_id, count, episode_id
    ));
    Ok(DanmuLoadOutput {
        session_id,
        count,
        matched_episode_id: episode_id.to_string(),
        matched_title: anime_title.to_string(),
        matched_episode: episode_title.to_string(),
        logs,
    })
}

fn visible_danmu(session: &mut DanmuSession, input: &DanmuVisibleInput) -> DanmuVisibleOutput {
    let width = input.width.max(1.0);
    let height = input.height.max(1.0);
    let font_size = input.font_size.clamp(10.0, 32.0);
    let lane_height = font_size + 8.0;
    let top_padding = input
        .top_padding
        .unwrap_or(24.0)
        .clamp(-(height * 0.20), height * 0.55);
    let lane_count = input.max_lines.unwrap_or(8).clamp(1, 14);
    let fixed_lane_count = ((height * 0.20) / lane_height).floor().clamp(1.0, 3.0) as usize;
    let speed = input.speed.clamp(0.5, 2.0);
    let travel_ms = (9500.0 / speed).round() as i64;
    let fixed_ms = 3800_i64;
    let now = input.position_ms as i64 + input.offset_ms;
    let max_items = input.max_items.unwrap_or(56).clamp(8, 120);
    let lookahead_ms = 3200_i64;
    let layout_key = DanmuLayoutKey {
        width_px: width.round().max(1.0) as u32,
        font_px: font_size.round().max(1.0) as u32,
        speed_percent: (speed * 100.0).round().max(1.0) as u32,
        lane_count,
        fixed_lane_count,
        top_padding_px: (top_padding.round() + 10_000.0).max(0.0) as u32,
    };
    ensure_danmu_layout(session, layout_key, width, font_size, travel_ms, fixed_ms);
    let layout = session.layout.as_ref().expect("danmu layout initialized");

    let mut items = Vec::with_capacity(max_items);

    let lookback_ms = travel_ms + 500;
    let start_time = (now - lookback_ms).max(0) as u64;
    let start_index = session
        .events
        .partition_point(|event| event.time_ms < start_time);

    for (absolute_index, event) in session.events.iter().enumerate().skip(start_index) {
        if items.len() >= max_items {
            break;
        }
        let event_time = event.time_ms as i64;
        if event_time - now > lookahead_ms {
            break;
        }
        let elapsed = now - event_time;
        let Some(lane) = layout.lanes.get(absolute_index).and_then(|value| *value) else {
            continue;
        };
        let lane = lane as usize;

        let text_width = estimate_text_width(&event.text, font_size).min(width * 0.92);
        match event.mode {
            DanmuMode::Top if elapsed <= fixed_ms => {
                let top = top_padding + lane as f64 * lane_height;
                items.push(render_item(
                    absolute_index,
                    event,
                    (width - text_width) / 2.0,
                    top,
                    text_width,
                    now,
                    event_time,
                    event_time + fixed_ms,
                    0.0,
                ));
            }
            DanmuMode::Bottom if elapsed <= fixed_ms => {
                let top = (height - 120.0 - (lane + 1) as f64 * lane_height).max(48.0);
                items.push(render_item(
                    absolute_index,
                    event,
                    (width - text_width) / 2.0,
                    top,
                    text_width,
                    now,
                    event_time,
                    event_time + fixed_ms,
                    0.0,
                ));
            }
            _ if elapsed <= travel_ms => {
                let progress = elapsed as f64 / travel_ms as f64;
                let left = width - progress * (width + text_width);
                let top = top_padding + lane as f64 * lane_height;
                items.push(render_item(
                    absolute_index,
                    event,
                    left,
                    top,
                    text_width,
                    now,
                    event_time,
                    event_time + travel_ms,
                    -(width + text_width) / travel_ms as f64,
                ));
            }
            _ => {}
        }
    }

    DanmuVisibleOutput { items }
}

fn parse_comment_events(body: &str) -> Result<Vec<DanmuEvent>> {
    let json: Value = serde_json::from_str(body)?;
    let comments = json
        .get("comments")
        .and_then(Value::as_array)
        .ok_or_else(|| anyhow!("danmu comments missing or not an array"))?;
    let mut events = Vec::with_capacity(comments.len());
    for comment in comments {
        let p = comment.get("p").and_then(Value::as_str).unwrap_or("");
        let mut parts = p.split(',');
        let seconds = parts
            .next()
            .and_then(|value| value.parse::<f64>().ok())
            .or_else(|| number_value(comment.get("timepoint")))
            .or_else(|| number_value(comment.get("time")))
            .or_else(|| number_value(comment.get("t")))
            .unwrap_or(0.0);
        let mode_value = parts
            .next()
            .and_then(|value| value.parse::<u8>().ok())
            .or_else(|| int_value(comment.get("ct")).map(|value| value as u8))
            .or_else(|| int_value(comment.get("mode")).map(|value| value as u8))
            .or_else(|| int_value(comment.get("type")).map(|value| value as u8))
            .unwrap_or(1);
        let color = parts
            .next()
            .and_then(|value| value.parse::<u32>().ok())
            .or_else(|| int_value(comment.get("color")).map(|value| value as u32))
            .unwrap_or(0x00ff_ffff);
        let text = comment
            .get("m")
            .or_else(|| comment.get("text"))
            .or_else(|| comment.get("content"))
            .and_then(Value::as_str)
            .unwrap_or("")
            .trim()
            .to_string();
        if text.is_empty() {
            continue;
        }
        events.push(DanmuEvent {
            time_ms: (seconds * 1000.0).round().max(0.0) as u64,
            mode: match mode_value {
                4 => DanmuMode::Bottom,
                5 => DanmuMode::Top,
                1 | 6 => DanmuMode::Scroll,
                _ => DanmuMode::Scroll,
            },
            color,
            text,
            source: None,
        });
    }
    events.sort_by_key(|event| event.time_ms);
    Ok(events)
}

fn parse_bilibili_xml_events(body: &str) -> Result<Vec<DanmuEvent>> {
    let document = roxmltree::Document::parse(body)?;
    let mut events = Vec::new();
    for node in document.descendants().filter(|node| node.has_tag_name("d")) {
        let Some(param) = node.attribute("p") else {
            continue;
        };
        let parts = param.split(',').collect::<Vec<_>>();
        if parts.len() < 4 {
            continue;
        }
        let seconds = parts[0].trim().parse::<f64>().unwrap_or(0.0);
        let mode_value = parts[1].trim().parse::<u8>().unwrap_or(1);
        let color = parts[3].trim().parse::<u32>().unwrap_or(0x00ff_ffff);
        let text = node.text().unwrap_or("").trim().to_string();
        if text.is_empty() {
            continue;
        }
        events.push(DanmuEvent {
            time_ms: (seconds * 1000.0).round().max(0.0) as u64,
            mode: match mode_value {
                4 => DanmuMode::Bottom,
                5 => DanmuMode::Top,
                1 | 6 => DanmuMode::Scroll,
                _ => DanmuMode::Scroll,
            },
            color,
            text,
            source: Some("tvbox".to_string()),
        });
    }
    events.sort_by_key(|event| event.time_ms);
    Ok(events)
}

fn render_item(
    id: usize,
    event: &DanmuEvent,
    left: f64,
    top: f64,
    text_width: f64,
    sample_ms: i64,
    start_ms: i64,
    end_ms: i64,
    velocity_x: f64,
) -> DanmuRenderItem {
    DanmuRenderItem {
        id,
        time_ms: event.time_ms,
        mode: match event.mode {
            DanmuMode::Scroll => 1,
            DanmuMode::Bottom => 4,
            DanmuMode::Top => 5,
            DanmuMode::Unknown => 0,
        },
        color: event.color,
        text: event.text.clone(),
        left,
        top,
        text_width,
        sample_ms,
        start_ms,
        end_ms,
        velocity_x,
    }
}

fn ensure_danmu_layout(
    session: &mut DanmuSession,
    key: DanmuLayoutKey,
    width: f64,
    font_size: f64,
    travel_ms: i64,
    fixed_ms: i64,
) {
    if session
        .layout
        .as_ref()
        .map(|layout| layout.key == key)
        .unwrap_or(false)
    {
        return;
    }

    let mut lanes = vec![None; session.events.len()];
    let mut scroll_available = vec![0_i64; key.lane_count.max(1)];
    let mut top_available = vec![0_i64; key.fixed_lane_count.max(1)];
    let mut bottom_available = vec![0_i64; key.fixed_lane_count.max(1)];

    for (index, event) in session.events.iter().enumerate() {
        let event_time = event.time_ms as i64;
        match event.mode {
            DanmuMode::Top => {
                if let Some(lane) = assign_lane(&mut top_available, event_time, fixed_ms, 300) {
                    lanes[index] = Some(lane as u8);
                }
            }
            DanmuMode::Bottom => {
                if let Some(lane) = assign_lane(&mut bottom_available, event_time, fixed_ms, 300) {
                    lanes[index] = Some(lane as u8);
                }
            }
            _ => {
                let text_width = estimate_text_width(&event.text, font_size).min(width * 0.92);
                let gap_ms = (((text_width + 48.0) / (width + text_width)) * travel_ms as f64)
                    .ceil()
                    .max(850.0) as i64;
                if let Some(lane) = assign_lane(&mut scroll_available, event_time, gap_ms, 450) {
                    lanes[index] = Some(lane as u8);
                }
            }
        }
    }

    session.layout = Some(DanmuLayout { key, lanes });
}

fn assign_lane(
    available_at: &mut [i64],
    event_time: i64,
    occupy_ms: i64,
    tolerance_ms: i64,
) -> Option<usize> {
    if let Some((lane, _)) = available_at
        .iter()
        .enumerate()
        .find(|(_, available)| **available <= event_time)
    {
        available_at[lane] = event_time + occupy_ms.max(1);
        return Some(lane);
    }

    let (lane, earliest) = available_at
        .iter()
        .enumerate()
        .min_by_key(|(_, available)| **available)?;
    if *earliest - event_time <= tolerance_ms {
        available_at[lane] = event_time + occupy_ms.max(1);
        Some(lane)
    } else {
        None
    }
}

fn estimate_text_width(text: &str, font_size: f64) -> f64 {
    let units = text
        .chars()
        .map(|ch| if ch.is_ascii() { 0.62 } else { 1.0 })
        .sum::<f64>();
    (units * font_size * 1.02).max(font_size)
}

fn value_to_string(value: &Value) -> String {
    match value {
        Value::String(value) => value.clone(),
        Value::Number(value) => value.to_string(),
        _ => String::new(),
    }
}

fn number_value(value: Option<&Value>) -> Option<f64> {
    match value? {
        Value::Number(value) => value.as_f64(),
        Value::String(value) => value.trim().parse::<f64>().ok(),
        _ => None,
    }
}

fn int_value(value: Option<&Value>) -> Option<u64> {
    match value? {
        Value::Number(value) => value.as_u64(),
        Value::String(value) => value.trim().parse::<u64>().ok(),
        _ => None,
    }
}

fn empty_comment_response(body: &str) -> bool {
    let Ok(value) = serde_json::from_str::<Value>(body) else {
        return false;
    };
    let count_empty = value
        .get("count")
        .map(|count| count == 0 || count == "0")
        .unwrap_or(false);
    let comments_empty = value
        .get("comments")
        .map(|comments| {
            comments == 0
                || comments == "0"
                || comments
                    .as_array()
                    .map(|items| items.is_empty())
                    .unwrap_or(false)
        })
        .unwrap_or(false);
    count_empty && comments_empty
}

fn short_body(body: &str) -> String {
    let compact = body.split_whitespace().collect::<Vec<_>>().join(" ");
    if compact.chars().count() <= 800 {
        compact
    } else {
        compact.chars().take(800).collect::<String>() + "..."
    }
}

#[cfg(test)]
mod tests {
    use super::{
        parse_bilibili_xml_events, visible_danmu, DanmuEvent, DanmuMode, DanmuSession,
        DanmuVisibleInput,
    };

    #[test]
    fn parses_tvbox_bilibili_xml_danmu() {
        let events = parse_bilibili_xml_events(
            r#"<?xml version="1.0"?><i><d p="2.5,1,25,16711680,0,0,0,0">滚动 &amp; 测试</d><d p="1,5,25,255,0,0,0,0">顶部</d></i>"#,
        )
        .unwrap();

        assert_eq!(events.len(), 2);
        assert_eq!(events[0].time_ms, 1000);
        assert!(matches!(events[0].mode, DanmuMode::Top));
        assert_eq!(events[0].color, 255);
        assert_eq!(events[1].text, "滚动 & 测试");
        assert_eq!(events[1].color, 16_711_680);
        assert_eq!(events[1].source.as_deref(), Some("tvbox"));
    }

    #[test]
    fn rust_builds_the_complete_scroll_trajectory() {
        let mut session = DanmuSession {
            events: vec![DanmuEvent {
                time_ms: 1_000,
                mode: DanmuMode::Scroll,
                color: 0xFFFFFF,
                text: "trajectory".to_string(),
                source: None,
            }],
            layout: None,
        };
        let frame = visible_danmu(
            &mut session,
            &DanmuVisibleInput {
                session_id: 1,
                position_ms: 2_000,
                width: 1_000.0,
                height: 600.0,
                font_size: 24.0,
                speed: 1.0,
                offset_ms: 0,
                max_items: None,
                max_lines: Some(3),
                top_padding: Some(0.0),
            },
        );

        let item = &frame.items[0];
        assert_eq!(item.sample_ms, 2_000);
        assert_eq!(item.start_ms, 1_000);
        assert_eq!(item.end_ms, 10_500);
        assert!(item.velocity_x < 0.0);
        assert!(
            (item.left + item.velocity_x * 500.0 - (1_000.0 + item.velocity_x * 1_500.0)).abs()
                < 0.001
        );
    }
}
