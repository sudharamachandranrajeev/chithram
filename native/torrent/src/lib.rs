//! Chithram torrent engine. C ABI (JSON strings) over [`engine::Engine`].
//!
//! Every function returns a heap C string holding JSON, `{"ok":true,...}` or
//! `{"ok":false,"error":"..."}`; release it with [`ct_free`]. Calls block, so call them off the UI thread.

pub mod engine;
pub mod server;

use std::ffi::{CStr, CString, c_char};
use std::panic::{AssertUnwindSafe, catch_unwind};
use std::path::PathBuf;
use std::sync::{Arc, Mutex};
use std::time::Duration;

use engine::{AddSource, Engine, StartOptions};
use serde_json::{Value, json};
use tokio::runtime::Runtime;

struct Global {
    rt: Arc<Runtime>,
    engine: Arc<Engine>,
}

static GLOBAL: Mutex<Option<Global>> = Mutex::new(None);

fn out(v: Value) -> *mut c_char {
    CString::new(v.to_string()).unwrap_or_default().into_raw()
}

fn err(msg: impl std::fmt::Display) -> Value {
    json!({"ok": false, "error": format!("{msg:#}")})
}

fn guard(f: impl FnOnce() -> Value) -> *mut c_char {
    match catch_unwind(AssertUnwindSafe(f)) {
        Ok(v) => out(v),
        Err(_) => out(err("internal panic")),
    }
}

unsafe fn opt_str(p: *const c_char) -> Option<String> {
    if p.is_null() {
        None
    } else {
        Some(unsafe { CStr::from_ptr(p) }.to_string_lossy().into_owned())
    }
}

fn current() -> Result<(Arc<Runtime>, Arc<Engine>), Value> {
    let g = GLOBAL.lock().unwrap_or_else(|e| e.into_inner());
    match g.as_ref() {
        Some(g) => Ok((g.rt.clone(), g.engine.clone())),
        None => Err(err("not started")),
    }
}

/// Library version string (static, do not free).
#[unsafe(no_mangle)]
pub extern "C" fn ct_version() -> *const c_char {
    concat!("chithram_torrent ", env!("CARGO_PKG_VERSION"), " / librqbit 9.0.1\0").as_ptr() as *const c_char
}

/// Frees a string returned by any `ct_*` function.
///
/// # Safety
/// `p` must come from this library and not be freed twice.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn ct_free(p: *mut c_char) {
    if !p.is_null() {
        drop(unsafe { CString::from_raw(p) });
    }
}

/// Starts the engine. `{"ok":true,"port":N,"token":"hex"}`.
///
/// # Safety
/// `dir` must be a valid C string; `socks5` may be null or a valid C string.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn ct_start(dir: *const c_char, quota_bytes: u64, socks5: *const c_char) -> *mut c_char {
    let dir = unsafe { opt_str(dir) };
    let socks5 = unsafe { opt_str(socks5) }.filter(|s| !s.is_empty());
    guard(move || {
        let Some(dir) = dir else { return err("dir is null") };
        let mut g = GLOBAL.lock().unwrap_or_else(|e| e.into_inner());
        if g.is_some() {
            return err("already started");
        }
        let rt = match tokio::runtime::Builder::new_multi_thread()
            .worker_threads(4)
            .enable_all()
            .thread_name("chithram-torrent")
            .build()
        {
            Ok(rt) => Arc::new(rt),
            Err(e) => return err(e),
        };
        let opts = StartOptions { dir: PathBuf::from(dir), quota_bytes, socks5, local_only: false };
        match rt.block_on(Engine::start(opts)) {
            Ok(engine) => {
                let v = json!({"ok": true, "port": engine.port, "token": engine.token});
                *g = Some(Global { rt, engine: Arc::new(engine) });
                v
            }
            Err(e) => err(e),
        }
    })
}

/// Adds a magnet (`magnet` non-null) or `.torrent` bytes. Blocks until metadata is known (max 120 s).
/// `{"ok":true,"id":N,"name":"..","files":[{"index","path","length","streamable"}]}`.
///
/// # Safety
/// `magnet` null or a valid C string; `data` must point to `len` readable bytes when non-null;
/// `peers_json` null or a JSON array of "ip:port" strings used as initial peers.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn ct_add(
    magnet: *const c_char,
    data: *const u8,
    len: usize,
    peers_json: *const c_char,
) -> *mut c_char {
    let magnet = unsafe { opt_str(magnet) };
    let peers: Vec<std::net::SocketAddr> = unsafe { opt_str(peers_json) }
        .and_then(|s| serde_json::from_str::<Vec<String>>(&s).ok())
        .map(|v| v.iter().filter_map(|p| p.parse().ok()).collect())
        .unwrap_or_default();
    let bytes = if data.is_null() || len == 0 {
        None
    } else {
        Some(unsafe { std::slice::from_raw_parts(data, len) }.to_vec())
    };
    guard(move || {
        let (rt, engine) = match current() {
            Ok(x) => x,
            Err(e) => return e,
        };
        let src = match (magnet, bytes) {
            (Some(m), _) => AddSource::Magnet(m),
            (None, Some(b)) => AddSource::TorrentBytes(b),
            _ => return err("need a magnet or torrent bytes"),
        };
        let r = rt.block_on(async {
            tokio::time::timeout(Duration::from_secs(120), engine.add(src, peers))
                .await
                .map_err(|_| anyhow::anyhow!("timed out resolving metadata"))?
        });
        match r {
            Ok(mut v) => {
                v["ok"] = json!(true);
                v
            }
            Err(e) => err(e),
        }
    })
}

/// Torrent stats as JSON (`state`, `progress_bytes`, `total_bytes`, `live.download_speed`, ...).
#[unsafe(no_mangle)]
pub extern "C" fn ct_stats(id: u64) -> *mut c_char {
    guard(move || match current().and_then(|(_, e)| e.stats(id as usize).map_err(err)) {
        Ok(mut v) => {
            v["ok"] = json!(true);
            v
        }
        Err(e) => e,
    })
}

/// Removes a torrent; `delete_files != 0` also deletes its data.
#[unsafe(no_mangle)]
pub extern "C" fn ct_remove(id: u64, delete_files: i32) -> *mut c_char {
    guard(move || {
        let (rt, e) = match current() {
            Ok(x) => x,
            Err(e) => return e,
        };
        match rt.block_on(e.remove(id as usize, delete_files != 0)) {
            Ok(()) => json!({"ok": true}),
            Err(e) => err(e),
        }
    })
}

/// Stops the server and the session and frees the runtime.
#[unsafe(no_mangle)]
pub extern "C" fn ct_stop() -> *mut c_char {
    guard(|| {
        let g = GLOBAL.lock().unwrap_or_else(|e| e.into_inner()).take();
        let Some(g) = g else { return json!({"ok": true}) };
        g.rt.block_on(g.engine.shutdown());
        drop(g.engine);
        if let Ok(rt) = Arc::try_unwrap(g.rt) {
            rt.shutdown_timeout(Duration::from_secs(2));
        }
        json!({"ok": true})
    })
}
