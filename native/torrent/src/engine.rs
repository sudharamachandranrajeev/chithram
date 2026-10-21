//! Engine: a librqbit session plus the loopback streaming server.

use std::net::{Ipv4Addr, SocketAddr};
use std::path::PathBuf;
use std::sync::Arc;

use anyhow::{Context, Result, bail};
use librqbit::{
    AddTorrent, AddTorrentOptions, AddTorrentResponse, ConnectionOptions, DhtSessionConfig,
    ListenerMode, ListenerOptions, Session, SessionOptions, api::TorrentIdOrHash,
};
use serde_json::{Value, json};
use tokio::task::JoinHandle;

use crate::server::{self, Shared};

#[derive(Clone, Debug)]
pub struct StartOptions {
    pub dir: PathBuf,
    /// Max bytes kept on disk across torrents; oldest torrents are evicted. 0 = unlimited.
    pub quota_bytes: u64,
    /// `socks5://[user:pass@]host:port`. When set, no DHT, no listener, no LSD, no UDP trackers.
    pub socks5: Option<String>,
    /// Tests: no DHT, listen on 127.0.0.1 only.
    pub local_only: bool,
}

pub enum AddSource {
    Magnet(String),
    TorrentBytes(Vec<u8>),
}

pub struct Engine {
    pub session: Arc<Session>,
    pub port: u16,
    pub token: String,
    quota_bytes: u64,
    socks5: bool,
    server: JoinHandle<()>,
}

fn random_token() -> Result<String> {
    let mut b = [0u8; 16]; // 128 bits
    getrandom::fill(&mut b).map_err(|e| anyhow::anyhow!("getrandom: {e}"))?;
    Ok(b.iter().map(|x| format!("{x:02x}")).collect())
}

/// Drop `tr=udp://...` params: UDP trackers would bypass the SOCKS5 proxy.
fn strip_udp_trackers(magnet: &str) -> String {
    let Some((head, query)) = magnet.split_once('?') else {
        return magnet.to_string();
    };
    let kept: Vec<&str> = query
        .split('&')
        .filter(|kv| {
            let v = kv.strip_prefix("tr=").unwrap_or("");
            !(kv.starts_with("tr=") && v.to_ascii_lowercase().starts_with("udp"))
        })
        .collect();
    format!("{head}?{}", kept.join("&"))
}

/// Skip one bencode value starting at `i`; returns the index just past it.
fn bskip(b: &[u8], i: usize) -> Option<usize> {
    match *b.get(i)? {
        b'i' => Some(i + b[i..].iter().position(|&c| c == b'e')? + 1),
        b'l' | b'd' => {
            let mut j = i + 1;
            while *b.get(j)? != b'e' {
                j = bskip(b, j)?;
            }
            Some(j + 1)
        }
        b'0'..=b'9' => {
            let colon = i + b[i..].iter().position(|&c| c == b':')?;
            let n: usize = std::str::from_utf8(&b[i..colon]).ok()?.parse().ok()?;
            let end = colon.checked_add(1)?.checked_add(n)?;
            (end <= b.len()).then_some(end)
        }
        _ => None,
    }
}

/// Parse a bencode byte string at `i`: (content, end).
fn bstr(b: &[u8], i: usize) -> Option<(&[u8], usize)> {
    let end = bskip(b, i)?;
    let colon = i + b[i..].iter().position(|&c| c == b':')?;
    (b[i].is_ascii_digit()).then(|| (&b[colon + 1..end], end))
}

fn is_udp(url: &[u8]) -> bool {
    url.len() >= 3 && url[..3].eq_ignore_ascii_case(b"udp")
}

fn benc_str(out: &mut Vec<u8>, s: &[u8]) {
    out.extend_from_slice(s.len().to_string().as_bytes());
    out.push(b':');
    out.extend_from_slice(s);
}

/// Rewrite `announce` / `announce-list` without udp:// trackers (UDP bypasses the SOCKS5 proxy).
/// Every other top-level value (notably `info`, whose bytes define the infohash) is copied verbatim.
/// Unparseable input yields an empty Vec (fail closed; the engine rejects it).
fn strip_udp_trackers_torrent(b: &[u8]) -> Vec<u8> {
    fn go(b: &[u8]) -> Option<Vec<u8>> {
        if *b.first()? != b'd' {
            return None;
        }
        let mut out = vec![b'd'];
        let mut i = 1;
        while *b.get(i)? != b'e' {
            let (key, kend) = bstr(b, i)?;
            let vend = bskip(b, kend)?;
            match key {
                b"announce" => {
                    let (url, _) = bstr(b, kend)?;
                    if !is_udp(url) {
                        out.extend_from_slice(&b[i..vend]);
                    }
                }
                b"announce-list" => {
                    if *b.get(kend)? != b'l' {
                        return None;
                    }
                    let mut tiers = Vec::new();
                    let mut j = kend + 1;
                    while *b.get(j)? != b'e' {
                        if *b.get(j)? != b'l' {
                            return None;
                        }
                        let mut tier = Vec::new();
                        let mut k = j + 1;
                        while *b.get(k)? != b'e' {
                            let (url, e) = bstr(b, k)?;
                            if !is_udp(url) {
                                benc_str(&mut tier, url);
                            }
                            k = e;
                        }
                        j = k + 1;
                        if !tier.is_empty() {
                            tiers.push(tier);
                        }
                    }
                    if !tiers.is_empty() {
                        out.extend_from_slice(&b[i..kend]);
                        out.push(b'l');
                        for t in tiers {
                            out.push(b'l');
                            out.extend_from_slice(&t);
                            out.push(b'e');
                        }
                        out.push(b'e');
                    }
                }
                _ => out.extend_from_slice(&b[i..vend]),
            }
            i = vend;
        }
        out.extend_from_slice(&b[i..]);
        Some(out)
    }
    // Fail closed: unparseable input would be rejected by the engine anyway, but never pass
    // through something we could not inspect.
    go(b).unwrap_or_default()
}

impl Engine {
    pub async fn start(o: StartOptions) -> Result<Engine> {
        std::fs::create_dir_all(&o.dir).context("creating download dir")?;
        let proxied = o.socks5.is_some();
        let mut so = SessionOptions {
            dht: None,
            disable_local_service_discovery: true,
            ..Default::default()
        };
        if o.local_only {
            so.listen = Some(ListenerOptions {
                mode: ListenerMode::TcpOnly,
                listen_addr: (Ipv4Addr::LOCALHOST, 0).into(),
                ..Default::default()
            });
            so.disable_trackers = true;
        } else if !proxied {
            so.dht = Some(DhtSessionConfig { persistence: None, ..Default::default() });
            so.listen = Some(ListenerOptions { mode: ListenerMode::TcpAndUtp, ..Default::default() });
        }
        if let Some(url) = &o.socks5 {
            so.connect = Some(ConnectionOptions {
                proxy_url: Some(url.clone()),
                enable_tcp: true,
                peer_opts: None,
            });
        }
        let session = Session::new_with_opts(o.dir.clone(), so)
            .await
            .context("starting torrent session")?;

        let std_l = std::net::TcpListener::bind((Ipv4Addr::LOCALHOST, 0)).context("bind loopback")?;
        std_l.set_nonblocking(true)?;
        let port = std_l.local_addr()?.port();
        let listener = tokio::net::TcpListener::from_std(std_l)?;
        let token = random_token()?;
        let shared = Arc::new(Shared { token: token.clone(), port, session: session.clone() });
        let app = server::router(shared);
        let server = tokio::spawn(async move {
            let _ = axum::serve(listener, app).await;
        });
        Ok(Engine { session, port, token, quota_bytes: o.quota_bytes, socks5: proxied, server })
    }

    pub async fn add(&self, src: AddSource, initial_peers: Vec<SocketAddr>) -> Result<Value> {
        let add = match src {
            AddSource::Magnet(m) => {
                if !m.starts_with("magnet:") {
                    bail!("not a magnet link");
                }
                AddTorrent::from_url(if self.socks5 { strip_udp_trackers(&m) } else { m })
            }
            AddSource::TorrentBytes(b) => {
                AddTorrent::from_bytes(if self.socks5 { strip_udp_trackers_torrent(&b) } else { b })
            }
        };
        let opts = AddTorrentOptions {
            initial_peers: if initial_peers.is_empty() { None } else { Some(initial_peers) },
            ..Default::default()
        };
        let (id, h) = match self.session.add_torrent(add, Some(opts)).await? {
            AddTorrentResponse::Added(id, h) | AddTorrentResponse::AlreadyManaged(id, h) => (id, h),
            AddTorrentResponse::ListOnly(_) => bail!("unexpected list-only response"),
        };
        let files: Vec<Value> = h.with_metadata(|m| {
            m.file_infos
                .iter()
                .enumerate()
                .map(|(i, f)| {
                    let p = f.relative_filename.to_string_lossy().into_owned();
                    json!({"index": i, "path": p, "length": f.len, "streamable": server::is_media(&p)})
                })
                .collect()
        })?;
        self.enforce_quota(id).await;
        Ok(json!({"id": id, "name": h.name(), "files": files}))
    }

    /// Evict the oldest other torrents (files included) while total progress exceeds the quota.
    async fn enforce_quota(&self, keep: usize) {
        if self.quota_bytes == 0 {
            return;
        }
        let mut all: Vec<(usize, u64)> = self
            .session
            .with_torrents(|it| it.map(|(id, h)| (id, h.stats().progress_bytes)).collect());
        all.sort_by_key(|(id, _)| *id);
        let mut total: u64 = all.iter().map(|(_, b)| *b).sum();
        for (id, bytes) in all {
            if total <= self.quota_bytes {
                break;
            }
            if id == keep {
                continue;
            }
            if self.session.delete(TorrentIdOrHash::Id(id), true).await.is_ok() {
                total = total.saturating_sub(bytes);
            }
        }
    }

    pub fn stats(&self, id: usize) -> Result<Value> {
        let h = self.session.get(TorrentIdOrHash::Id(id)).context("no such torrent")?;
        let mut v = serde_json::to_value(h.stats())?;
        if let Value::Object(m) = &mut v {
            m.insert("id".into(), json!(id));
            m.insert("name".into(), json!(h.name()));
        }
        Ok(v)
    }

    pub async fn remove(&self, id: usize, delete_files: bool) -> Result<()> {
        self.session.delete(TorrentIdOrHash::Id(id), delete_files).await
    }

    pub fn url_prefix(&self) -> String {
        format!("http://127.0.0.1:{}/{}", self.port, self.token)
    }

    pub async fn shutdown(&self) {
        self.server.abort();
        self.session.stop().await;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn t(announce: &str, tiers: &[&[&str]]) -> Vec<u8> {
        let mut v = b"d".to_vec();
        v.extend_from_slice(b"8:announce");
        benc_str(&mut v, announce.as_bytes());
        v.extend_from_slice(b"13:announce-listl");
        for tier in tiers {
            v.push(b'l');
            for u in *tier {
                benc_str(&mut v, u.as_bytes());
            }
            v.push(b'e');
        }
        v.extend_from_slice(b"ee4:infod6:lengthi5e4:name1:a12:piece lengthi16384e6:pieces20:aaaaaaaaaaaaaaaaaaaaee");
        v
    }

    #[test]
    fn strips_udp_from_torrent_keeps_info_verbatim() {
        let src = t(
            "udp://a:1/announce",
            &[&["udp://a:1/announce", "https://b/announce"], &["UDP://c:2"], &["http://d/a"]],
        );
        let out = strip_udp_trackers_torrent(&src);
        let s = String::from_utf8_lossy(&out);
        assert!(!s.to_ascii_lowercase().contains("udp://"), "{s}");
        assert!(s.contains("https://b/announce") && s.contains("http://d/a"));
        assert!(!s.contains("8:announce"), "udp-only announce must be removed: {s}");
        let info = b"4:infod6:lengthi5e4:name1:a12:piece lengthi16384e6:pieces20:aaaaaaaaaaaaaaaaaaaae";
        assert!(out.windows(info.len()).any(|w| w == info));
        assert_eq!(out.first(), Some(&b'd'));
        assert_eq!(out.last(), Some(&b'e'));
    }

    #[test]
    fn keeps_http_announce_and_drops_empty_list() {
        let src = t("http://x/a", &[&["udp://y:1"]]);
        let s = String::from_utf8_lossy(&strip_udp_trackers_torrent(&src)).into_owned();
        assert!(s.contains("http://x/a"));
        assert!(!s.contains("announce-list") && !s.contains("udp"));
    }

    #[test]
    fn garbage_fails_closed() {
        assert!(strip_udp_trackers_torrent(b"not bencode").is_empty());
    }
}
