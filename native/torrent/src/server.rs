//! Loopback-only HTTP range server: `GET|HEAD /{token}/stream/{id}/{file_idx}` and `/{token}/health`.

use std::io::SeekFrom;
use std::sync::Arc;
use std::time::Duration;

use axum::{
    Router,
    body::Body,
    extract::{Request, State},
    http::{HeaderMap, HeaderValue, Method, StatusCode, header},
    response::Response,
};
use librqbit::{Session, api::TorrentIdOrHash};
use tokio::io::{AsyncReadExt, AsyncSeekExt};
use tokio_util::io::ReaderStream;

/// Extensions that may be served. Anything else gets 415.
pub const MEDIA_EXTENSIONS: &[&str] = &[
    "mp4", "m4v", "mkv", "webm", "avi", "mov", "ts", "m2ts", "mts", "mpg", "mpeg", "flv", "wmv",
    "ogv", "3gp", "mp3", "m4a", "aac", "flac", "ogg", "oga", "opus", "wav", "wma", "srt", "vtt",
    "ass", "ssa", "sub",
];

pub struct Shared {
    pub token: String,
    pub port: u16,
    pub session: Arc<Session>,
}

pub fn router(shared: Arc<Shared>) -> Router {
    Router::new().fallback(handle).with_state(shared)
}

fn status(code: StatusCode) -> Response {
    let mut r = Response::new(Body::empty());
    *r.status_mut() = code;
    r.headers_mut()
        .insert(header::CACHE_CONTROL, HeaderValue::from_static("no-store"));
    r
}

/// True when `host` (a Host header value) is a loopback literal or `localhost` on our port.
pub fn host_ok(host: &str, port: u16) -> bool {
    let (name, p) = if let Some(rest) = host.strip_prefix('[') {
        let Some((name, tail)) = rest.split_once(']') else {
            return false;
        };
        (format!("[{name}]"), tail.strip_prefix(':'))
    } else {
        match host.rsplit_once(':') {
            Some((n, p)) => (n.to_string(), Some(p)),
            None => (host.to_string(), None),
        }
    };
    let name = name.to_ascii_lowercase();
    if !matches!(name.as_str(), "127.0.0.1" | "localhost" | "[::1]") {
        return false;
    }
    matches!(p.and_then(|p| p.parse::<u16>().ok()), Some(p) if p == port)
}

pub fn token_eq(a: &str, b: &str) -> bool {
    if a.len() != b.len() {
        return false;
    }
    a.bytes().zip(b.bytes()).fold(0u8, |acc, (x, y)| acc | (x ^ y)) == 0
}

pub fn is_media(name: &str) -> bool {
    match name.rsplit_once('.') {
        Some((_, ext)) => {
            let ext = ext.to_ascii_lowercase();
            MEDIA_EXTENSIONS.contains(&ext.as_str())
        }
        None => false,
    }
}

pub fn mime_for(name: &str) -> &'static str {
    let ext = name.rsplit_once('.').map(|(_, e)| e.to_ascii_lowercase()).unwrap_or_default();
    match ext.as_str() {
        "mp4" | "m4v" => "video/mp4",
        "mkv" => "video/x-matroska",
        "webm" => "video/webm",
        "avi" => "video/x-msvideo",
        "mov" => "video/quicktime",
        "ts" | "m2ts" | "mts" => "video/mp2t",
        "mpg" | "mpeg" => "video/mpeg",
        "flv" => "video/x-flv",
        "wmv" => "video/x-ms-wmv",
        "ogv" => "video/ogg",
        "3gp" => "video/3gpp",
        "mp3" => "audio/mpeg",
        "m4a" | "aac" => "audio/mp4",
        "flac" => "audio/flac",
        "ogg" | "oga" | "opus" => "audio/ogg",
        "wav" => "audio/wav",
        "wma" => "audio/x-ms-wma",
        "srt" => "application/x-subrip",
        "vtt" => "text/vtt",
        _ => "application/octet-stream",
    }
}

/// Outcome of parsing a `Range` header against a file of `len` bytes.
#[derive(Debug, PartialEq, Eq)]
pub enum RangeSpec {
    /// No Range header: the whole file.
    Full,
    /// Inclusive byte range.
    Partial(u64, u64),
    Unsatisfiable,
}

pub fn parse_range(h: Option<&str>, len: u64) -> RangeSpec {
    let Some(h) = h else { return RangeSpec::Full };
    let Some(spec) = h.trim().strip_prefix("bytes=") else {
        return RangeSpec::Full; // unknown unit: ignore, per RFC 9110
    };
    if spec.contains(',') {
        return RangeSpec::Unsatisfiable; // multi-range is not supported
    }
    let Some((a, b)) = spec.split_once('-') else {
        return RangeSpec::Unsatisfiable;
    };
    if len == 0 {
        return RangeSpec::Unsatisfiable;
    }
    let (a, b) = (a.trim(), b.trim());
    if a.is_empty() {
        // suffix: last N bytes
        let Ok(n) = b.parse::<u64>() else { return RangeSpec::Unsatisfiable };
        if n == 0 {
            return RangeSpec::Unsatisfiable;
        }
        return RangeSpec::Partial(len.saturating_sub(n), len - 1);
    }
    let Ok(start) = a.parse::<u64>() else { return RangeSpec::Unsatisfiable };
    if start >= len {
        return RangeSpec::Unsatisfiable;
    }
    let end = if b.is_empty() {
        len - 1
    } else {
        match b.parse::<u64>() {
            Ok(e) if e >= start => e.min(len - 1),
            _ => return RangeSpec::Unsatisfiable,
        }
    };
    RangeSpec::Partial(start, end)
}

fn header_str<'a>(h: &'a HeaderMap, name: header::HeaderName) -> Option<&'a str> {
    h.get(name).and_then(|v| v.to_str().ok())
}

async fn handle(State(st): State<Arc<Shared>>, req: Request) -> Response {
    // 1. Host header: loopback literal / localhost on our port only (DNS-rebinding defence).
    match header_str(req.headers(), header::HOST) {
        Some(h) if host_ok(h, st.port) => {}
        _ => return status(StatusCode::FORBIDDEN),
    }
    // 2. Token (first path segment).
    let path = req.uri().path().to_string();
    let mut seg = path.trim_start_matches('/').split('/');
    match seg.next() {
        Some(t) if token_eq(t, &st.token) => {}
        _ => return status(StatusCode::FORBIDDEN),
    }
    let is_head = req.method() == Method::HEAD;
    if req.method() != Method::GET && !is_head {
        return status(StatusCode::METHOD_NOT_ALLOWED);
    }
    let rest: Vec<&str> = seg.collect();
    match rest.as_slice() {
        ["health"] => {
            let mut r = Response::new(Body::from(if is_head { "" } else { "ok" }));
            r.headers_mut()
                .insert(header::CACHE_CONTROL, HeaderValue::from_static("no-store"));
            r
        }
        ["stream", id, idx] => {
            let (Ok(id), Ok(idx)) = (id.parse::<usize>(), idx.parse::<usize>()) else {
                return status(StatusCode::NOT_FOUND);
            };
            let range = header_str(req.headers(), header::RANGE).map(str::to_string);
            stream(&st, id, idx, range.as_deref(), is_head).await
        }
        _ => status(StatusCode::NOT_FOUND),
    }
}

async fn stream(st: &Shared, id: usize, idx: usize, range: Option<&str>, head: bool) -> Response {
    let Some(h) = st.session.get(TorrentIdOrHash::Id(id)) else {
        return status(StatusCode::NOT_FOUND);
    };
    let info = h
        .with_metadata(|m| {
            m.file_infos
                .get(idx)
                .map(|f| (f.relative_filename.to_string_lossy().into_owned(), f.len))
        })
        .ok()
        .flatten();
    let Some((name, len)) = info else {
        return status(StatusCode::NOT_FOUND);
    };
    if !is_media(&name) {
        return status(StatusCode::UNSUPPORTED_MEDIA_TYPE);
    }
    let (code, start, end) = match parse_range(range, len) {
        RangeSpec::Full if len == 0 => (StatusCode::OK, 0, 0),
        RangeSpec::Full => (StatusCode::OK, 0, len - 1),
        RangeSpec::Partial(a, b) => (StatusCode::PARTIAL_CONTENT, a, b),
        RangeSpec::Unsatisfiable => {
            let mut r = status(StatusCode::RANGE_NOT_SATISFIABLE);
            if let Ok(v) = HeaderValue::from_str(&format!("bytes */{len}")) {
                r.headers_mut().insert(header::CONTENT_RANGE, v);
            }
            return r;
        }
    };
    let n = if len == 0 { 0 } else { end - start + 1 };

    let body = if head || n == 0 {
        Body::empty()
    } else {
        match tokio::time::timeout(Duration::from_secs(60), h.wait_until_initialized()).await {
            Ok(Ok(())) => {}
            _ => return status(StatusCode::SERVICE_UNAVAILABLE),
        }
        let mut fs = match h.clone().stream(idx).await {
            Ok(s) => s,
            Err(_) => return status(StatusCode::SERVICE_UNAVAILABLE),
        };
        if start > 0 && fs.seek(SeekFrom::Start(start)).await.is_err() {
            return status(StatusCode::INTERNAL_SERVER_ERROR);
        }
        Body::from_stream(ReaderStream::with_capacity(fs.take(n), 64 * 1024))
    };

    let mut r = Response::new(body);
    *r.status_mut() = code;
    let hd = r.headers_mut();
    hd.insert(header::CONTENT_TYPE, HeaderValue::from_static(mime_for(&name)));
    hd.insert(header::ACCEPT_RANGES, HeaderValue::from_static("bytes"));
    hd.insert(header::CACHE_CONTROL, HeaderValue::from_static("no-store"));
    hd.insert(header::X_CONTENT_TYPE_OPTIONS, HeaderValue::from_static("nosniff"));
    hd.insert(header::CONTENT_LENGTH, HeaderValue::from(n));
    if code == StatusCode::PARTIAL_CONTENT {
        if let Ok(v) = HeaderValue::from_str(&format!("bytes {start}-{end}/{len}")) {
            hd.insert(header::CONTENT_RANGE, v);
        }
    }
    r
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn host_check() {
        assert!(host_ok("127.0.0.1:8000", 8000));
        assert!(host_ok("localhost:8000", 8000));
        assert!(host_ok("LOCALHOST:8000", 8000));
        assert!(host_ok("[::1]:8000", 8000));
        assert!(!host_ok("127.0.0.1:8001", 8000));
        assert!(!host_ok("127.0.0.1", 8000));
        assert!(!host_ok("evil.example:8000", 8000));
        assert!(!host_ok("127.0.0.1.evil.example:8000", 8000));
        assert!(!host_ok("192.168.1.5:8000", 8000));
        assert!(!host_ok("[::1", 8000));
        assert!(!host_ok("", 8000));
    }

    #[test]
    fn ranges() {
        assert_eq!(parse_range(None, 100), RangeSpec::Full);
        assert_eq!(parse_range(Some("bytes=0-9"), 100), RangeSpec::Partial(0, 9));
        assert_eq!(parse_range(Some("bytes=90-"), 100), RangeSpec::Partial(90, 99));
        assert_eq!(parse_range(Some("bytes=90-500"), 100), RangeSpec::Partial(90, 99));
        assert_eq!(parse_range(Some("bytes=-10"), 100), RangeSpec::Partial(90, 99));
        assert_eq!(parse_range(Some("bytes=-500"), 100), RangeSpec::Partial(0, 99));
        assert_eq!(parse_range(Some("bytes=100-"), 100), RangeSpec::Unsatisfiable);
        assert_eq!(parse_range(Some("bytes=5-2"), 100), RangeSpec::Unsatisfiable);
        assert_eq!(parse_range(Some("bytes=0-1,5-6"), 100), RangeSpec::Unsatisfiable);
        assert_eq!(parse_range(Some("items=0-1"), 100), RangeSpec::Full);
    }

    #[test]
    fn media() {
        assert!(is_media("Movie.MKV"));
        assert!(is_media("a/b/c.mp4"));
        assert!(!is_media("setup.exe"));
        assert!(!is_media("noext"));
        assert!(!is_media("x.mkv.exe"));
    }

    #[test]
    fn tokens() {
        assert!(token_eq("abc", "abc"));
        assert!(!token_eq("abc", "abd"));
        assert!(!token_eq("abc", "abcd"));
    }
}
