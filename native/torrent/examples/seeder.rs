//! CI helper: seeds one random file over loopback so the emulator can leech it via `adb reverse`.
//! `seeder --size-mb 50 --port 16881 --dir /tmp/seed --out magnet.txt`

use std::io::Write;
use std::net::Ipv4Addr;

use librqbit::{
    AddTorrent, AddTorrentOptions, CreateTorrentOptions, ListenerMode, ListenerOptions, Session,
    SessionOptions, create_torrent, spawn_utils::BlockingSpawner,
};

fn arg(name: &str, default: &str) -> String {
    let a: Vec<String> = std::env::args().collect();
    a.iter().position(|x| x == name).and_then(|i| a.get(i + 1).cloned()).unwrap_or(default.into())
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let mb: usize = arg("--size-mb", "50").parse()?;
    let port: u16 = arg("--port", "16881").parse()?;
    let dir = std::path::PathBuf::from(arg("--dir", "seed"));
    let out = arg("--out", "magnet.txt");
    std::fs::create_dir_all(&dir)?;
    let mut f = std::fs::File::create(dir.join("sample.mkv"))?;
    let mut x: u64 = 0x1234_5678_9ABC_DEF1;
    let mut buf = vec![0u8; 1 << 20];
    for _ in 0..mb {
        for c in buf.chunks_mut(8) {
            x ^= x << 13;
            x ^= x >> 7;
            x ^= x << 17;
            c.copy_from_slice(&x.to_le_bytes()[..c.len()]);
        }
        f.write_all(&buf)?;
    }
    drop(f);
    let t = create_torrent(
        &dir,
        CreateTorrentOptions { piece_length: Some(1 << 20), ..Default::default() },
        &BlockingSpawner::new(2),
    )
    .await?;
    let s = Session::new_with_opts(
        dir.clone(),
        SessionOptions {
            dht: None,
            disable_trackers: true,
            disable_local_service_discovery: true,
            listen: Some(ListenerOptions {
                mode: ListenerMode::TcpOnly,
                listen_addr: (Ipv4Addr::LOCALHOST, port).into(),
                ..Default::default()
            }),
            ..Default::default()
        },
    )
    .await?;
    let h = s
        .add_torrent(
            AddTorrent::from_bytes(t.as_bytes()?),
            Some(AddTorrentOptions {
                overwrite: true,
                output_folder: Some(dir.to_string_lossy().into_owned()),
                ..Default::default()
            }),
        )
        .await?
        .into_handle()
        .unwrap();
    h.wait_until_completed().await?;
    std::fs::write(&out, t.as_magnet().to_string())?;
    println!("seeding {} on 127.0.0.1:{port}; magnet in {out}", dir.display());
    std::future::pending::<()>().await;
    Ok(())
}
