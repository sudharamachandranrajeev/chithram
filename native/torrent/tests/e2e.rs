//! Seeder + leecher over loopback (`initial_peers`), then Range reads through the HTTP server.
//! Size: `E2E_SIZE_MB` (default 200). Run with `cargo test --release --test e2e -- --nocapture`.

use std::io::{Read, Seek, SeekFrom, Write};
use std::net::{Ipv4Addr, SocketAddr};
use std::time::{Duration, Instant};

use chithram_torrent::engine::{AddSource, Engine, StartOptions};
use librqbit::{
    AddTorrent, AddTorrentOptions, CreateTorrentOptions, ListenerMode, ListenerOptions, Session,
    SessionOptions, create_torrent, spawn_utils::BlockingSpawner,
};
use sha2::{Digest, Sha256};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpStream;

struct Resp {
    status: u16,
    headers: Vec<(String, String)>,
    body: Vec<u8>,
}

impl Resp {
    fn header(&self, name: &str) -> Option<&str> {
        self.headers
            .iter()
            .find(|(k, _)| k.eq_ignore_ascii_case(name))
            .map(|(_, v)| v.as_str())
    }
}

/// Minimal HTTP/1.1 client so the Host header can be forged.
async fn http(port: u16, method: &str, path: &str, host: &str, range: Option<&str>) -> Resp {
    let mut s = TcpStream::connect((Ipv4Addr::LOCALHOST, port)).await.unwrap();
    let mut req = format!("{method} {path} HTTP/1.1\r\nHost: {host}\r\nConnection: close\r\n");
    if let Some(r) = range {
        req.push_str(&format!("Range: {r}\r\n"));
    }
    req.push_str("\r\n");
    s.write_all(req.as_bytes()).await.unwrap();
    let mut raw = Vec::new();
    s.read_to_end(&mut raw).await.unwrap();
    let split = raw.windows(4).position(|w| w == b"\r\n\r\n").expect("no header end") + 4;
    let head = String::from_utf8_lossy(&raw[..split]).into_owned();
    let mut lines = head.lines();
    let status = lines.next().unwrap().split_whitespace().nth(1).unwrap().parse().unwrap();
    let headers = lines
        .filter_map(|l| l.split_once(':'))
        .map(|(k, v)| (k.trim().to_string(), v.trim().to_string()))
        .collect();
    let mut body = raw[split..].to_vec();
    let chunked = headers_has_chunked(&head);
    if chunked {
        body = dechunk(&body);
    }
    Resp { status, headers, body }
}

fn headers_has_chunked(head: &str) -> bool {
    head.to_ascii_lowercase().contains("transfer-encoding: chunked")
}

fn dechunk(mut b: &[u8]) -> Vec<u8> {
    let mut out = Vec::new();
    loop {
        let Some(p) = b.windows(2).position(|w| w == b"\r\n") else { break };
        let n = usize::from_str_radix(std::str::from_utf8(&b[..p]).unwrap().trim(), 16).unwrap_or(0);
        if n == 0 {
            break;
        }
        out.extend_from_slice(&b[p + 2..p + 2 + n]);
        b = &b[p + 2 + n + 2..];
    }
    out
}

fn write_random(path: &std::path::Path, bytes: usize) {
    let mut f = std::fs::File::create(path).unwrap();
    let mut x: u64 = 0x9E37_79B9_7F4A_7C15 ^ (bytes as u64);
    let mut buf = vec![0u8; 1 << 20];
    let mut left = bytes;
    while left > 0 {
        for c in buf.chunks_mut(8) {
            x ^= x << 13;
            x ^= x >> 7;
            x ^= x << 17;
            let b = x.to_le_bytes();
            c.copy_from_slice(&b[..c.len()]);
        }
        let n = left.min(buf.len());
        f.write_all(&buf[..n]).unwrap();
        left -= n;
    }
}

fn sha_of(path: &std::path::Path, off: u64, len: usize) -> String {
    let mut f = std::fs::File::open(path).unwrap();
    f.seek(SeekFrom::Start(off)).unwrap();
    let mut b = vec![0u8; len];
    f.read_exact(&mut b).unwrap();
    hex(&Sha256::digest(&b))
}

fn hex(b: &[u8]) -> String {
    b.iter().map(|x| format!("{x:02x}")).collect()
}

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn seed_leech_stream() {
    let mb: usize = std::env::var("E2E_SIZE_MB").ok().and_then(|v| v.parse().ok()).unwrap_or(200);
    let size = mb * 1024 * 1024;

    // Seeder.
    let seed_dir = tempfile::tempdir().unwrap();
    let file = seed_dir.path().join("video.mkv");
    write_random(&file, size);
    let torrent = create_torrent(
        seed_dir.path(),
        CreateTorrentOptions { piece_length: Some(1 << 20), ..Default::default() },
        &BlockingSpawner::new(2),
    )
    .await
    .unwrap();
    let torrent_bytes = torrent.as_bytes().unwrap();
    let seeder = Session::new_with_opts(
        seed_dir.path().into(),
        SessionOptions {
            dht: None,
            disable_trackers: true,
            disable_local_service_discovery: true,
            listen: Some(ListenerOptions {
                mode: ListenerMode::TcpOnly,
                listen_addr: (Ipv4Addr::LOCALHOST, 0).into(),
                ..Default::default()
            }),
            ..Default::default()
        },
    )
    .await
    .unwrap();
    let sh = seeder
        .add_torrent(
            AddTorrent::from_bytes(torrent_bytes),
            Some(AddTorrentOptions {
                overwrite: true,
                output_folder: Some(seed_dir.path().to_str().unwrap().to_owned()),
                ..Default::default()
            }),
        )
        .await
        .unwrap()
        .into_handle()
        .unwrap();
    tokio::time::timeout(Duration::from_secs(120), sh.wait_until_completed())
        .await
        .expect("seeder verify timeout")
        .unwrap();
    let peer: SocketAddr = seeder.listen_addr().expect("seeder listen addr");
    let magnet = torrent.as_magnet().to_string();
    println!("seeder ready at {peer}, magnet {magnet}");

    // Leecher = the real engine, resolving the magnet from the seeder.
    let leech_dir = tempfile::tempdir().unwrap();
    let eng = Engine::start(StartOptions {
        dir: leech_dir.path().into(),
        quota_bytes: 0,
        socks5: None,
        local_only: true,
    })
    .await
    .unwrap();
    let added = tokio::time::timeout(
        Duration::from_secs(60),
        eng.add(AddSource::Magnet(magnet), vec![peer]),
    )
    .await
    .expect("add timeout")
    .unwrap();
    println!("added: {added}");
    let id = added["id"].as_u64().unwrap();
    assert_eq!(added["files"][0]["length"].as_u64().unwrap(), size as u64);
    assert_eq!(added["files"][0]["streamable"], true);

    let port = eng.port;
    let tok = eng.token.clone();
    let host = format!("127.0.0.1:{port}");
    let base = format!("/{tok}");

    // /health
    let r = http(port, "GET", &format!("{base}/health"), &host, None).await;
    assert_eq!(r.status, 200, "health");

    // Auth failures.
    let r = http(port, "GET", &format!("/{}/health", "0".repeat(32)), &host, None).await;
    assert_eq!(r.status, 403, "bad token");
    let r = http(port, "GET", "/health", &host, None).await;
    assert_eq!(r.status, 403, "no token");
    for evil in ["evil.example", &format!("evil.example:{port}"), &format!("192.168.1.10:{port}")] {
        let r = http(port, "GET", &format!("{base}/health"), evil, None).await;
        assert_eq!(r.status, 403, "foreign host {evil}");
        let r = http(port, "GET", &format!("{base}/stream/{id}/0"), evil, Some("bytes=0-9")).await;
        assert_eq!(r.status, 403, "foreign host stream {evil}");
    }
    // No CORS.
    let r = http(port, "GET", &format!("{base}/health"), &host, None).await;
    assert!(r.header("access-control-allow-origin").is_none());

    // Range reads at 0 / 50 / 90 %.
    let chunk = 2 * 1024 * 1024usize;
    let stream_path = format!("{base}/stream/{id}/0");
    for pct in [0u64, 50, 90] {
        let off = (size as u64 / 100 * pct).min((size - chunk) as u64);
        let t = Instant::now();
        let r = http(
            port,
            "GET",
            &stream_path,
            &host,
            Some(&format!("bytes={}-{}", off, off + chunk as u64 - 1)),
        )
        .await;
        let dt = t.elapsed();
        assert_eq!(r.status, 206, "range status at {pct}%");
        assert_eq!(
            r.header("content-range").unwrap(),
            format!("bytes {}-{}/{}", off, off + chunk as u64 - 1, size)
        );
        assert_eq!(r.body.len(), chunk);
        assert_eq!(hex(&Sha256::digest(&r.body)), sha_of(&file, off, chunk), "sha at {pct}%");
        println!("range {pct}% off={off} ok in {dt:?}");
        assert!(dt < Duration::from_secs(10), "seek at {pct}% took {dt:?}");
    }

    // HEAD, suffix range, bad range.
    let r = http(port, "HEAD", &stream_path, &host, None).await;
    assert_eq!(r.status, 200);
    assert_eq!(r.header("content-length").unwrap(), size.to_string());
    assert_eq!(r.header("accept-ranges"), Some("bytes"));
    let r = http(port, "GET", &stream_path, &host, Some("bytes=-1000")).await;
    assert_eq!(r.status, 206);
    assert_eq!(hex(&Sha256::digest(&r.body)), sha_of(&file, size as u64 - 1000, 1000));
    let r = http(port, "GET", &stream_path, &host, Some(&format!("bytes={size}-"))).await;
    assert_eq!(r.status, 416);
    let r = http(port, "GET", &format!("{base}/stream/{id}/9"), &host, None).await;
    assert_eq!(r.status, 404);

    // Stats.
    let st = eng.stats(id as usize).unwrap();
    println!("stats: {st}");
    assert!(st["total_bytes"].as_u64().unwrap() > 0);

    // Remove.
    eng.remove(id as usize, true).await.unwrap();
    let r = http(port, "GET", &stream_path, &host, Some("bytes=0-9")).await;
    assert_eq!(r.status, 404);
    eng.shutdown().await;
    seeder.stop().await;
}

/// Non-media files are never served.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn non_media_rejected() {
    let dir = tempfile::tempdir().unwrap();
    std::fs::write(dir.path().join("payload.exe"), vec![7u8; 4096]).unwrap();
    let torrent = create_torrent(
        dir.path(),
        CreateTorrentOptions { piece_length: Some(1024), ..Default::default() },
        &BlockingSpawner::new(1),
    )
    .await
    .unwrap();
    let eng = Engine::start(StartOptions {
        dir: tempfile::tempdir().unwrap().keep(),
        quota_bytes: 0,
        socks5: None,
        local_only: true,
    })
    .await
    .unwrap();
    let added = eng.add(AddSource::TorrentBytes(torrent.as_bytes().unwrap().to_vec()), vec![]).await.unwrap();
    assert_eq!(added["files"][0]["streamable"], false);
    let id = added["id"].as_u64().unwrap();
    let host = format!("127.0.0.1:{}", eng.port);
    let r = http(eng.port, "GET", &format!("/{}/stream/{id}/0", eng.token), &host, None).await;
    assert_eq!(r.status, 415);
    eng.shutdown().await;
}
